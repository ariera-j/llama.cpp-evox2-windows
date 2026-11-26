from analyze import *
for label in ['M004','R2D','R3D','R3C','R3B','VKCLI','HIPCLI']:
 p=runs[label]
 j=load(p/'result.json')
 start=utc(j['TargetLifecycle']['StartedUtc'])
 ev=[json.loads(l) for l in (p/'ram-events.jsonl').read_text(encoding='utf-8-sig').splitlines()]
 def mark(phase):
  return float(next(utc(x['TimestampUtc']) for x in ev if x['Data'].get('Phase')==phase)-start)
 b=mark('ContextInitialization')
 r=csvs(p/'resources.csv')
 def times(q):
  return float(utc(q['TimestampUtc'])-start)
 def stat(filter_,k):
  x=[float(q[k]) for q in r if q[k] and filter_(times(q))]
  return (min(x),round(st.median(x),2),max(x)) if x else '-'
 print(label,'mid and last below ctx\n ',[(k,stat(lambda t:7<t<45,k),stat(lambda t:b-14<t<b,k)) for k in ('DiskRead_MiBps','DiskWrite_MiBps','PagesInput_PerSec','PageFaults_PerSec','CPU_Percent','Disk_Percent')])
 if (p/'ram-detail.csv').exists():
  rr=csvs(p/'ram-detail.csv')
  for q in rr:
   q['t']=float(utc(q['TimestampUtc'])-start)
   q['free']=float(q['AvailableRAMBytes'])/(1024**3)
   q['ws']=float(q['WorkingSetBytes'])/(1024**3) if q['WorkingSetBytes'] else None
  print('brief')
  table([q for q in rr if (label=='HIPCLI' and ((29.8<=q['t']<=34.0) or (62.8<=q['t']<=66.1))) or (label=='R3D' and 55.5<=q['t']<=57.6)],['TimestampUtc','t','free','ws'])
 if label in ['R3D','HIPCLI']:
  print('quality', {k:v for k,v in j.get('MonitoringQuality',{}).items()})
  print('post RAM',j['RamDetail']['SystemRecovery'],j['RamDetail']['GpuRecovery'])
for p in Path('manifests').rglob('*.json'):
 j=load(p); print(p,j['Source']['Commit'],[(x['Name'],x['Sha256']) for x in j['Artifacts'] if x['Name'] in ['llama-bench.exe','llama-cli.exe']])
p=Path('repo/docs/evox2/iq2-s-vulkan-matvec-20261125')
m=load(p/'logs/build-i2mv-manifest.json')
print('i2mv',m['Source']['Commit'], m['BuildIdentity'],[(x['Name'],x['Sha256']) for x in m['Artifacts'] if x['Name']=='llama-bench.exe'])
hashes={q['file']:q for q in csvs(p/'raw-log-sha256.csv')}
for f in sorted(root.glob('iq2*/*.stderr.log')):
 h=hashlib.sha256(f.read_bytes()).hexdigest()
 print(f.name,h==hashes[f.name]['sha256'],f.stat().st_size==int(hashes[f.name]['bytes']),load(f.with_name(f.name.replace('stderr.log','command.json')))['started'])
