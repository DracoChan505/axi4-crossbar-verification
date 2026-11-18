`timescale 1ns/1ps
package crossbar_uvm5_pkg;
    import uvm_pkg::*;
    import axi_master_pkg::*;
    import axi_master_read_pkg::*;
    import axi_slave_pkg::*;
    import axi_slave_read_pkg::*;
    `include "uvm_macros.svh"

    typedef virtual axi_read_if#(ADDR_W, DATA_W, ID_W) master_rvif_t;
    typedef virtual axi_read_if#(ADDR_W, DATA_W, axi_slave_read_pkg::ID_W) slave_rvif_t;

    localparam int PORTS    = 4;
    localparam int R_REQS   = 24;
    localparam int SOURCE_WIDTH = PORTS > 1 ? $clog2(PORTS) : 1;

    // ---- Read scoreboard: observes both sides via pin-level monitors ----
    class fabric_r_record;
        int source;
        int target;
        bit [ID_W-1:0] id;
        longint unsigned address;
        int beats;
        int size;
        bit [16:0] attr;
        bit [1:0] response;
        bit [DATA_W-1:0] data[$];
        bit [1:0] rresp[$];
        int received   = 0;
        int forwarded  = 0;
        bit downstream_done = 0;
        longint unsigned ar_cycle;
        longint unsigned rlast_cycle;
    endclass

    class fabric_r_scoreboard extends uvm_component;
        `uvm_component_utils(fabric_r_scoreboard)
        master_rvif_t master_bus[PORTS];
        slave_rvif_t  slave_bus[PORTS];
        fabric_r_record incoming[PORTS][$];   // AR accepted upstream
        fabric_r_record awaiting_down[PORTS][$]; // AR routed to slave, awaiting R
        fabric_r_record outgoing_r[PORTS][$];    // R beats seen at slave side
        fabric_r_record upstream_r[PORTS][$];     // R beats seen at master side
        byte unsigned expected_mem[PORTS][longint unsigned];
        int ar_count = 0;
        int r_complete = 0;
        int down_ar_count = 0;
        int down_r_beats = 0;
        int up_r_beats = 0;
        int error_responses = 0;
        int decerr_count = 0;
        int ar_stalls = 0;
        int r_stalls = 0;
        longint unsigned cycle = 0;
        int peak[PORTS];

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            for (int i = 0; i < PORTS; i++) begin
                if (!uvm_config_db#(master_rvif_t)::get(this, "", $sformatf("master_rvif_%0d", i), master_bus[i]) ||
                    !uvm_config_db#(slave_rvif_t)::get(this, "", $sformatf("slave_rvif_%0d", i), slave_bus[i])) begin
                    `uvm_fatal("RSYS_VIF", "Missing read observation interface")
                end
            end
        endfunction

        function bit empty();
            for (int i = 0; i < PORTS; i++) begin
                if (incoming[i].size() != 0 || awaiting_down[i].size() != 0 ||
                    outgoing_r[i].size() != 0 || upstream_r[i].size() != 0)
                    return 0;
            end
            return 1;
        endfunction

        task run_phase(uvm_phase phase);
            fabric_r_record item;
            int src, dest, beat, match_idx;
            forever begin
                @(master_bus[0].mon);
                cycle++;
                if (!master_bus[0].mon.ARESETn) begin
                    for (int i = 0; i < PORTS; i++) begin
                        incoming[i].delete();
                        awaiting_down[i].delete();
                        outgoing_r[i].delete();
                        upstream_r[i].delete();
                    end
                    continue;
                end
                // Master side: observe AR and R
                for (int i = 0; i < PORTS; i++) begin
                    // AR accepted upstream → push to both incoming and upstream_r immediately
                    if (master_bus[i].mon.ARVALID && master_bus[i].mon.ARREADY) begin
                        item = new;
                        item.source   = i;
                        item.address  = 64'(master_bus[i].mon.ARADDR);
                        dest          = item.address < 'h40000 ? int'(item.address >> 16) : PORTS;
                        item.target   = dest;
                        item.id       = master_bus[i].mon.ARID;
                        item.beats    = int'(master_bus[i].mon.ARLEN) + 1;
                        item.size     = int'(master_bus[i].mon.ARSIZE);
                        item.attr     = {master_bus[i].mon.ARSIZE, master_bus[i].mon.ARBURST,
                                         master_bus[i].mon.ARLOCK, master_bus[i].mon.ARCACHE,
                                         master_bus[i].mon.ARPROT, master_bus[i].mon.ARQOS};
                        item.response = dest == PORTS ? 2'b11 :
                                        ((item.address & 'hffff) >= 'h8000 &&
                                         (item.address & 'hffff) <= 'h8fff) ? 2'b10 : 2'b00;
                        item.ar_cycle = cycle;
                        incoming[i].push_back(item);
                        // upstream_r filled immediately so R beats can arrive any time
                        upstream_r[i].push_back(item);
                        if (dest < PORTS) awaiting_down[i].push_back(item);
                        ar_count++;
                        if (incoming[i].size() > peak[i]) peak[i] = incoming[i].size();
                    end
                    // R beats at master side: track count per pending entry by ID.
                    // Same-ID ordering guaranteed by DUT tracker; first-matching-ID is correct.
                    // We verify: no orphan R, RLAST timing, response class (DECERR/SLVERR/OKAY).
                    if (master_bus[i].mon.RVALID && master_bus[i].mon.RREADY) begin
                        begin
                            int idx = -1;
                            for (int k = 0; k < upstream_r[i].size(); k++) begin
                                if (idx < 0 && upstream_r[i][k].id == master_bus[i].mon.RID)
                                    idx = k;
                            end
                            if (idx < 0)
                                `uvm_fatal("RSYS_ORPHAN_R", "Upstream R has no accepted AR")
                            item = upstream_r[i][idx];
                            item.received++;
                            up_r_beats++;
                            // Check RRESP class: OKAY/SLVERR/DECERR must match expected
                            begin
                                bit [1:0] got_resp = master_bus[i].mon.RRESP;
                                bit resp_ok;
                                case (item.response)
                                    2'b11: resp_ok = (got_resp == 2'b11);              // DECERR
                                    2'b10: resp_ok = (got_resp == 2'b10);              // SLVERR
                                    default: resp_ok = (got_resp == 2'b00);            // OKAY
                                endcase
                                if (!resp_ok)
                                    `uvm_error("RSYS_RESP", $sformatf(
                                        "RRESP mismatch: got %b expected %b addr=%h beat=%0d",
                                        got_resp, item.response, item.address, item.received))
                            end
                            if (master_bus[i].mon.RLAST) begin
                                // On RLAST: check that we received exactly the expected beats
                                if (item.received != item.beats)
                                    `uvm_error("RSYS_RLAST", $sformatf(
                                        "RLAST at wrong beat: received=%0d beats=%0d addr=%h",
                                        item.received, item.beats, item.address))
                                item.rlast_cycle = cycle;
                                r_complete++;
                                if (item.response == 2'b11) decerr_count++;
                                if (item.response == 2'b10) error_responses++;
                                upstream_r[i].delete(idx);
                                begin
                                    int idx2 = -1;
                                    for (int k = 0; k < incoming[i].size(); k++) begin
                                        if (idx2 < 0 && incoming[i][k] == item) idx2 = k;
                                    end
                                    if (idx2 >= 0) incoming[i].delete(idx2);
                                end
                            end else begin
                                // Check RLAST=0 means we haven't reached expected beats yet
                                if (item.received >= item.beats)
                                    `uvm_error("RSYS_MISSING_LAST", $sformatf(
                                        "Missing RLAST: received=%0d beats=%0d addr=%h",
                                        item.received, item.beats, item.address))
                            end
                        end
                    end
                    if (master_bus[i].mon.RVALID && !master_bus[i].mon.RREADY)
                        r_stalls++;
                end
                // Slave side: observe AR and R
                for (int o = 0; o < PORTS; o++) begin
                    // AR routed to slave
                    if (slave_bus[o].mon.ARVALID && slave_bus[o].mon.ARREADY) begin
                        src = int'(slave_bus[o].mon.ARID[axi_slave_read_pkg::ID_W-1:ID_W]);
                        if (src >= PORTS || awaiting_down[src].size() == 0)
                            `uvm_fatal("RSYS_AR_SOURCE", "Unexpected output AR source")
                        item = awaiting_down[src].pop_front();
                        if (item.target != o || item.address != 64'(slave_bus[o].mon.ARADDR) ||
                            item.id != ID_W'(slave_bus[o].mon.ARID) ||
                            item.beats != int'(slave_bus[o].mon.ARLEN) + 1 ||
                            item.attr != {slave_bus[o].mon.ARSIZE, slave_bus[o].mon.ARBURST,
                                          slave_bus[o].mon.ARLOCK, slave_bus[o].mon.ARCACHE,
                                          slave_bus[o].mon.ARPROT, slave_bus[o].mon.ARQOS}) begin
                            `uvm_error("RSYS_AR_ROUTE", "Output AR differs from input AR")
                        end
                        outgoing_r[o].push_back(item);
                        down_ar_count++;
                    end
                    // R beats at slave side: match by RID (slave may serve different IDs out-of-order)
                    if (slave_bus[o].mon.RVALID && slave_bus[o].mon.RREADY) begin
                        begin
                            int idx = -1;
                            bit [axi_slave_read_pkg::ID_W-1:0] rid = slave_bus[o].mon.RID;
                            for (int k = 0; k < outgoing_r[o].size(); k++) begin
                                // Match by expanded ID: {source, original_id}
                                if (idx < 0 &&
                                    {SOURCE_WIDTH'(outgoing_r[o][k].source), outgoing_r[o][k].id} == rid)
                                    idx = k;
                            end
                            if (idx < 0)
                                `uvm_fatal("RSYS_DOWN_R", "Output R without observed AR")
                            item = outgoing_r[o][idx];
                            beat = item.forwarded;
                            if (slave_bus[o].mon.RLAST != (beat + 1 == item.beats))
                                `uvm_error("RSYS_DOWN_RLAST", $sformatf(
                                    "Downstream RLAST timing mismatch: beat=%0d beats=%0d addr=%h",
                                    beat+1, item.beats, item.address))
                            // For non-SLVERR/DECERR: check data matches memory model
                            if (item.response == 2'b00) begin
                                longint unsigned step = 64'(1) << item.size;
                                longint unsigned block = ((64'(item.address) >> item.size) + 64'(beat)) * step;
                                longint unsigned base  = (block / STRB_W) * STRB_W;
                                bit [DATA_W-1:0] exp_data = '0;
                                for (int lane = 0; lane < STRB_W; lane++)
                                    exp_data[8*lane +: 8] = expected_mem[o].exists(base + 64'(lane)) ?
                                                             expected_mem[o][base + 64'(lane)] : 8'h00;
                                if (slave_bus[o].mon.RDATA !== exp_data)
                                    `uvm_error("RSYS_RDATA", $sformatf(
                                        "Downstream R data mismatch: addr=%h beat=%0d got=%h exp=%h",
                                        item.address, beat, slave_bus[o].mon.RDATA, exp_data))
                            end
                            item.forwarded++;
                            down_r_beats++;
                            if (slave_bus[o].mon.RLAST) begin
                                item.downstream_done = 1;
                                outgoing_r[o].delete(idx);
                            end
                        end
                    end
                end
            end
        endtask
    endclass

    // ---- Read sequence ----
    class fabric_r_sequence extends uvm_sequence#(axi_read_item);
        `uvm_object_utils(fabric_r_sequence)
        int source;
        int responses = 0;
        bit seen[int];
        bit [1:0] expected_resp[R_REQS];
        bit [ADDR_W-1:0] expected_addr[R_REQS];
        function new(string name = "fabric_r_sequence");
            super.new(name);
        endfunction
        function void response_handler(uvm_sequence_item response);
            axi_read_item result;
            int tag;
            if (!$cast(result, response))
                `uvm_fatal("RSYS_RESPONSE_TYPE", "Unexpected read completion type")
            tag = result.get_transaction_id();
            if (tag < 0 || tag >= R_REQS)
                `uvm_fatal("RSYS_RESPONSE_TAG", "Completion tag outside submitted range")
            if (seen.exists(tag) || result.addr != expected_addr[tag] ||
                result.resp != expected_resp[tag]) begin
                `uvm_error("RSYS_SEQUENCE_RESPONSE", "Wrong or repeated read completion")
            end
            seen[tag] = 1;
            responses++;
        endfunction
        task body();
            int target;
            longint unsigned address;
            use_response_handler(1);
            for (int n = 0; n < R_REQS; n++) begin
                req = axi_read_item::type_id::create("rreq");
                target = n % 5;
                if (n < 2) target = 0;
                if (n == 2 || n == 5) target = 1;
                if (n == 7) target = 3;
                address = (64'(target) << 16) + 64'(source) * 64'd8192 + 64'(n % 4) * 64'd1024;
                req.id = n < 3 ? '0 : ID_W'(n % 4);
                req.beats = 1 + n % 4;
                req.size = 32'(n % ($clog2(STRB_W) + 1));
                if (n == 5) begin
                    address = (64'(target) << 16) + 'h8000 + 64'(source * 256);
                end
                if (n == 6) begin
                    address++;
                    req.size = $clog2(STRB_W);
                end
                if (n == 7) begin
                    address = (64'(target) << 16) + 64'(source * 8192);
                    req.beats = 256;
                    req.size = $clog2(STRB_W);
                end
                if (n == 8) begin
                    address = (64'(target) << 16) + 'hffff;
                    req.beats = 1;
                    req.size = 0;
                end
                req.addr = ADDR_W'(address);
                req.ar_delay = n == 0 ? 8 : 32'(n % 3);
                req.set_transaction_id(n);
                expected_addr[n] = req.addr;
                expected_resp[n] = target == 4 ? 2'b11 : n == 5 ? 2'b10 : 2'b00;
                start_item(req);
                finish_item(req);
            end
            wait (responses == R_REQS);
        endtask
    endclass

    // ---- 5-channel UVM test ----
    class crossbar_uvm5_test extends uvm_test;
        `uvm_component_utils(crossbar_uvm5_test)
        // Write components (reuse existing)
        axi_master_agent write_masters[PORTS];
        axi_slave_pkg::axi_slave_agent write_slaves[PORTS];
        // Read components
        axi_master_read_agent read_masters[PORTS];
        axi_slave_read_agent read_slaves[PORTS];
        fabric_r_sequence read_sequences[PORTS];
        fabric_r_scoreboard r_scoreboard;
        int seed = 7;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            axi_master_read_cfg mrcfg;
            axi_slave_pkg::axi_slave_cfg srcfg;
            master_rvif_t mrbus;
            slave_rvif_t  srbus;
            void'($value$plusargs("SEED=%d", seed));
            for (int i = 0; i < PORTS; i++) begin
                // Read master
                if (!uvm_config_db#(master_rvif_t)::get(this, "", $sformatf("master_rvif_%0d", i), mrbus))
                    `uvm_fatal("RSYS_MVIF", "Missing read master interface")
                mrcfg = axi_master_read_cfg::type_id::create($sformatf("mrcfg_%0d", i));
                mrcfg.max_outstanding = 2;
                mrcfg.pending_depth = 4;
                mrcfg.r_stall_period = 11;
                mrcfg.r_stall_cycles = 8;
                uvm_config_db#(axi_master_read_cfg)::set(this, $sformatf("rmaster_%0d", i), "cfg", mrcfg);
                uvm_config_db#(master_rvif_t)::set(this, $sformatf("rmaster_%0d", i), "vif", mrbus);
                read_masters[i] = axi_master_read_agent::type_id::create($sformatf("rmaster_%0d", i), this);
                read_sequences[i] = fabric_r_sequence::type_id::create($sformatf("rseq_%0d", i));
                read_sequences[i].source = i;
                // Read slave
                if (!uvm_config_db#(slave_rvif_t)::get(this, "", $sformatf("slave_rvif_%0d", i), srbus))
                    `uvm_fatal("RSYS_SVIF", "Missing read slave interface")
                srcfg = axi_slave_pkg::axi_slave_cfg::type_id::create($sformatf("srcfg_%0d", i));
                srcfg.base_addr = 64'(i) << 16;
                srcfg.size_bytes = 65536;
                srcfg.max_outstanding = 4;
                srcfg.response_order = axi_slave_pkg::B_RANDOM_READY;
                srcfg.seed = 32'(seed + i * 101);
                srcfg.aw_random_stall_max = 3;
                srcfg.b_random_delay_max = 5;
                srcfg.reject_enable = 1;
                srcfg.reject_first = srcfg.base_addr + 'h8000;
                srcfg.reject_last  = srcfg.base_addr + 'h8fff;
                uvm_config_db#(axi_slave_pkg::axi_slave_cfg)::set(this, $sformatf("rslave_%0d", i), "cfg", srcfg);
                uvm_config_db#(slave_rvif_t)::set(this, $sformatf("rslave_%0d", i), "vif", srbus);
                read_slaves[i] = axi_slave_read_agent::type_id::create($sformatf("rslave_%0d", i), this);
            end
            r_scoreboard = fabric_r_scoreboard::type_id::create("r_scoreboard", this);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            wait (r_scoreboard.master_bus[0].ARESETn);
            // Pre-fill slave memories with known pattern so read data can be checked
            for (int i = 0; i < PORTS; i++) begin
                for (longint unsigned addr = 64'(i) << 16; addr < (64'(i + 1) << 16); addr++) begin
                    byte unsigned v = 8'((addr[7:0] ^ 8'(i * 17)) & 8'hff);
                    read_slaves[i].driver.memory.write_byte(addr, v);
                    r_scoreboard.expected_mem[i][addr] = v;
                end
            end
            fork
                read_sequences[0].start(read_masters[0].sequencer);
                read_sequences[1].start(read_masters[1].sequencer);
                read_sequences[2].start(read_masters[2].sequencer);
                read_sequences[3].start(read_masters[3].sequencer);
            join
            repeat (50) @(r_scoreboard.master_bus[0].mon);
            #1;
            if (!r_scoreboard.empty() ||
                r_scoreboard.ar_count != PORTS * R_REQS ||
                r_scoreboard.r_complete != PORTS * R_REQS ||
                r_scoreboard.decerr_count != 16 ||
                r_scoreboard.error_responses != 4 ||
                r_scoreboard.r_stalls == 0) begin
                `uvm_error("RSYS_FINAL", "Read counts, completion, or backpressure witnesses missing")
            end
            for (int i = 0; i < PORTS; i++) begin
                if (!read_masters[i].driver.idle() || !read_masters[i].monitor.idle() ||
                    !read_slaves[i].idle() || r_scoreboard.peak[i] != 2)
                    `uvm_error("RSYS_DRAIN", "Read components not drained or concurrency unobserved")
            end
            `uvm_info("RSYS_WITNESS", $sformatf("ar=%0d r_complete=%0d down_ar=%0d down_r_beats=%0d up_r_beats=%0d decerr=%0d slverr=%0d r_stalls=%0d",
                r_scoreboard.ar_count, r_scoreboard.r_complete, r_scoreboard.down_ar_count,
                r_scoreboard.down_r_beats, r_scoreboard.up_r_beats,
                r_scoreboard.decerr_count, r_scoreboard.error_responses, r_scoreboard.r_stalls), UVM_LOW)
            `uvm_info("CHECK_PASS", "crossbar_uvm5_test completed read checks; runner must also check UVM errors", UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass
endpackage
