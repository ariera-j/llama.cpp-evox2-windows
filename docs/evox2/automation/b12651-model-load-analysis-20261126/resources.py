from analyze import *
G=1024**3
keys=['AvailableRAMBytes','CommitTotalBytes','SystemCacheBytes','WorkingSetBytes','PrivateBytes']
rk=['FreeRAM_GiB','Committed_GiB','SystemCache_GiB','TargetWS_GiB','TargetPrivate_GiB','TargetGPUDedicated_GiB','TargetGPUShared_GiB','CPU_Percent','Disk_Percent','DiskRead_MiBps','DiskWrite_MiBps','PagesInput_PerSec','PageReads_PerSec','PageFaults_PerSec']
for label in ['M004','R2D','R3D','R3C','R3B','VKCLI','HIPCLI']:
 p=runs[label]
 j=load(p/'result.json')
 start=utc(j['TargetLifecycle']['StartedUtc'])
 exit=utc(j['TargetLifecycle']['ExitedUtc'])
 ev=[json.loads(l) for l in (p/'ram-events.jsonl').read_text(encoding='utf-8-sig').splitlines()]
 pid=next(x['Data'] for x in ev if x['Event']=='TargetPidObserved')
 tickref=next(x for x in ev if x['Event']=='TargetPidObserved')
 ram=[]
 if (p/'ram-detail.csv').exists():
  ram=csvs(p/'ram-detail.csv')
 for q in ram:
  assert q['RunId']==p.name
  if q['TargetPID']:
   assert q['TargetPID']==str(pid['Id']) and q['TargetStartUtc']==pid['StartUtc']
  q['t']=float(utc(q['TimestampUtc'])-start)
  q['tick']=float(q['StopwatchTicks'])/tickref['StopwatchFrequency']
  for k in keys:
   q[k]=float(q[k])/G if q[k] else None
 print('\n',label,'ram count',len(ram),'proc',dict((k,len(list(gr))) for k,gr in groupby(sorted(q['ProcessStatus'] for q in ram))))
 if ram:
  print('ram utc/tick spread',max(abs((q['tick']-int(tickref['StopwatchTicks'])/tickref['StopwatchFrequency'])-(q['t']-float(utc(tickref['TimestampUtc'])-start))) for q in ram))
  print('Pre medians',*(round(st.median(q[k] for q in ram if q['Phase']=='Pre'),3) for k in keys[:3]))
  for k in keys:
   rs=[q for q in ram if q[k] is not None and 0<=q['t']<=float(exit-start)]
   if rs:
    q=min(rs,key=lambda x:x[k]) if k.startswith('Available') else max(rs,key=lambda x:x[k])
    print(k,'extreme',*(round(q[key],3) if q[key] is not None else '-' for key in ['t']+keys))
  if label in ['HIPCLI','R3D','R2D','M004','VKCLI']:
   points=[0,2,6,10,15,20,25,30,35,40,45,48,49,50,51,52,53,54,55,56,57,58,59,60,62,64,66,70,78,86,95,102,106]
   if label in ['R3D','R2D','M004','VKCLI']: points=[0,6,10,20,30,40,42,44,46,48,50,52,55,58,60,62,64,66,70,78,86,94,102,106]
   print('RAM at closest timestamp',keys)
   table([min(ram,key=lambda q:abs(q['t']-t)) for t in points if t <= ram[-1]['t']],['t']+keys)
  for threshold in (1,.5,.125):
   inds=[i for i,q in enumerate(ram) if q[keys[0]] is not None and q[keys[0]]<threshold]
   if inds:
    runs_i=[(xs[0],xs[-1]) for _,g in groupby(enumerate(inds),key=lambda pair:pair[0]-pair[1]) if (xs:=[i for _,i in g])]
    print('threshold',threshold,len(inds),[(round(ram[a]['t'],3),round(ram[b]['t'],3),round(ram[b]['tick']-ram[a]['tick'],3),round(ram[a-1]['t'],3),round(ram[b+1]['t'],3)) for a,b in runs_i])
 res=csvs(p/'resources.csv')
 for q in res:
  assert q['RunId']==p.name
  if q['TargetPID']:
   assert q['TargetPID']==str(pid['Id']) and abs(float(utc(q['TargetProcessStart'])-start))<.000002
  q['t']=float(utc(q['TimestampUtc'])-start)
  q['n']=float(utc(q['NativeMemoryTimestampUtc'])-start) if q['NativeMemoryTimestampUtc'] else None
  q['w']=float(utc(q['ProcessMemoryTimestampUtc'])-start) if q['ProcessMemoryTimestampUtc'] else None
  for k in rk:
   q[k]=float(q[k]) if q[k] else None
 print('resource columns',rk)
 table([q for q in res if q['t']<68],['t','n','w']+rk)
 for k in rk:
  rr=[q for q in res if q[k] is not None and q['t']<68]
  if rr:
   q=max(rr,key=lambda x:x[k])
   print(k, len(rr),round(st.median(x[k] for x in rr),3),q[k],round(q['t'],3))
 gpu=csvs(p/'gpu-metrics.csv')
 for q in gpu:
  q['t']=float(utc(q['timestamp_local']+'+09:00')-start)
  for k in ('gpu_usage_pct','gpu_vram_mb','gpu_vram_clock_mhz'): q[k]=float(q[k]) if q[k] not in ('','NA') else None
 print('ADLX t usage vram_mb vram_clock')
 table([q for q in gpu if 0<=q['t']<70],['t','gpu_usage_pct','gpu_vram_mb','gpu_vram_clock_mhz'])
