"""Recreate D0-4B summary CSV from completed Measure log directories."""

import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import re
from statistics import median
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'd0-4a-20261127'))
from compare_measure import analyze, body, read_csv, timestamp

EXPECTED = {'64k': 61789, '128k': 126253, '256k': 255181}
CONTEXT = {'64k': 65536, '128k': 131072, '256k': 262144}
GIB = 1024 ** 3


class OmitTimeline:
    def writerow(self, row):
        pass


def native_seconds(stamp):
    minutes, seconds, millis, micros = map(int, stamp.split('.'))
    return minutes * 60 + seconds + millis / 1000 + micros / 1_000_000


def summarize(label, folder):
    report = analyze(label, folder, OmitTimeline())
    result = json.loads(body(folder / 'result.json'))
    assert report['tokens_pp_tg'][0] == EXPECTED[label]
    assert result['ActualContext'] == CONTEXT[label]
    assert result['ExitCode'] == 0
    assert 0 < report['tokens_pp_tg'][1] <= 256
    lines = body(folder / 'stderr.log')
    buffers = {}
    for line in report['buffers']:
        match = re.search(r'\b(CPU(?:_Mapped)?|ROCm0|ROCm_Host)\s+(model|KV|RS|compute|output) buffer size =\s*([0-9.]+) MiB', line)
        if match:
            device, purpose, amount = match.groups()
            key = f'{device}_{purpose}_MiB'
            buffers[key] = buffers.get(key, 0) + float(amount)

    load, context, warmup, prompt, pp, tg, native_end, end = report['boundaries_s']
    pp_s, tg_s = (value / 1000 for value in report['pp_tg_ms'])
    pp_rate, tg_rate = report['pp_tg_tok_s']
    prompt_tokens, generated = report['tokens_pp_tg']
    start = datetime.fromisoformat(report['start'])
    metric = {
        'context': CONTEXT[label], 'prompt_tokens': prompt_tokens, 'generated_tokens': generated,
        'pp_tok_s': pp_rate, 'tg_tok_s': tg_rate, 'pp_s': pp_s, 'tg_s': tg_s,
        'cli_s': end, 'tensor_load_s': context - load, 'tensor_load_started_s': load,
        'context_started_s': context, 'warmup_started_s': warmup, 'first_prompt_s': prompt,
        'estimated_pp_started_s': pp, 'estimated_tg_started_s': tg,
        'native_eval_report_s': native_end, 'ram_samples': result['RamDetail']['Samples'],
        'ram_missing': result['RamDetail']['NativeMissing'],
        'low_ram_samples': report['low_count'], 'low_ram_intervals': len(report['low_intervals']),
        'longest_observed_low_ram_s': max((r[3] for r in report['low_intervals'] if r[3] is not None),default=None),
        **buffers,
    }
    for stage in ('tensor_load', 'PP', 'TG'):
        metric[stage + '_min_free_GiB'] = report['stages'][stage]['min_free_MiB'] / 1024
    metric.update({
        key.removesuffix('Bytes') + '_GiB': value
        for key, value in report['ram_max_GiB'].items()
    })
    metric.update(report['resource_peaks'])
    metric.update(report['paging_max'])
    metric['resources_n'] = report['resource_rows']
    metric['adlx_vram_mb_max'] = report['adlx']['ALL']['peak']['gpu_vram_mb']
    metric['adlx_temp_c_max'] = report['adlx']['ALL']['peak']['gpu_temp_c']
    for stage in ('PP', 'TG'):
        gpu = report['adlx'][stage]
        metric[f'{stage}_adlx_n'] = gpu['n']
        metric.update({f'{stage}_{key}_median': value for key, value in gpu['med'].items()})

    # Native progress is cumulative. Each interval rate is calculated from two lines in the same run.
    progress = [
        (int(count), native_seconds(stamp))
        for stamp, count in re.findall(
            r'^([0-9.]+) I .*prompt processing, n_tokens =\s*(\d+),', lines, flags=re.M
        )
    ]
    def boundary(fraction):
        return min(progress, key=lambda point: abs(point[0] - fraction * prompt_tokens))
    if len(progress) >= 4:
        for name, bounds in (('early', (0.1, 0.3)), ('late', (0.7, 0.9))):
            count1, time1 = boundary(bounds[0])
            count2, time2 = boundary(bounds[1])
            if count2 <= count1 or time2 <= time1:
                continue
            metric[f'pp_{name}_first_token'] = count1
            metric[f'pp_{name}_last_token'] = count2
            metric[f'pp_{name}_tok_s'] = (count2 - count1) / (time2 - time1)
    metric['native_pp_progress_n'] = len(progress)
    adlx = read_csv(folder / 'gpu-metrics.csv')
    resources = read_csv(folder / 'resources.csv')
    midpoint = (pp + tg) / 2
    for name, lo, hi in (('first_half', pp, midpoint), ('second_half', midpoint, tg)):
        gpu_rows = [
            row for row in adlx if row['adlx_result'] == '0' and
            lo <= (timestamp(row['timestamp_local'] + '+09:00') - start).total_seconds() < hi
        ]
        for key in ('gpu_clock_mhz', 'gpu_vram_clock_mhz', 'gpu_temp_c', 'gpu_power_w'):
            samples = [float(row[key]) for row in gpu_rows if row.get(key)]
            metric[f'PP_{name}_{key}_median'] = median(samples) if samples else None
        metric[f'PP_{name}_adlx_n'] = len(gpu_rows)
        page_input = [
            float(row['PagesInput_PerSec']) for row in resources
            if row['PerfMonSystemStatus'] == 'Complete' and row['PagesInput_PerSec'] and
            lo <= (timestamp(row['TimestampUtc']) - start).total_seconds() < hi
        ]
        metric[f'PP_{name}_page_input_per_s_median'] = median(page_input) if page_input else None
        metric[f'PP_{name}_page_input_per_s_max'] = max(page_input, default=None)
    metric['response_sha256'] = report['response_sha']
    return metric


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv', type=Path)
    parser.add_argument('--run', action='append', nargs=2, metavar=('LABEL', 'MEASURE_DIR'), required=True)
    args = parser.parse_args()
    metrics = [summarize(label, Path(directory)) for label, directory in args.run]
    baseline = metrics[0]
    if baseline['context'] != CONTEXT['64k']:
        parser.error('the first Measure folder must be the 64k baseline')
    for values in metrics:
        for key in ('pp_tok_s', 'tg_tok_s', 'pp_s', 'prompt_tokens'):
            values[key + '_pct_of_64k'] = 100 * values[key] / baseline[key]
    columns = list(dict.fromkeys(key for values in metrics for key in values))
    with args.csv.open('w', newline='') as target:
        writer = csv.DictWriter(target, columns, lineterminator='\n')
        writer.writeheader()
        writer.writerows(metrics)
    print(json.dumps(metrics, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
