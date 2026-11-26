import argparse
import csv
import hashlib
import json
from datetime import datetime
from pathlib import Path
from statistics import median

GIB = 1024 ** 3
MIB = 1024 ** 2
RAM = [
    'PhysicalTotalBytes', 'UsedRAMBytes', 'AvailableRAMBytes', 'CommitTotalBytes',
    'CommitLimitBytes', 'SystemCacheBytes', 'WorkingSetBytes', 'PrivateBytes', 'VirtualBytes',
]


def body(path):
    return path.read_text(encoding='utf-8-sig')


def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as source:
        return list(csv.DictReader(source))


def timestamp(value):
    return datetime.fromisoformat(value)


def stamp(lines, marker):
    line = next(l for l in lines if marker in l)
    minutes, seconds, millis, micros = [int(x) for x in line.split()[0].split('.')]
    return minutes * 60 + seconds + millis / 1000 + micros / 1e6


def get_stat(rows, key, stat=max):
    values = [float(r[key]) for r in rows if r.get(key) not in (None, '')]
    return stat(values) if values else None


def analyze(label, folder, output):
    result = json.loads(body(folder / 'result.json'))
    ram = result['RamDetail']
    start = timestamp(ram['TargetStartUtc'])
    end = (timestamp(ram['TargetOsExitUtc']) - start).total_seconds()
    lines = body(folder / 'stderr.log').splitlines()
    load = stamp(lines, 'loading model tensors')
    context = stamp(lines, 'constructing llama_context')
    warmup = stamp(lines, 'warming up the model')
    new_prompt = stamp(lines, '| new prompt,')
    native_eval_end = stamp(lines, '| prompt eval time')
    # Reference publication estimated PP/TG by backing off from native exit.
    tg = end - result['GenerationEvalMilliseconds'] / 1000
    pp = tg - result['PromptEvalMilliseconds'] / 1000
    boundaries = [
        (0, 'pre'), (load, 'initialization'), (context, 'tensor_load'), (warmup, 'context'),
        (new_prompt, 'warmup_to_prompt'), (pp, 'prompt_setup'), (tg, 'PP'), (end, 'TG'),
    ]

    def phase(elapsed):
        for boundary, name in boundaries:
            if elapsed < boundary:
                return name
        return 'recovery'

    samples = []
    low_groups = []
    active = []
    for row in read_csv(folder / 'ram-detail.csv'):
        t = (timestamp(row['TimestampUtc']) - start).total_seconds()
        stage = phase(t)
        output.writerow([label, f'{t:.6f}', stage, row['Phase'], row['NativeStatus'],
                         row['ProcessStatus'], row['IntervalMsActual'], *(row[k] for k in RAM)])
        samples.append((t, stage, row))
        available = row['AvailableRAMBytes']
        if (row['NativeStatus'] == 'Complete' and available and
                int(available) < GIB and 0 <= t < end):
            if active and t - active[-1] > 0.5:
                low_groups.append(active)
                active = []
            active.append(t)
        elif active:
            low_groups.append(active)
            active = []
    if active:
        low_groups.append(active)
    stages = {}
    for stage in dict.fromkeys(x[1] for x in samples):
        rows = [row for _, row_stage, row in samples
                if row_stage == stage and row['NativeStatus'] == 'Complete']
        minimum = get_stat(rows, 'AvailableRAMBytes', min)
        stages[stage] = {'samples': len(rows), 'min_free_MiB': minimum / MIB if minimum is not None else None}
    resource_rows = read_csv(folder / 'resources.csv')
    adlx = read_csv(folder / 'gpu-metrics.csv')
    adlx_summary = {}
    gpu_metrics = ('gpu_usage_pct', 'gpu_clock_mhz', 'gpu_vram_clock_mhz', 'gpu_temp_c', 'gpu_power_w')
    for stage in ['PP', 'TG', 'ALL']:
        rows = [
            row for row in adlx if row['adlx_result'] == '0' and (
                stage == 'ALL' or
                phase((timestamp(row['timestamp_local'] + '+09:00') - start).total_seconds()) == stage
            )
        ]
        adlx_summary[stage] = {
            'n':len(rows),
            'med': {k: get_stat(rows, k, median) for k in gpu_metrics},
            'peak':{k:get_stat(rows,k) for k in ('gpu_vram_mb','gpu_temp_c')}}
    system_perf = [row for row in resource_rows if row['PerfMonSystemStatus'] == 'Complete']
    peak_metrics = (
        'AdapterDedicated_GiB', 'AdapterShared_GiB', 'TargetGPUDedicated_GiB',
        'TargetGPUShared_GiB', 'DiskRead_MiBps', 'DiskWrite_MiBps',
    )
    active_ram = [row for t, _, row in samples if 0 <= t < end and row['NativeStatus'] == 'Complete']
    stdout = body(folder / 'stdout.normalized.log')
    response = stdout.split('... (truncated)',1)[1].rsplit('Exiting...',1)[0].strip()
    return {
        'tokens_pp_tg': [result['PromptTokens'],result['GeneratedTokens']],
        'pp_tg_tok_s': [result['PromptTokensPerSecond'],result['GenerationTokensPerSecond']],
        'pp_tg_ms': [result['PromptEvalMilliseconds'],result['GenerationEvalMilliseconds']],
        'quality':result['MonitoringQuality'],
        'command': json.loads(body(folder / 'conditions.json'))['Command'],
        'start':start.isoformat(), 'finished_at':result['FinishedAt'],
        'buffers':[ln for ln in lines if 'buffer size' in ln or 'layers to GPU' in ln or 'load time' in ln],
        'boundaries_s':[load,context,warmup,new_prompt,pp,tg,native_eval_end,end],
        'stages':stages, 'low_count':sum(map(len,low_groups)),
        'low_intervals':[(g[0],g[-1],len(g),g[-1]-g[0] if len(g)>1 else None) for g in low_groups],
        'ram_max_GiB':{k:get_stat(active_ram, k) / GIB for k in RAM if k!='AvailableRAMBytes'},
        'resource_rows':len(resource_rows),
        'resource_peaks':{k:get_stat(resource_rows,k) for k in peak_metrics},
        'system_perf_rows':len(system_perf), 'paging_max':{k:get_stat(system_perf,k) for k in ('PagesInput_PerSec','PageReads_PerSec','PageFaults_PerSec')},
        'adlx':adlx_summary, 'response_sha':hashlib.sha256(response.encode()).hexdigest(),
        'fingerprint':result['OutputFingerprintSha256'],'exit':[result['Status'],result['ExitCode'],result['ExitCodeSource']],
        'recovery':[ram.get('SystemRecovery'),ram.get('GpuRecovery')],
    }


def main():
    parser = argparse.ArgumentParser(description='Compare the two complete D0-4A Measure log directories.')
    parser.add_argument('baseline', type=Path)
    parser.add_argument('patched', type=Path)
    parser.add_argument('csv', type=Path)
    args = parser.parse_args()
    with args.csv.open('w', newline='') as target:
        writer = csv.writer(target, lineterminator='\n')
        writer.writerow(['run', 'elapsed_s', 'analysis_phase', 'monitor_phase', 'native_status',
                         'process_status', 'interval_ms_actual', *RAM])
        summary = {'baseline': analyze('baseline', args.baseline, writer),
                   'patched': analyze('patched', args.patched, writer)}
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
