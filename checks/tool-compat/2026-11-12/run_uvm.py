from pathlib import Path
import subprocess,os,json,time
r=Path('/tmp/axi-compat-20261112');a=r/'local';u=a/'third_party/1800.2-2020.3.2'
e=dict(os.environ,LC_ALL='C',LANG='C',VERILATOR_ROOT=str(a/'tools/verilator-5.052/share/verilator'))
c=[str(a/'tools/verilator-5.052/bin/verilator'),'--binary','--timing','--assert','--vpi','--language','1800-2017','-Wno-fatal','--top-module','top','-j','4','--Mdir',str(r/'obj_uvm'),'+incdir+'+str(u/'src'),'-CFLAGS','-DUVM_NO_MALLOC -I'+str(u/'src/dpi'),str(u/'src/uvm_pkg.sv'),str(r/'uvm_response.sv'),str(u/'src/dpi/uvm_dpi.cc')]
t=time.time()
with (r/'uvm.build.log').open('w') as f: b=subprocess.run(c,env=e,stdout=f,stderr=subprocess.STDOUT,timeout=600)
out=dict(command=c,build_exit=b.returncode,seconds=round(time.time()-t,2))
if b.returncode:out['diagnostic']=(r/'uvm.build.log').read_text()[-3000:]
else:
 x=subprocess.run([str(r/'obj_uvm/Vtop')],env=e,capture_output=True,text=True,timeout=20,cwd=r)
 (r/'uvm.run.log').write_text(x.stdout+x.stderr);out.update(run_exit=x.returncode,output=x.stdout+x.stderr)
(r/'uvm-result.json').write_text(json.dumps(out,indent=2));print(json.dumps(out),flush=True)
