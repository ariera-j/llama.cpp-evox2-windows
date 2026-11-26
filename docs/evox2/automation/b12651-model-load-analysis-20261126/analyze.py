import csv,datetime as dt,hashlib,json,statistics as st
from pathlib import Path
from decimal import Decimal
from itertools import groupby
from bisect import bisect_left
def utc(s):
 return Decimal(int(dt.datetime.fromisoformat(s[:19]).replace(tzinfo=dt.timezone.utc).timestamp())) + Decimal('0'+s[19:-1]) if s.endswith('Z') else Decimal(str(dt.datetime.fromisoformat(s).timestamp()))
def load(p):
 return json.loads(p.read_text(encoding='utf-8-sig'))
def csvs(p):
 with p.open(encoding='utf-8-sig') as f:
  return list(csv.DictReader(f))
def table(rs,keys):
 for r in rs:
  print(' '.join(f'{r.get(k, None):.3f}' if isinstance(r.get(k),(float,Decimal)) else str(r.get(k,'-') or '-') for k in keys))
root=Path('logs')
labels=['M001','M002','M003','M004','R2D','R3B','R3D','R3A','R3C','VKCLI','HIPCLI']
runs=dict(zip(labels, sorted(root.glob('20*')),strict=True))
if __name__=='__main__':
 for label,p in runs.items():
  j=load(p/'result.json')
  start=utc(j['TargetLifecycle']['StartedUtc'])
  ev=[json.loads(l) for l in (p/'ram-events.jsonl').read_text(encoding='utf-8-sig').splitlines()]
  pid=next(x for x in ev if x['Event']=='TargetPidObserved')
  print(label, pid['Data']['Id'],pid['Data']['StartUtc'],j['TargetLifecycle']['ProcessSeconds'],j['DurationSeconds'])
  assert pid['Data']['StartUtc']==j['TargetLifecycle']['StartedUtc']
  a=[]
  stderr=(p/'stderr.log').read_text(encoding='utf-8-sig',errors='replace').split('\n')
  for x in ev:
   assert x['RunId']==p.name
   d=x['Data']
   if x['Event']=='LogMarkerReceived' and d['Stream']=='stderr':
    line=stderr[d['Line']-1].strip()
    if any(s in line for s in ('loaded meta data','loading model tensors','model buffer size','constructing llama_context','initializing llama_context','reserve took','warmup prompt','warmup generation','warming up','prompt run','generation run','prompt eval time','eval time')):
     a.append((float(utc(x['TimestampUtc'])-start),d['Line'],line))
  print('  '+' '.join(f'{t:.3f}@{n}' for t,n,l in a))
  if label in ('M001','R3D','R2D','M004','HIPCLI','VKCLI'):
   print('  '+'\n  '.join(f'{t:.3f} {n} {l}' for t,n,l in a))
   print('  '+str([l.strip() for l in stderr if 'load time =' in l or 'total time =' in l])[:500])
