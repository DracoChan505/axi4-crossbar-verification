// Acceptance tests use pin observations and their own transaction/byte ledger.
// They never inspect the Slave's private queues or call its address algorithm.
class audit_record;
    longint unsigned sequence_number;
    longint unsigned min_delay;
    longint unsigned address;
    bit [ID_W-1:0] id;
    int unsigned beats;
    int unsigned size;
    int unsigned received = 0;
    bit done = 0;
    bit reject_write;
    longint unsigned done_cycle;
endclass

class clear_error_catcher extends uvm_report_catcher;
    int hits = 0;

    function new();
        super.new("clear_error_catcher");
    endfunction

    function action_e catch();
        if (get_severity() == UVM_ERROR && get_id() == "CLEAR_BUSY") begin
            hits++;
            set_severity(UVM_INFO);
        end
        return THROW;
    endfunction
endclass

class audit_master_sequence extends uvm_sequence#(axi_master_pkg::axi_write_item);
    `uvm_object_utils(audit_master_sequence)
    int responses = 0;
    bit seen[int];

    function new(string name = "audit_master_sequence");
        super.new(name);
    endfunction

    function void response_handler(uvm_sequence_item response);
        axi_master_pkg::axi_write_item result;
        int tag;
        if (!$cast(result, response)) begin
            `uvm_fatal("AUDIT_RESPONSE_TYPE", "Unexpected response type")
        end
        tag = result.get_transaction_id();
        if (tag < 0 || tag >= 12 || seen.exists(tag) || result.resp != 0 ||
            result.addr != ADDR_W'('h2000 + tag * 32)) begin
            `uvm_error("AUDIT_MASTER_RESPONSE", "Wrong or duplicate Master completion")
        end
        seen[tag] = 1;
        responses++;
    endfunction

    task body();
        use_response_handler(1);
        for (int i = 0; i < 12; i++) begin
            req = axi_master_pkg::axi_write_item::type_id::create("request");
            req.addr = ADDR_W'('h2000 + i * 32);
            req.id = ID_W'(i % 4);
            req.beats = 2;
            req.size = 2;
            req.aw_delay = 0;
            req.w_delay = i % 3;
            req.fill_pattern(i + 1);
            req.set_transaction_id(i);
            start_item(req);
            finish_item(req);
        end
        wait (responses == 12);
    endtask
endclass

class slave_acceptance_test extends slave_stage1_test;
    `uvm_component_utils(slave_acceptance_test)

    audit_record outstanding_q[$];
    audit_record data_q[$];
    byte unsigned reference_bytes[longint unsigned];
    int cancelled = 0;
    int peak = 0;
    int triple_events = 0;
    int blocked_aw_cycles = 0;
    int blocked_w_cycles = 0;
    int out_of_order = 0;
    longint unsigned response_addresses[$];
    int byte_cases = 0;
    bit auto_drop_aw = 0;
    bit integrated = 0;
    axi_master_pkg::axi_master_agent master;
    audit_master_sequence sequence_i;
    clear_error_catcher clear_catcher;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        axi_master_pkg::axi_master_cfg master_cfg;
        super.build_phase(phase);
        void'($value$plusargs("CAPACITY=%d", cfg.max_outstanding));
        if (test_case == "reset_bdelay") begin
            cfg.b_delay_cycles = 10;
        end
        if (test_case == "delay_one") begin
            cfg.b_delay_cycles = 1;
        end
        if (test_case == "same_id") begin
            cfg.reject_enable = 1;
            cfg.reject_first = 'h1010;
            cfg.reject_last = 'h101f;
        end
        if (test_case == "offset_window") begin
            cfg.base_addr = 'h10000;
            cfg.size_bytes = 65536;
        end
        if (test_case == "invalid_cfg") begin
            cfg.max_outstanding = 0;
        end
        void'($value$plusargs("SLAVE_SEED=%d", cfg.seed));
        if (test_case == "reorder" || test_case == "reorder_same_id" ||
            test_case == "b_lock" || test_case == "ordered_delay") begin
            cfg.response_order = test_case == "ordered_delay" ? B_IN_ORDER : B_OLDEST_READY;
            cfg.b_extra_delay_by_seq[0] = test_case == "b_lock" ? 12 : 40;
        end
        if (test_case == "reorder_same_id") begin
            cfg.reject_enable = 1;
            cfg.reject_first = 'h1010;
            cfg.reject_last = 'h101f;
        end
        if (test_case == "periodic_backpressure") begin
            cfg.aw_stall_period = 5;
            cfg.aw_stall_cycles = 3;
            cfg.w_stall_period = 7;
            cfg.w_stall_cycles = 5;
        end
        if (test_case == "random_backpressure" || test_case == "integration_stress" ||
            test_case == "reset_policies") begin
            cfg.aw_random_stall_max = 4;
            cfg.w_random_stall_max = 5;
            cfg.b_random_delay_max = 3;
            cfg.response_order = B_RANDOM_READY;
        end
        if (test_case == "integration_stress") begin
            cfg.b_extra_delay_by_seq[0] = 100;
        end
        if (test_case == "invalid_stall") begin
            cfg.aw_stall_period = 4;
            cfg.aw_stall_cycles = 4;
        end
        integrated = test_case == "integration" || test_case == "integration_stress";
        if (integrated) begin
            master_cfg = axi_master_pkg::axi_master_cfg::type_id::create("master_cfg");
            master_cfg.max_outstanding = 2;
            master_cfg.b_stall_period = 5;
            master_cfg.b_stall_cycles = 2;
            master_cfg.trace = 0;
            uvm_config_db#(axi_master_pkg::axi_master_cfg)::set(this, "master", "cfg", master_cfg);
            uvm_config_db#(virtual axi_write_if)::set(this, "master", "vif", vif);
            master = axi_master_pkg::axi_master_agent::type_id::create("master", this);
            sequence_i = audit_master_sequence::type_id::create("sequence_i");
        end
        clear_catcher = new;
        uvm_report_cb::add(null, clear_catcher);
    endfunction

    virtual task tick();
        bit aw_fire;
        bit w_fire;
        bit b_fire;
        audit_record transaction;
        audit_record retired;
        longint unsigned block_address;
        longint unsigned byte_address;
        int lane;
        int response_index;
        @(vif.mon);
        cycle++;
        aw_fire = vif.mon.AWVALID && vif.mon.AWREADY;
        w_fire = vif.mon.WVALID && vif.mon.WREADY;
        b_fire = vif.mon.BVALID && vif.mon.BREADY;
        if (!vif.mon.ARESETn) begin
            cancelled += outstanding_q.size();
            outstanding_q.delete();
            data_q.delete();
            return;
        end
        if (vif.mon.AWVALID && !vif.mon.AWREADY) begin
            blocked_aw_cycles++;
        end
        if (vif.mon.WVALID && !vif.mon.WREADY) begin
            blocked_w_cycles++;
        end
        if (aw_fire && outstanding_q.size() == cfg.max_outstanding) begin
            `uvm_error("AUDIT_EARLY_REUSE", "Full capacity reused on the B retirement edge")
        end
        if (aw_fire && w_fire && b_fire) begin
            triple_events++;
        end
        // Evaluate B against state from before this edge's new AW/W events.
        if (vif.mon.BVALID) begin
            if (outstanding_q.size() == 0) begin
                `uvm_fatal("AUDIT_ORPHAN_B", "Response without an observed AW")
            end
            response_index = 0;
            if (cfg.response_order != B_IN_ORDER) begin
                response_index = -1;
                foreach (outstanding_q[i]) begin
                    if (response_index < 0 && outstanding_q[i].id == vif.mon.BID) begin
                        response_index = i;
                    end
                end
                if (response_index < 0) begin
                    `uvm_fatal("AUDIT_BID", "No observed transaction has this BID")
                end
            end
            transaction = outstanding_q[response_index];
            if (!transaction.done || transaction.done_cycle >= cycle) begin
                `uvm_error("AUDIT_EARLY_B", "B precedes data completion")
            end
            if (vif.mon.BID != transaction.id ||
                vif.mon.BRESP != (transaction.reject_write ? 2'b10 : 2'b00)) begin
                `uvm_error("AUDIT_RESPONSE", "Response differs from the permitted ID head")
            end
            if (cycle < transaction.done_cycle + transaction.min_delay + 1) begin
                `uvm_error("AUDIT_DELAY", "Response violated configured delay")
            end
            if (b_fire) begin
                if (response_index != 0) begin
                    out_of_order++;
                end
                response_addresses.push_back(transaction.address);
                outstanding_q.delete(response_index);
                b_count++;
            end
        end
        if (w_fire) begin
            if (data_q.size() == 0) begin
                `uvm_fatal("AUDIT_ORPHAN_W", "Accepted W before AW")
            end
            transaction = data_q[0];
            // Enumerate absolute byte addresses of this beat independently.
            block_address = ((transaction.address >> transaction.size) +
                             64'(transaction.received)) << transaction.size;
            for (int offset = 0; offset < (1 << transaction.size); offset++) begin
                byte_address = block_address + 64'(offset);
                lane = int'(byte_address % STRB_W);
                if (byte_address >= transaction.address && vif.mon.WSTRB[lane] &&
                    !transaction.reject_write) begin
                    reference_bytes[byte_address] = vif.mon.WDATA[8*lane +: 8];
                end
            end
            transaction.received++;
            if (vif.mon.WLAST != (transaction.received == transaction.beats)) begin
                `uvm_error("AUDIT_STIMULUS", "Test produced a bad WLAST")
            end
            if (vif.mon.WLAST) begin
                transaction.done = 1;
                transaction.done_cycle = cycle;
                retired = data_q.pop_front();
            end
            w_count++;
        end
        if (aw_fire) begin
            transaction = new;
            transaction.sequence_number = 64'(aw_count);
            transaction.min_delay = 64'(cfg.b_delay_cycles);
            if (cfg.b_extra_delay_by_seq.exists(transaction.sequence_number)) begin
                transaction.min_delay += 64'(cfg.b_extra_delay_by_seq[transaction.sequence_number]);
            end
            transaction.address = 64'(vif.mon.AWADDR);
            transaction.id = vif.mon.AWID;
            transaction.beats = int'(vif.mon.AWLEN) + 1;
            transaction.size = int'(vif.mon.AWSIZE);
            transaction.reject_write = cfg.reject_enable &&
                transaction.address >= cfg.reject_first && transaction.address <= cfg.reject_last;
            outstanding_q.push_back(transaction);
            data_q.push_back(transaction);
            aw_count++;
            if (auto_drop_aw) begin
                vif.AWVALID <= 0;
                auto_drop_aw = 0;
            end
        end
        if (outstanding_q.size() > cfg.max_outstanding) begin
            `uvm_error("AUDIT_CAPACITY", "Observed AW exceeded capacity")
        end
        if (outstanding_q.size() > peak) begin
            peak = outstanding_q.size();
        end
    endtask

    task drive_aw(longint unsigned address, int beats, int size, int id);
        vif.AWADDR <= ADDR_W'(address);
        vif.AWID <= ID_W'(id);
        vif.AWLEN <= 8'(beats - 1);
        vif.AWSIZE <= 3'(size);
        vif.AWBURST <= 1;
        vif.AWLOCK <= 0;
        vif.AWCACHE <= 2;
        vif.AWPROT <= 2;
        vif.AWQOS <= 0;
        vif.AWVALID <= 1;
    endtask

    task accept_aw(longint unsigned address, int beats = 1, int size = 2, int id = 0);
        drive_aw(address, beats, size, id);
        do begin
            tick();
        end while (!(vif.mon.AWVALID && vif.mon.AWREADY));
        vif.AWVALID <= 0;
    endtask

    task accept_w(bit [DATA_W-1:0] data, bit [STRB_W-1:0] strobe = STRB_W'(15), bit last = 1);
        vif.WDATA <= data;
        vif.WSTRB <= strobe;
        vif.WLAST <= last;
        vif.WVALID <= 1;
        do begin
            tick();
        end while (!(vif.mon.WVALID && vif.mon.WREADY));
        vif.WVALID <= 0;
    endtask

    task drain();
        vif.BREADY <= 1;
        while (outstanding_q.size() != 0) begin
            tick();
        end
        vif.BREADY <= 0;
        repeat (2) tick();
        #1;
        if (!driver.idle()) begin
            `uvm_error("AUDIT_DRAIN", "Pin ledger drained but Driver did not")
        end
    endtask

    function void check_memory(longint unsigned first_address, longint unsigned last_address);
        byte unsigned value;
        for (longint unsigned address = first_address; address <= last_address; address++) begin
            value = reference_bytes.exists(address) ? reference_bytes[address] : 0;
            expect_byte(address, value);
        end
    endfunction

    task capacity_test(bit same_id);
        int capacity;
        capacity = int'(cfg.max_outstanding);
        for (int i = 0; i < capacity; i++) begin
            accept_aw('h1000 + 64'(16*i), 1, 2, same_id ? 1 : i);
        end
        drive_aw('h1000 + 64'(16*capacity), 1, 2, same_id ? 1 : capacity);
        auto_drop_aw = 1;
        accept_w(DATA_W'('h12345678));
        repeat (5) begin
            tick();
            if (vif.mon.AWREADY || aw_count != capacity || b_count != 0) begin
                `uvm_error("AUDIT_FULL", "Full port reused a slot before B handshake")
            end
        end
        // B0 can retire with W1. On the following edge AW(extra), W2 and B1
        // can all handshake; this creates a required actual overlap witness.
        vif.BREADY <= 1;
        for (int i = 1; i < capacity; i++) begin
            accept_w(DATA_W'('h12345678 + i));
        end
        while (aw_count < capacity + 1) begin
            tick();
        end
        accept_w(DATA_W'('h12345678 + capacity));
        drain();
        if (peak != capacity || aw_count != capacity + 1 || b_count != capacity + 1 ||
            w_count != capacity + 1 || blocked_aw_cycles < 5) begin
            `uvm_error("AUDIT_CAPACITY_WITNESS", "Required capacity scenario did not occur")
        end
        if (capacity >= 3 && triple_events == 0) begin
            `uvm_error("AUDIT_OVERLAP_WITNESS", "AW/W/B never handshook together")
        end
        check_memory('h1000, 'h108f);
    endtask

    task byte_matrix();
        longint unsigned address;
        bit [STRB_W-1:0] legal;
        bit [DATA_W-1:0] data;
        int first_lane;
        int end_lane;
        for (int size = 0; size <= $clog2(STRB_W); size++) begin
            for (int offset = 0; offset < STRB_W; offset++) begin
                address = 'h3000 + 64'(offset);
                first_lane = offset;
                end_lane = ((offset >> size) + 1) << size;
                legal = '0;
                for (int lane = first_lane; lane < end_lane; lane++) begin
                    legal[lane] = 1;
                end
                for (int subset = 0; subset < (1 << STRB_W); subset++) begin
                    if ((STRB_W'(subset) & ~legal) != 0) begin
                        continue;
                    end
                    data = '0;
                    for (int lane = 0; lane < STRB_W; lane++) begin
                        data[8*lane +: 8] = 8'(byte_cases * 17 + lane + 1);
                    end
                    accept_aw(address, 1, size, byte_cases % (1 << ID_W));
                    accept_w(data, STRB_W'(subset));
                    drain();
                    check_memory('h2fff, 'h3010);
                    byte_cases++;
                end
            end
        end
        if (byte_cases != (DATA_W == 32 ? 50 : 610)) begin
            `uvm_error("AUDIT_MATRIX_WITNESS", "Byte matrix unexpectedly small")
        end
    endtask

    task reordering_test();
        int count;
        count = test_case == "reorder_same_id" ? 4 : 2;
        for (int i = 0; i < count; i++) begin
            accept_aw('h1000 + 64'(16*i), 1, 2,
                      test_case == "reorder_same_id" ? i / 2 : i);
        end
        for (int i = 0; i < count; i++) begin
            accept_w(DATA_W'('h12345678 + i));
        end
        if (test_case == "b_lock") begin
            do begin
                tick();
            end while (!vif.mon.BVALID);
            repeat (20) begin
                if (!vif.mon.BVALID || vif.mon.BID != ID_W'(1)) begin
                    `uvm_error("AUDIT_LOCK", "Stalled B changed when another ID became ready")
                end
                tick();
            end
        end
        drain();
        if (test_case == "ordered_delay") begin
            if (out_of_order != 0 || response_addresses[0] != 'h1000) begin
                `uvm_error("AUDIT_ORDERED", "Default ordered mode bypassed the oldest AW")
            end
        end
        else begin
            if (out_of_order == 0 || response_addresses[0] == 'h1000) begin
                `uvm_error("AUDIT_REORDER_WITNESS", "No actual cross-ID reordering occurred")
            end
        end
        if (test_case == "reorder_same_id") begin
            if (response_addresses[0] != 'h1020 || response_addresses[1] != 'h1030 ||
                response_addresses[2] != 'h1000 || response_addresses[3] != 'h1010) begin
                `uvm_error("AUDIT_ID_ORDER", "Unexpected response sequence in two ID streams")
            end
        end
        if (aw_count != count || b_count != count || w_count != count) begin
            `uvm_error("AUDIT_REORDER_COUNTS", "Lost or duplicated transaction")
        end
        check_memory('h1000, 'h1040);
    endtask

    task backpressure_test();
        for (int i = 0; i < 12; i++) begin
            accept_aw('h5000 + 64'(16*i), 1, 2, i % 4);
            accept_w(DATA_W'('h11223344 + i));
            drain();
        end
        if (blocked_aw_cycles == 0 || blocked_w_cycles == 0 ||
            aw_count != 12 || w_count != 12 || b_count != 12) begin
            `uvm_error("AUDIT_BACKPRESSURE_WITNESS", "Both channel stalls and completion must occur")
        end
        check_memory('h5000, 'h50c0);
    endtask

    task run_phase(uvm_phase phase);
        longint unsigned address;
        phase.raise_objection(this);
        if (!integrated) begin
            vif.AWVALID <= 0;
            vif.WVALID <= 0;
            vif.BREADY <= 0;
        end
        do begin
            tick();
        end while (!vif.mon.ARESETn);
        tick();
        case (test_case)
            "reorder", "reorder_same_id", "b_lock", "ordered_delay": begin
                reordering_test();
            end
            "periodic_backpressure", "random_backpressure": begin
                backpressure_test();
            end
            "reset_policies": begin
                accept_aw('h1000, 2);
                accept_w(DATA_W'('h11223344), STRB_W'(15), 0);
                reset_during_transfer();
                accept_aw('h1010);
                accept_w(DATA_W'('h55667788));
                drain();
                check_memory('h1000, 'h1020);
            end
            "capacity", "same_id": begin
                capacity_test(test_case == "same_id");
            end
            "byte_matrix": begin
                byte_matrix();
            end
            "reset_idle", "reset_aw", "reset_bdelay", "reset_bvalid", "clear_reset": begin
                driver.memory.write_byte('h4000, 'ha5);
                reference_bytes['h4000] = 'ha5;
                if (test_case != "reset_idle") begin
                    accept_aw('h1000);
                end
                if (test_case == "reset_bdelay" || test_case == "reset_bvalid") begin
                    accept_w(DATA_W'('h12345678));
                    if (test_case == "reset_bvalid") begin
                        do begin
                            tick();
                        end while (!vif.mon.BVALID);
                    end
                end
                if (test_case == "clear_reset") begin
                    uvm_event reset_request;
                    reset_request = uvm_event_pool::get_global("slave_reset_request");
                    reset_request.trigger();
                    do begin
                        tick();
                    end while (vif.mon.ARESETn);
                    #1;
                    driver.memory.clear_memory();
                    reference_bytes.delete();
                    do begin
                        tick();
                    end while (!vif.mon.ARESETn);
                end
                else begin
                    reset_during_transfer();
                end
                accept_aw('h1010);
                accept_w(DATA_W'('h89abcdef));
                drain();
                check_memory('h1000, 'h1020);
                check_memory('h4000, 'h4000);
            end
            "clear_busy": begin
                driver.memory.write_byte('h4000, 'ha5);
                reference_bytes['h4000] = 'ha5;
                accept_aw('h1000);
                #1;
                driver.memory.clear_memory();
                if (clear_catcher.hits != 1) begin
                    `uvm_error("AUDIT_CLEAR_MISSING", "Active clear did not report CLEAR_BUSY")
                end
                expect_byte('h4000, 'ha5);
                accept_w(DATA_W'('h12345678));
                drain();
                check_memory('h1000, 'h1003);
            end
            "offset_window", "delay_one": begin
                address = cfg.base_addr + 'h1000;
                accept_aw(address);
                accept_w(DATA_W'('h12345678));
                drain();
                check_memory(address - 1, address + 8);
            end
            "integration", "integration_stress": begin
                fork
                    sequence_i.start(master.sequencer);
                    begin
                        do begin
                            tick();
                        end while (b_count < 12);
                    end
                join
                repeat (3) tick();
                #1;
                if (sequence_i.responses != 12 || aw_count != 12 || w_count != 24 ||
                    b_count != 12 || !master.driver.idle() || !driver.idle()) begin
                    `uvm_error("AUDIT_INTEGRATION", "Master/Slave did not complete all tasks")
                end
                if (test_case == "integration_stress" &&
                    (out_of_order == 0 || blocked_aw_cycles == 0 || blocked_w_cycles == 0)) begin
                    `uvm_error("AUDIT_STRESS_WITNESS", "Combined stalls and reordering did not occur")
                end
                check_memory('h2000, 'h2180);
            end
            default: begin
                `uvm_fatal("AUDIT_CASE", "Unknown acceptance test")
            end
        endcase
        if (outstanding_q.size() != 0 || data_q.size() != 0 ||
            aw_count != b_count + cancelled) begin
            `uvm_error("AUDIT_LEDGER", "Unbalanced pin-level transaction ledger")
        end
        if (test_case != "clear_busy" && clear_catcher.hits != 0) begin
            `uvm_error("AUDIT_UNEXPECTED_CLEAR", "Unexpected CLEAR_BUSY diagnostic")
        end
        `uvm_info("AUDIT_WITNESS", $sformatf("peak=%0d triple=%0d blocked_aw=%0d byte_cases=%0d cancelled=%0d blocked_w=%0d reordered=%0d",
            peak, triple_events, blocked_aw_cycles, byte_cases, cancelled, blocked_w_cycles, out_of_order), UVM_NONE)
        `uvm_info("CHECK_PASS", $sformatf("case=%s AW=%0d W=%0d B=%0d stage=acceptance",
            test_case, aw_count, w_count, b_count), UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass
