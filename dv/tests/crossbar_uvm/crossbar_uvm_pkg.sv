`timescale 1ns/1ps
package crossbar_uvm_pkg;
    import uvm_pkg::*;
    import axi_master_pkg::*;
    `include "uvm_macros.svh"
    typedef virtual axi_write_if#(ADDR_W, DATA_W, ID_W) master_vif_t;
    typedef virtual axi_write_if#(ADDR_W, DATA_W, axi_slave_pkg::ID_W) slave_vif_t;
    localparam int PORTS = 4;
    localparam int REQUESTS = 24;

    class fabric_record;
        int source;
        int target;
        bit [ID_W-1:0] id;
        longint unsigned address;
        int beats;
        int size;
        bit [16:0] attr;
        bit [1:0] response;
        bit [DATA_W-1:0] data[$];
        bit [STRB_W-1:0] strb[$];
        int received = 0;
        int forwarded = 0;
        bit downstream_response = 0;
        longint unsigned input_done_cycle;
        longint unsigned output_done_cycle;
    endclass

    class fabric_sequence extends uvm_sequence#(axi_write_item);
        `uvm_object_utils(fabric_sequence)
        int source;
        int responses = 0;
        bit seen[int];
        bit [1:0] expected_resp[REQUESTS];
        bit [ADDR_W-1:0] expected_addr[REQUESTS];
        function new(string name = "fabric_sequence");
            super.new(name);
        endfunction
        function void response_handler(uvm_sequence_item response);
            axi_write_item result;
            int tag;
            if (!$cast(result, response)) begin
                `uvm_fatal("SYS_RESPONSE_TYPE", "Unexpected completion type")
            end
            tag = result.get_transaction_id();
            if (tag < 0 || tag >= REQUESTS) begin
                `uvm_fatal("SYS_RESPONSE_TAG", "Completion tag outside submitted range")
            end
            if (seen.exists(tag) || result.addr != expected_addr[tag] || result.resp != expected_resp[tag]) begin
                `uvm_error("SYS_SEQUENCE_RESPONSE", "Wrong or repeated completion")
            end
            seen[tag] = 1;
            responses++;
        endfunction
        task body();
            int target;
            longint unsigned address;
            use_response_handler(1);
            for (int n = 0; n < REQUESTS; n++) begin
                req = axi_write_item::type_id::create("request");
                target = n % 5;
                if (n < 2) begin
                    target = 0;
                end
                if (n == 2 || n == 5) begin
                    target = 1;
                end
                if (n == 7) begin
                    target = 3;
                end
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
                req.aw_delay = n == 0 ? 8 : 32'(n % 3);
                req.w_delay = n == 0 ? 0 : 32'((n + source) % 4);
                req.w_gap = 32'(n % 2);
                req.qos = 4'(source + n);
                req.fill_pattern(source * 53 + n * 17, n % 3);
                req.set_transaction_id(n);
                expected_addr[n] = req.addr;
                expected_resp[n] = target == 4 ? 2'b11 : n == 5 ? 2'b10 : 2'b00;
                start_item(req);
                finish_item(req);
            end
            wait (responses == REQUESTS);
        endtask
    endclass

    // Passive observations of both sides. No driver queues or RTL state are read.
    class fabric_scoreboard extends uvm_component;
        `uvm_component_utils(fabric_scoreboard)
        master_vif_t master_bus[PORTS];
        slave_vif_t slave_bus[PORTS];
        fabric_record incoming_w[PORTS][$];
        fabric_record incoming_b[PORTS][$];
        fabric_record awaiting_forward[PORTS][$];
        fabric_record outgoing_w[PORTS][$];
        fabric_record outgoing_b[PORTS][$];
        fabric_record completed_downstream[PORTS][$];
        int port_aw[PORTS];
        int port_writes[PORTS];
        int port_beats[PORTS];
        byte unsigned expected_bytes[PORTS][longint unsigned];
        longint unsigned cycle = 0;
        int aw_count = 0;
        int b_count = 0;
        int down_aw_count = 0;
        int down_b_count = 0;
        int input_beats = 0;
        int output_beats = 0;
        int early_w_valid = 0;
        int aw_stalls = 0;
        int w_stalls = 0;
        int b_stalls = 0;
        int reordered = 0;
        int error_responses = 0;
        int rejected_responses = 0;
        int peak[PORTS];
        int size_hits[8];
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            for (int i = 0; i < PORTS; i++) begin
                if (!uvm_config_db#(master_vif_t)::get(this, "", $sformatf("master_vif_%0d", i), master_bus[i]) ||
                    !uvm_config_db#(slave_vif_t)::get(this, "", $sformatf("slave_vif_%0d", i), slave_bus[i])) begin
                    `uvm_fatal("SYS_VIF", "Missing system observation interface")
                end
            end
        endfunction
        function bit empty();
            for (int i = 0; i < PORTS; i++) begin
                if (incoming_w[i].size() != 0 || incoming_b[i].size() != 0 ||
                    awaiting_forward[i].size() != 0 || outgoing_w[i].size() != 0 || outgoing_b[i].size() != 0) begin
                    return 0;
                end
            end
            return 1;
        endfunction
        task run_phase(uvm_phase phase);
            fabric_record item;
            fabric_record consumed;
            int match_index;
            int src;
            int dest;
            int beat;
            int lane;
            longint unsigned block_start;
            longint unsigned address;
            bit [STRB_W-1:0] legal;
            forever begin
                @(master_bus[0].mon);
                cycle++;
                if (!master_bus[0].mon.ARESETn) begin
                    for (int i = 0; i < PORTS; i++) begin
                        incoming_w[i].delete();
                        incoming_b[i].delete();
                        awaiting_forward[i].delete();
                        outgoing_w[i].delete();
                        outgoing_b[i].delete();
                    end
                    continue;
                end
                for (int i = 0; i < PORTS; i++) begin
                    if (master_bus[i].mon.AWVALID && !master_bus[i].mon.AWREADY) begin
                        aw_stalls++;
                    end
                    if (master_bus[i].mon.WVALID && !master_bus[i].mon.WREADY) begin
                        w_stalls++;
                        if (incoming_w[i].size() == 0) begin
                            early_w_valid++;
                        end
                    end
                    if (master_bus[i].mon.BVALID) begin
                        match_index = -1;
                        foreach (incoming_b[i][j]) begin
                            if (match_index < 0 && incoming_b[i][j].id == master_bus[i].mon.BID) begin
                                match_index = j;
                            end
                        end
                        if (match_index < 0) begin
                            `uvm_fatal("SYS_ORPHAN_B", "Upstream B has no accepted AW")
                        end
                        item = incoming_b[i][match_index];
                        if (item.received != item.beats || item.input_done_cycle >= cycle ||
                            (item.target < PORTS && !item.downstream_response)) begin
                            `uvm_error("SYS_EARLY_B", "B precedes the required W/downstream B events")
                        end
                        if (master_bus[i].mon.BRESP != item.response) begin
                            `uvm_error("SYS_RESPONSE", "Incorrect upstream status")
                        end
                        if (master_bus[i].mon.BREADY) begin
                            incoming_b[i].delete(match_index);
                            b_count++;
                            if (match_index != 0) begin
                                reordered++;
                            end
                            if (item.response == 3) begin
                                error_responses++;
                            end
                            if (item.response == 2) begin
                                rejected_responses++;
                            end
                        end
                        else begin
                            b_stalls++;
                        end
                    end
                    if (master_bus[i].mon.WVALID && master_bus[i].mon.WREADY) begin
                        if (incoming_w[i].size() == 0) begin
                            `uvm_fatal("SYS_W_NO_AW", "Crossbar accepted W without a route")
                        end
                        item = incoming_w[i][0];
                        item.data.push_back(master_bus[i].mon.WDATA);
                        item.strb.push_back(master_bus[i].mon.WSTRB);
                        item.received++;
                        input_beats++;
                        if (master_bus[i].mon.WLAST != (item.received == item.beats)) begin
                            `uvm_error("SYS_INPUT_LAST", "Input burst length mismatch")
                        end
                        if (master_bus[i].mon.WLAST) begin
                            item.input_done_cycle = cycle;
                            consumed = incoming_w[i].pop_front();
                        end
                    end
                    if (master_bus[i].mon.AWVALID && master_bus[i].mon.AWREADY) begin
                        item = new;
                        item.source = i;
                        item.address = 64'(master_bus[i].mon.AWADDR);
                        dest = item.address < 'h40000 ? int'(item.address >> 16) : PORTS;
                        item.target = dest;
                        item.id = master_bus[i].mon.AWID;
                        item.beats = int'(master_bus[i].mon.AWLEN) + 1;
                        item.size = int'(master_bus[i].mon.AWSIZE);
                        item.attr = {master_bus[i].mon.AWSIZE, master_bus[i].mon.AWBURST,
                                     master_bus[i].mon.AWLOCK, master_bus[i].mon.AWCACHE,
                                     master_bus[i].mon.AWPROT, master_bus[i].mon.AWQOS};
                        item.response = dest == PORTS ? 2'b11 :
                                        ((item.address & 'hffff) >= 'h8000 && (item.address & 'hffff) <= 'h8fff) ? 2'b10 : 2'b00;
                        incoming_w[i].push_back(item);
                        incoming_b[i].push_back(item);
                        if (dest < PORTS) begin
                            awaiting_forward[i].push_back(item);
                        end
                        aw_count++;
                        size_hits[item.size]++;
                        if (incoming_b[i].size() > peak[i]) begin
                            peak[i] = incoming_b[i].size();
                        end
                        if (incoming_b[i].size() > 2) begin
                            `uvm_error("SYS_CAPACITY", "Input outstanding exceeded two")
                        end
                    end
                end
                for (int o = 0; o < PORTS; o++) begin
                    if (slave_bus[o].mon.BVALID) begin
                        match_index = -1;
                        foreach (outgoing_b[o][j]) begin
                            if (match_index < 0 &&
                                {2'(outgoing_b[o][j].source), outgoing_b[o][j].id} == slave_bus[o].mon.BID) begin
                                match_index = j;
                            end
                        end
                        if (match_index < 0) begin
                            `uvm_fatal("SYS_DOWNSTREAM_B", "Unknown downstream response")
                        end
                        item = outgoing_b[o][match_index];
                        if (item.forwarded != item.beats || item.output_done_cycle >= cycle || slave_bus[o].mon.BRESP != item.response) begin
                            `uvm_error("SYS_SLAVE_RESPONSE", "Bad Slave response timing/status")
                        end
                        if (slave_bus[o].mon.BREADY) begin
                            item.downstream_response = 1;
                            outgoing_b[o].delete(match_index);
                            down_b_count++;
                            completed_downstream[o].push_back(item);
                        end
                    end
                    if (slave_bus[o].mon.WVALID && slave_bus[o].mon.WREADY) begin
                        if (outgoing_w[o].size() == 0) begin
                            `uvm_fatal("SYS_DOWNSTREAM_W", "Output W without an observed AW")
                        end
                        item = outgoing_w[o][0];
                        beat = item.forwarded;
                        if (beat >= item.data.size()) begin
                            `uvm_fatal("SYS_W_NOT_RECEIVED", "Output beat was not accepted upstream")
                        end
                        if (slave_bus[o].mon.WDATA !== item.data[beat] || slave_bus[o].mon.WSTRB !== item.strb[beat] ||
                            slave_bus[o].mon.WLAST != (beat + 1 == item.beats)) begin
                            `uvm_error("SYS_W_ROUTE", "Wrong output data/strobe/last or burst association")
                        end
                        // Byte-address enumeration independent of Driver fill_pattern/allowed_mask.
                        block_start = ((item.address >> item.size) + 64'(beat)) << item.size;
                        legal = '0;
                        for (int offset = 0; offset < (1 << item.size); offset++) begin
                            address = block_start + 64'(offset);
                            lane = int'(address % STRB_W);
                            if (address >= item.address) begin
                                legal[lane] = 1;
                                if (item.strb[beat][lane] && item.response == 0) begin
                                    expected_bytes[o][address] = item.data[beat][8*lane +: 8];
                                end
                            end
                        end
                        if ((item.strb[beat] & ~legal) != 0) begin
                            `uvm_error("SYS_STROBE", "Observed illegal byte enable")
                        end
                        item.forwarded++;
                        output_beats++;
                        port_beats[o]++;
                        if (slave_bus[o].mon.WLAST) begin
                            item.output_done_cycle = cycle;
                            port_writes[o]++;
                            consumed = outgoing_w[o].pop_front();
                        end
                    end
                    if (slave_bus[o].mon.AWVALID && slave_bus[o].mon.AWREADY) begin
                        src = int'(slave_bus[o].mon.AWID[axi_slave_pkg::ID_W-1:ID_W]);
                        if (src >= PORTS || awaiting_forward[src].size() == 0) begin
                            `uvm_fatal("SYS_AW_SOURCE", "Unexpected output address/source")
                        end
                        item = awaiting_forward[src].pop_front();
                        if (item.target != o || item.address != 64'(slave_bus[o].mon.AWADDR) ||
                            item.id != ID_W'(slave_bus[o].mon.AWID) || item.beats != int'(slave_bus[o].mon.AWLEN) + 1 ||
                            item.attr != {slave_bus[o].mon.AWSIZE, slave_bus[o].mon.AWBURST,
                                          slave_bus[o].mon.AWLOCK, slave_bus[o].mon.AWCACHE,
                                          slave_bus[o].mon.AWPROT, slave_bus[o].mon.AWQOS}) begin
                            `uvm_error("SYS_AW_ROUTE", "Output AW differs from input AW/order")
                        end
                        outgoing_w[o].push_back(item);
                        outgoing_b[o].push_back(item);
                        down_aw_count++;
                        port_aw[o]++;
                    end
                end
            end
        endtask
    endclass

    class fabric_slave_listener extends uvm_subscriber#(axi_slave_pkg::axi_slave_observation);
        `uvm_component_utils(fabric_slave_listener)
        int aw_count = 0;
        int write_count = 0;
        int b_count = 0;
        axi_slave_pkg::axi_slave_observation first_aw;
        axi_slave_pkg::axi_slave_observation completed[$];
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void write(axi_slave_pkg::axi_slave_observation item);
            case (item.kind)
                axi_slave_pkg::SLAVE_AW: begin
                    aw_count++;
                    if (first_aw == null) begin
                        first_aw = item;
                    end
                end
                axi_slave_pkg::SLAVE_WRITE: write_count++;
                axi_slave_pkg::SLAVE_B: begin
                    b_count++;
                    completed.push_back(item);
                end
                default: begin
                end
            endcase
        endfunction
    endclass

    class crossbar_uvm_test extends uvm_test;
        `uvm_component_utils(crossbar_uvm_test)
        axi_master_agent masters[PORTS];
        axi_slave_pkg::axi_slave_agent slaves[PORTS];
        fabric_slave_listener slave_events[PORTS];
        axi_slave_pkg::axi_slave_agent passive_shadow;
        fabric_slave_listener passive_events;
        fabric_sequence sequences[PORTS];
        fabric_scoreboard scoreboard;
        int seed = 7;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            axi_master_cfg master_cfg;
            axi_slave_pkg::axi_slave_cfg slave_cfg;
            master_vif_t master_bus;
            slave_vif_t slave_bus;
            void'($value$plusargs("SEED=%d", seed));
            if (ID_W != 2 || axi_slave_pkg::ID_W != 4) begin
                `uvm_fatal("SYS_WIDTHS", "System test requires original ID2 and extended ID4")
            end
            for (int i = 0; i < PORTS; i++) begin
                if (!uvm_config_db#(master_vif_t)::get(this, "", $sformatf("master_vif_%0d", i), master_bus) ||
                    !uvm_config_db#(slave_vif_t)::get(this, "", $sformatf("slave_vif_%0d", i), slave_bus)) begin
                    `uvm_fatal("SYS_VIF", "Missing connected interface")
                end
                master_cfg = axi_master_cfg::type_id::create($sformatf("master_cfg_%0d", i));
                master_cfg.trace = 0;
                master_cfg.b_stall_period = 11;
                master_cfg.b_stall_cycles = 8;
                uvm_config_db#(axi_master_cfg)::set(this, $sformatf("master_%0d", i), "cfg", master_cfg);
                uvm_config_db#(master_vif_t)::set(this, $sformatf("master_%0d", i), "vif", master_bus);
                masters[i] = axi_master_agent::type_id::create($sformatf("master_%0d", i), this);
                sequences[i] = fabric_sequence::type_id::create($sformatf("sequence_%0d", i));
                sequences[i].source = i;
                slave_cfg = axi_slave_pkg::axi_slave_cfg::type_id::create($sformatf("slave_cfg_%0d", i));
                slave_cfg.base_addr = 64'(i) << 16;
                slave_cfg.size_bytes = 65536;
                slave_cfg.max_outstanding = 4;
                slave_cfg.response_order = axi_slave_pkg::B_RANDOM_READY;
                slave_cfg.seed = 32'(seed + i * 101);
                slave_cfg.aw_random_stall_max = 3;
                slave_cfg.w_random_stall_max = 4;
                slave_cfg.b_random_delay_max = 5;
                slave_cfg.reject_enable = 1;
                slave_cfg.reject_first = slave_cfg.base_addr + 'h8000;
                slave_cfg.reject_last = slave_cfg.base_addr + 'h8fff;
                if (i == 0) begin
                    slave_cfg.b_extra_delay_by_seq[0] = 80;
                end
                uvm_config_db#(axi_slave_pkg::axi_slave_cfg)::set(this, $sformatf("slave_%0d", i), "cfg", slave_cfg);
                uvm_config_db#(slave_vif_t)::set(this, $sformatf("slave_%0d", i), "vif", slave_bus);
                slaves[i] = axi_slave_pkg::axi_slave_agent::type_id::create($sformatf("slave_%0d", i), this);
                slave_events[i] = fabric_slave_listener::type_id::create($sformatf("slave_events_%0d", i), this);
            end
            slave_cfg = axi_slave_pkg::axi_slave_cfg::type_id::create("passive_cfg");
            slave_cfg.active = 0;
            if (!uvm_config_db#(slave_vif_t)::get(this, "", "slave_vif_0", slave_bus)) begin
                `uvm_fatal("SYS_PASSIVE_VIF", "Missing passive observation interface")
            end
            uvm_config_db#(axi_slave_pkg::axi_slave_cfg)::set(this, "passive_shadow", "cfg", slave_cfg);
            uvm_config_db#(slave_vif_t)::set(this, "passive_shadow", "vif", slave_bus);
            passive_shadow = axi_slave_pkg::axi_slave_agent::type_id::create("passive_shadow", this);
            passive_events = fabric_slave_listener::type_id::create("passive_events", this);
            scoreboard = fabric_scoreboard::type_id::create("scoreboard", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            for (int i = 0; i < PORTS; i++) begin
                slaves[i].monitor.events.connect(slave_events[i].analysis_export);
            end
            passive_shadow.monitor.events.connect(passive_events.analysis_export);
        endfunction
        task run_phase(uvm_phase phase);
            byte unsigned expected;
            axi_slave_pkg::axi_slave_observation observed;
            fabric_record reference_item;
            int bytes_checked;
            phase.raise_objection(this);
            wait (scoreboard.master_bus[0].ARESETn);
            fork
                sequences[0].start(masters[0].sequencer);
                sequences[1].start(masters[1].sequencer);
                sequences[2].start(masters[2].sequencer);
                sequences[3].start(masters[3].sequencer);
            join
            repeat (20) @(scoreboard.master_bus[0].mon);
            #1;
            if (!scoreboard.empty() || scoreboard.aw_count != PORTS * REQUESTS || scoreboard.b_count != PORTS * REQUESTS ||
                scoreboard.down_aw_count != scoreboard.down_b_count || scoreboard.error_responses != 16 ||
                scoreboard.rejected_responses != 4 || scoreboard.early_w_valid == 0 || scoreboard.b_stalls == 0) begin
                `uvm_error("SYS_FINAL", "Counts, completion, or required backpressure witnesses missing")
            end
            if ($test$plusargs("INJECT_MEMORY_FAULT")) begin
                slaves[0].driver.memory.write_byte('h7000, slaves[0].driver.memory.peek_byte('h7000) ^ 8'h01);
            end
            if (passive_shadow.driver != null || !passive_shadow.idle() ||
                passive_events.aw_count != slave_events[0].aw_count ||
                passive_events.write_count != slave_events[0].write_count ||
                passive_events.b_count != slave_events[0].b_count) begin
                `uvm_error("SYS_PASSIVE_AGENT", "Passive agent drove or observed a different stream")
            end
            bytes_checked = 0;
            for (int i = 0; i < PORTS; i++) begin
                if (!masters[i].driver.idle() || !masters[i].monitor.idle() || !slaves[i].idle() || scoreboard.peak[i] != 2) begin
                    `uvm_error("SYS_COMPONENT_DRAIN", "Components not drained or concurrency unobserved")
                end
                if (slave_events[i].aw_count != scoreboard.port_aw[i] ||
                    slave_events[i].write_count != scoreboard.port_writes[i] ||
                    slaves[i].monitor.beat_count != scoreboard.port_beats[i] ||
                    slave_events[i].completed.size() != scoreboard.completed_downstream[i].size()) begin
                    `uvm_error("SYS_MONITOR_COUNTS", "Monitor events differ from independent pin observations")
                end
                if (slave_events[i].first_aw == null || slave_events[i].first_aw.data.size() != 0 ||
                    slave_events[i].first_aw.kind != axi_slave_pkg::SLAVE_AW) begin
                    `uvm_error("SYS_EVENT_SNAPSHOT", "Published AW event was not an independent snapshot")
                end
                for (int j = 0; j < slave_events[i].completed.size() && j < scoreboard.completed_downstream[i].size(); j++) begin
                    observed = slave_events[i].completed[j];
                    reference_item = scoreboard.completed_downstream[i][j];
                    if (observed.id != {2'(reference_item.source), reference_item.id} ||
                        64'(observed.address) != reference_item.address || int'(observed.len) + 1 != reference_item.beats ||
                        int'(observed.size) != reference_item.size || observed.attr != reference_item.attr ||
                        observed.response != reference_item.response || observed.data != reference_item.data ||
                        observed.strb != reference_item.strb || !observed.write_done) begin
                        `uvm_error("SYS_MONITOR_EVENT", "Monitor transaction differs from independent observed transaction")
                    end
                    if (i == 0 && j < passive_events.completed.size()) begin
                        if (passive_events.completed[j].id != observed.id || passive_events.completed[j].address != observed.address ||
                            passive_events.completed[j].data != observed.data || passive_events.completed[j].strb != observed.strb ||
                            passive_events.completed[j].response != observed.response) begin
                            `uvm_error("SYS_PASSIVE_EVENT", "Passive and active observers differ")
                        end
                    end
                end
                for (longint unsigned address = 64'(i) << 16; address < (64'(i + 1) << 16); address++) begin
                    expected = scoreboard.expected_bytes[i].exists(address) ? scoreboard.expected_bytes[i][address] : 0;
                    if (slaves[i].driver.memory.peek_byte(address) != expected) begin
                        `uvm_error("SYS_MEMORY", $sformatf("Slave=%0d address=%h expected=%h actual=%h", i, address, expected, slaves[i].driver.memory.peek_byte(address)))
                    end
                    bytes_checked++;
                end
            end
            `uvm_info("SLAVE_AGENT_WITNESS", $sformatf("active_agents=4 passive_agents=1 monitor_completions=%0d passive_completions=%0d", scoreboard.down_b_count, passive_events.b_count), UVM_LOW)
            `uvm_info("SYS_WITNESS", $sformatf("aw=%0d b=%0d slave_aw=%0d slave_b=%0d input_w=%0d output_w=%0d decerr=%0d slverr=%0d early_w=%0d aw_stall=%0d w_stall=%0d b_stall=%0d reordered=%0d bytes_checked=%0d",
                      scoreboard.aw_count, scoreboard.b_count, scoreboard.down_aw_count, scoreboard.down_b_count,
                      scoreboard.input_beats, scoreboard.output_beats, scoreboard.error_responses, scoreboard.rejected_responses,
                      scoreboard.early_w_valid, scoreboard.aw_stalls, scoreboard.w_stalls, scoreboard.b_stalls, scoreboard.reordered, bytes_checked), UVM_LOW)
            `uvm_info("CHECK_PASS", "crossbar_uvm_test completed checks; runner must also check UVM errors", UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass
endpackage
