#!/usr/bin/env python3
"""Build/run only the external Master agent and a test-only response fixture."""
from pathlib import Path
import argparse,hashlib,json,os,re,signal,subprocess,sys,time,shutil
ROOT=Path(__file__).resolve().parents[1]
CASES=['smoke','w_first','aw_first','bursts','same_id','reorder','backpressure','error_resp','invalid_item','reset_aw','reset_w','reset_b','reset_bvalid','reset_queued','neg_orphan','neg_early','neg_last','neg_bstable','neg_duplicate','neg_awstable','neg_wstable','neg_strb']
def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['build','test','regress']);p.add_argument('--case',default='smoke');p.add_argument('--seed',type=int,default=7);p.add_argument('--data-width',type=int,default=32);p.add_argument('--id-width',type=int,default=2);p.add_argument('--max-out',type=int,default=2);p.add_argument('--trace',action='store_true');a=p.parse_args()
 local=Path(os.environ.get('AXI_LOCAL_UVM',str(ROOT.parent/'local-uvm')))
 alias=Path('/tmp')/('axi-master-'+hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]);alias.mkdir(exist_ok=True)
 for name,target in [('project',ROOT),('local',local)]:
  link=alias/name
  if link.is_symlink():
   if link.resolve()!=target.resolve():raise RuntimeError('wrong alias target')
  elif link.exists():raise RuntimeError('alias occupied')
  else:link.symlink_to(target,target_is_directory=True)
 proj=alias/'project';tool=alias/'local/tools/verilator-5.052';uvm=alias/'local/third_party/1800.2-2020.3.2'
 tag=f'd{a.data_width}_i{a.id_width}';build=proj/'build'/tag;logs=proj/'logs'/tag;logs.mkdir(parents=True,exist_ok=True)
 env=dict(os.environ,LC_ALL='C',LANG='C',VERILATOR_ROOT=str(tool/'share/verilator'))
 sources=[proj/'dv/interfaces/axi_write_if.sv',proj/'dv/master/axi_master_pkg.sv',proj/'dv/checkers/axi_write_checker.sv',proj/'dv/tests/master/master_test_pkg.sv',proj/'dv/tests/master/top.sv']
 digest=hashlib.sha256(b''.join(x.read_bytes() for x in sorted((ROOT/'dv').rglob('*')) if x.is_file())).hexdigest()
 def execute(cmd,log,timeout):
  started=time.time()
  with log.open('w') as f:
   f.write('COMMAND '+json.dumps(cmd)+'\n');f.flush()
   proc=subprocess.Popen(cmd,cwd=logs,env=env,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
   try:code=proc.wait(timeout=timeout)
   except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait();code=124
  return code,round(time.time()-started,2)
 if a.action=='build':
  build.mkdir(parents=True,exist_ok=True)
  cmd=[str(tool/'bin/verilator'),'--binary','--timing','--assert','--coverage-user','--vpi','--language','1800-2017','-Wno-fatal','--top-module','top','-j','4','--Mdir',str(build),f'+define+AXI_DATA_W={a.data_width}',f'+define+AXI_ID_W={a.id_width}',*[f'+incdir+{d}' for d in [uvm/'src',proj/'dv/interfaces',proj/'dv/master']],'-CFLAGS','-DUVM_NO_MALLOC -I'+str(uvm/'src/dpi'),str(uvm/'src/uvm_pkg.sv'),*[str(s) for s in sources],str(uvm/'src/dpi/uvm_dpi.cc')]
  code,seconds=execute(cmd,logs/'build.log',900)
  print(json.dumps(dict(build_exit=code,seconds=seconds,log=str(ROOT/'logs'/tag/'build.log'))),flush=True)
  if code:print((logs/'build.log').read_text()[-7000:]);return 1
  (build/'source.sha256').write_text(digest);return 0
 if not (build/'Vtop').exists() or (build/'source.sha256').read_text()!=digest:raise RuntimeError('Build missing/stale: run build for this configuration')
 runs=[(a.case,a.seed)] if a.action=='test' else [(c,a.seed) for c in CASES]+[('random',s) for s in (7,41,2026)]
 results=[]
 for case,seed in runs:
  path=logs/f'{case}_s{seed}_o{a.max_out}.log'
  code,seconds=execute([str(build/'Vtop'),f'+CASE={case}',f'+verilator+seed+{seed}',f'+MAX_OUT={a.max_out}',*(['+TRACE'] if a.trace else [])],path,60)
  if (logs/'coverage.dat').exists():shutil.copy2(logs/'coverage.dat',path.with_suffix('.coverage.dat'))
  t=path.read_text();counts={k:int(v) for k,v in re.findall(r'UVM_(ERROR|FATAL)\s*:\s*(\d+)',t)}
  ok=code==0 and '[CHECK_PASS]' in t and '$finish' in t and counts=={'ERROR':0,'FATAL':0}
  if case.startswith('neg_'):ok=ok and '[EXPECTED_DETECTION]' in t
  row=dict(case=case,seed=seed,max_out=a.max_out,passed=ok,exit=code,seconds=seconds,counts=counts,log=path.name)
  results.append(row);print(json.dumps(row),flush=True)
  if not ok:print(t[-4500:],flush=True)
 report=dict(source_sha256=digest,data_width=a.data_width,id_width=a.id_width,uvm='2020.3.2',verilator=subprocess.check_output([str(tool/'bin/verilator'),'--version'],env=env,text=True).strip(),results=results)
 (logs/('results.json' if a.action=='regress' else f'{a.case}_s{a.seed}_o{a.max_out}_result.json')).write_text(json.dumps(report,indent=2)+'\n')
 return 0 if all(x['passed'] for x in results) else 1
if __name__=='__main__':
 try:sys.exit(main())
 except Exception as e:print(str(e),file=sys.stderr);sys.exit(1)
