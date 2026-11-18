#!/usr/bin/env python3
"""Check two seeded Slave faults with frozen tests, in isolated temporary copies."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MUTATIONS = {
    "wrong_bid": (
        "vif.sink.BID <= returning.id;",
        "vif.sink.BID <= returning.id ^ ID_W'(1);",
        "TEST_BID",
    ),
    "wrong_byte": (
        "memory.write_byte(word_base + 64'(lane), vif.mon.WDATA[8*lane +: 8]);",
        "memory.write_byte(word_base + 64'(lane), vif.mon.WDATA[8*lane +: 8] ^ 8'h01);",
        "TEST_MEMORY",
    ),
}


def source_hash(root):
    paths = sorted((root / "dv").rglob("*.sv")) + sorted((root / "dv").rglob("*.svh"))
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def run_fault(name):
    temporary = Path(tempfile.mkdtemp(prefix="axi-slave-fault-" + name + "-"))
    shutil.copytree(ROOT / "dv", temporary / "dv")
    (temporary / "scripts").mkdir()
    shutil.copy2(ROOT / "scripts/run_slave.py", temporary / "scripts/run_slave.py")
    original = source_hash(ROOT)
    before, after, expected = MUTATIONS[name]
    driver = temporary / "dv/slave/axi_slave_driver.svh"
    text = driver.read_text()
    if text.count(before) != 1:
        raise RuntimeError("Mutation site missing or ambiguous: " + name)
    driver.write_text(text.replace(before, after))
    mutated = source_hash(temporary)
    changed = [path for path in original if original[path] != mutated[path]]
    if changed != ["dv/slave/axi_slave_driver.svh"]:
        raise RuntimeError("Unexpected file changed in mutation copy")
    env = dict(os.environ, AXI_LOCAL_UVM=str(ROOT.parent / "local-uvm"))
    command = [sys.executable, str(temporary / "scripts/run_slave.py")]
    with (temporary / "orchestration.log").open("w") as stream:
        build = subprocess.run(command + ["build"], env=env, stdout=stream, stderr=subprocess.STDOUT)
        test = None
        if build.returncode == 0:
            test = subprocess.run(command + ["test", "--case", "smoke"], env=env,
                                  stdout=stream, stderr=subprocess.STDOUT)
    result_path = temporary / "logs/slave_d32_i4/smoke_s7_c4_result.json"
    result = json.loads(result_path.read_text())["results"][0] if result_path.exists() else None
    killed = (build.returncode == 0 and test is not None and test.returncode == 1
              and result is not None and result["exit"] == 0
              and not result["passed"] and result["counts"].get("FATAL") == 0
              and set(result["error_ids"]) == {expected})
    artifact = ROOT / "checks/slave-acceptance-mutations" / name
    artifact.mkdir(parents=True, exist_ok=True)
    shutil.copy2(temporary / "orchestration.log", artifact / "orchestration.log")
    if result_path.exists():
        shutil.copy2(result_path, artifact / "result.json")
        shutil.copy2(Path(result["log"]), artifact / "simulation.log")
    (artifact / "mutation.diff").write_text("- " + before + "\n+ " + after + "\n")
    return dict(name=name, killed=killed, expected_error=expected, temporary=str(temporary),
                changed_files=changed, frozen_source_hashes=original, result=result)


def main():
    # Parallel compiler processes only; there are no delegated agents.
    with ThreadPoolExecutor(max_workers=2) as pool:
        rows = list(pool.map(run_fault, MUTATIONS))
    summary = dict(scope="two_seeded_faults_only", mutations=rows)
    output = ROOT / "checks/slave-acceptance-mutations/results.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2) + "\n")
    for row in rows:
        print(json.dumps({key: row[key] for key in ("name", "killed", "expected_error", "temporary")}), flush=True)
    return 0 if all(row["killed"] for row in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
