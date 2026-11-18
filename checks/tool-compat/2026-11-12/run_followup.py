from pathlib import Path
import os,subprocess,json,time
from concurrent.futures import ThreadPoolExecutor
root=Path('/tmp/axi-compat-20261112')
local=Path('/Users/shiyutian/Desktop/Projects/验证/local-uvm')
alias=root/'local'
if not alias.exists(): alias.symlink_to(local)
v=alias/'tools/verilator-5.052/bin/verilator'
env=dict(os.environ,LC_ALL='C',LANG='C',VERILATOR_ROOT=str(alias/'tools/verilator-5.052/share/verilator'))
def run(name):
 cmd=[str(v),'--binary','--timing','--assert','--language','1800-2017','-Wno-fatal','--top-module','top','-j','2','--Mdir',str(root/('obj_'+name)),str(root/(name+'.sv'))]
 if name.startswith('coverage'):cmd+=['--coverage']
 started=time.time()
 try:
  with (root/(name+'.build.log')).open('w') as f: b=subprocess.run(cmd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=240)
  result=dict(name=name,build_exit=b.returncode,seconds=round(time.time()-started,2),command=cmd)
  if b.returncode==0:
   runs=[]
   for args in ([[],['+FAULT']] if name.startswith('assertions') else [[]]):
    x=subprocess.run([str(root/('obj_'+name)/'Vtop'),*args],env=env,capture_output=True,text=True,timeout=15,cwd=root)
    log=name+('.fault' if args else '')+'.run.log'; (root/log).write_text(x.stdout+x.stderr)
    runs.append(dict(args=args,exit=x.returncode,log=log,output=x.stdout+x.stderr))
   result['runs']=runs
  else: result['diagnostic']=(root/(name+'.build.log')).read_text()[-2500:]
 except subprocess.TimeoutExpired:result=dict(name=name,timeout=True)
 print(json.dumps(result),flush=True);return result
with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(run,['coverage_basic','assertions_reset']))
(root/'followup-results.json').write_text(json.dumps(results,indent=2))
