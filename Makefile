.PHONY: master-build master-test master-regress
master-build:
	python3 scripts/run_master.py build
master-test:
	python3 scripts/run_master.py test --case smoke
master-regress:
	python3 scripts/run_master.py regress

.PHONY: slave-build slave-test slave-regress
slave-build:
	python3 scripts/run_slave.py build
slave-test:
	python3 scripts/run_slave.py test --case smoke
slave-regress:
	python3 scripts/run_slave.py regress

.PHONY: tracker-regress routing-regress
tracker-regress:
	python3 scripts/run_tracker.py
routing-regress:
	python3 scripts/run_routing.py

.PHONY: frontend-regress
frontend-regress:
	python3 scripts/run_frontend.py

.PHONY: wpath-regress
wpath-regress:
	python3 scripts/run_wpath.py

.PHONY: bpath-regress
bpath-regress:
	python3 scripts/run_bpath.py

.PHONY: write-regress decerr-regress
write-regress:
	python3 scripts/run_crossbar_write.py
decerr-regress:
	python3 scripts/run_decerr.py

.PHONY: system-build system-regress system-build64 system-regress64 system-memory-fault
system-build:
	python3 scripts/run_crossbar_uvm.py build
system-regress:
	python3 scripts/run_crossbar_uvm.py regress
system-build64:
	python3 scripts/run_crossbar_uvm.py build --data-width 64
system-regress64:
	python3 scripts/run_crossbar_uvm.py regress --data-width 64
system-memory-fault:
	python3 scripts/run_crossbar_uvm.py test --inject-memory-fault

.PHONY: monitor-build monitor-regress
monitor-build:
	python3 scripts/run_slave_monitor.py build
monitor-regress:
	python3 scripts/run_slave_monitor.py regress

.PHONY: read-regress
read-regress:
	python3 scripts/run_crossbar_read.py

.PHONY: read-uvm-build read-uvm-regress
read-uvm-build:
	python3 scripts/run_crossbar_uvm5.py build
read-uvm-regress:
	python3 scripts/run_crossbar_uvm5.py regress

.PHONY: read-uvm-build64 read-uvm-regress64
read-uvm-build64:
	python3 scripts/run_crossbar_uvm5.py build --data-width 64
read-uvm-regress64:
	python3 scripts/run_crossbar_uvm5.py regress --data-width 64

.PHONY: combined-build combined-regress combined-build64 combined-regress64
combined-build:
	python3 scripts/run_crossbar_uvm6.py build
combined-regress:
	python3 scripts/run_crossbar_uvm6.py regress
combined-build64:
	python3 scripts/run_crossbar_uvm6.py build --data-width 64
combined-regress64:
	python3 scripts/run_crossbar_uvm6.py regress --data-width 64

.PHONY: reset-build reset-regress reset-build64 reset-regress64
reset-build:
	python3 scripts/run_crossbar_uvm7.py build
reset-regress:
	python3 scripts/run_crossbar_uvm7.py regress
reset-build64:
	python3 scripts/run_crossbar_uvm7.py build --data-width 64
reset-regress64:
	python3 scripts/run_crossbar_uvm7.py regress --data-width 64

.PHONY: xcelium-build xcelium-regress xcelium-test
xcelium-build:
	python3 scripts/run_crossbar_xcelium.py build
xcelium-test:
	python3 scripts/run_crossbar_xcelium.py test --scenario 0 --seed 7
xcelium-regress:
	python3 scripts/run_crossbar_xcelium.py regress
