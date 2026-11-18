#!/usr/bin/env python3
"""Independent passive Slave Monitor checks with exact expected diagnostics."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
CASES = ['smoke','snapshot','w_first','order','reset','neg_orphan','neg_early','neg_last','neg_strb','neg_awstable','neg_wstable','neg_bstable']
EXPECTED = dict(neg_orphan='SM_ORPHAN_B', neg_early='SM_EARLY_B', neg_last='SM_W_LENGTH', neg_strb='SM_WSTRB',
                neg_awstable='SM_AW_STABILITY', neg_wstable='SM_W_STABILITY', neg_bstable='SM_B_STABILITY')
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('action', choices=['build','regress','test'])
p.add_argument('--case', choices=CASES, default='smoke')
a = p.parse_args()
ALIAS = Path('/tmp') / ('axi-slave-monitor-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
ALIAS.mkdir(exist_ok=True)
for name,target in [('project',ROOT),('local',ROOT.parent/'local-uvm')]:
    link = ALIAS/name
    if link.is_symlink():
        assert link.resolve() == target.resolve()
    elif link.exists():
        raise RuntimeError('Alias path occupied')
    else:
        link.symlink_to(target,target_is_directory=True)
PROJECT = ALIAS/'project'
TOOL = ALIAS/'local/tools/verilator-5.052'
UVM = ALIAS/'local/third_party/1800.2-2020.3.2'
ENV = dict(os.environ, LC_ALL='C', LANG='C', VERILATOR_ROOT=str(TOOL/'share/verilator'))
BUILD = PROJECT/'build/slave_monitor'
LOGS = ROOT/'logs/slave_monitor'
LOGS.mkdir(parents=True,exist_ok=True)
SOURCES = ['dv/interfaces/axi_write_if.sv','dv/slave/axi_slave_pkg.sv','dv/tests/slave_monitor/monitor_test_pkg.sv','dv/tests/slave_monitor/top.sv']
files = sorted(set([ROOT/f for f in SOURCES]+list((ROOT/'dv/slave').glob('*.svh'))+[ROOT/'dv/interfaces/axi_widths.svh',Path(__file__).resolve()]))
digest = hashlib.sha256(b''.join(str(f.relative_to(ROOT)).encode()+b'\0'+f.read_bytes() for f in files)).hexdigest()
if a.action == 'build':
    BUILD.mkdir(parents=True,exist_ok=True)
    command = [str(TOOL/'bin/verilator'),'--binary','--timing','--assert','--vpi','--language','1800-2017',
               '-Wno-fatal','--top-module','top','-j','4','--Mdir',str(BUILD),'+define+AXI_ID_W=4',
               *[f'+incdir+{d}' for d in [UVM/'src',PROJECT/'dv/interfaces',PROJECT/'dv/slave']],
               '-CFLAGS','-DUVM_NO_MALLOC -I'+str(UVM/'src/dpi'),str(UVM/'src/uvm_pkg.sv'),
               *[str(PROJECT/f) for f in SOURCES],str(UVM/'src/dpi/uvm_dpi.cc')]
    started = time.monotonic()
    with (LOGS/'build.log').open('w') as out:
        out.write(json.dumps(command)+'\n')
        out.flush()
        result = subprocess.run(command,stdout=out,stderr=subprocess.STDOUT,env=ENV,timeout=900)
    print(json.dumps(dict(build_exit=result.returncode,seconds=round(time.monotonic()-started,2),log=str(LOGS/'build.log'))),flush=True)
    if result.returncode:
        print((LOGS/'build.log').read_text()[-9000:])
    else:
        (BUILD/'source.sha256').write_text(digest)
    raise SystemExit(result.returncode)
if not (BUILD/'source.sha256').exists() or (BUILD/'source.sha256').read_text()!=digest:
    raise RuntimeError('Build missing or stale')
results=[]
for case in CASES if a.action=='regress' else [a.case]:
    command=[str(BUILD/'Vtop'),f'+CASE={case}']
    run=subprocess.run(command,capture_output=True,text=True,env=ENV,timeout=60)
    output=run.stdout+run.stderr
    log=LOGS/f'{case}.log'
    log.write_text(json.dumps(command)+'\n'+output)
    counts={k:int(v) for k,v in re.findall(r'UVM_(ERROR|FATAL)\s*:\s*(\d+)',output)}
    errors=re.findall(r'^UVM_ERROR\s+[^\n]*?\[([^\]]+)\]',output,re.MULTILINE)
    fatals=re.findall(r'^UVM_FATAL\s+[^\n]*?\[([^\]]+)\]',output,re.MULTILINE)
    expected=[EXPECTED[case]] if case in EXPECTED else []
    passed=run.returncode==0 and errors==expected and not fatals and counts=={'ERROR':len(expected),'FATAL':0} and '[CHECK_PASS]' in output and '$finish' in output and 'WATCHDOG' not in output and '%Error' not in output
    results.append(dict(case=case,passed=passed,counts=counts,error_ids=errors,expected_errors=expected,log=str(log)))
    print(json.dumps(results[-1]),flush=True)
    if not passed:
        print(output[-6000:],flush=True)
report=dict(date='2026-11-15',source_sha256=digest,results=results)
(LOGS/('results.json' if a.action=='regress' else f'{a.case}_result.json')).write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
