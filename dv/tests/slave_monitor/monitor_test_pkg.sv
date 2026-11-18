`timescale 1ns/1ps
package monitor_test_pkg;
    import uvm_pkg::*;
    import axi_slave_pkg::*;
    `include "uvm_macros.svh"
    class event_listener extends uvm_subscriber#(axi_slave_observation);
        `uvm_component_utils(event_listener)
        int aw_count = 0;
        int write_count = 0;
        int b_count = 0;
        int reset_count = 0;
        int cancelled = 0;
        bit mutate_aw = 0;
        axi_slave_observation first_aw;
        axi_slave_observation completions[$];
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void write(axi_slave_observation item);
            case (item.kind)
                SLAVE_AW: begin
                    aw_count++;
                    if (first_aw == null) begin
                        first_aw = item;
                    end
                    if (mutate_aw) begin
                        item.id = '1;
                        item.data.push_back(DATA_W'('hdead));
                    end
                end
                SLAVE_WRITE: begin
                    write_count++;
                    if (mutate_aw && (item.id != 0 || item.data.size() != 1 || item.data[0] != DATA_W'('h12345678))) begin
                        `uvm_error("UNIT_SNAPSHOT", "Published event changed the Monitor's live transaction")
                    end
                end
                SLAVE_B: begin
                    b_count++;
                    completions.push_back(item);
                end
                SLAVE_RESET: begin
                    reset_count++;
                    cancelled += item.cancelled_aw;
                end
            endcase
        endfunction
    endclass

    class slave_monitor_test extends uvm_test;
        `uvm_component_utils(slave_monitor_test)
        virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
        axi_slave_agent agent;
        event_listener listener;
        string test_case = "smoke";
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            axi_slave_cfg cfg;
            void'($value$plusargs("CASE=%s", test_case));
            if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif)) begin
                `uvm_fatal("UNIT_VIF", "Missing interface")
            end
            cfg = axi_slave_cfg::type_id::create("cfg");
            cfg.active = 0;
            uvm_config_db#(axi_slave_cfg)::set(this, "agent", "cfg", cfg);
            uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::set(this, "agent", "vif", vif);
            agent = axi_slave_agent::type_id::create("agent", this);
            listener = event_listener::type_id::create("listener", this);
            listener.mutate_aw = test_case == "snapshot";
        endfunction
        function void connect_phase(uvm_phase phase);
            agent.monitor.events.connect(listener.analysis_export);
        endfunction
        // Directed fixture changes signals on falling edges; Monitor samples #1step.
        task tick(bit av = 0, bit ar = 1, bit wv = 0, bit wr = 1,
                  bit bv = 0, bit br = 1, int addr = 'h1000, int id = 0,
                  int len = 0, int size = 2, int data = 'h12345678,
                  int strb = 15, bit last = 1, int bid = 0, int resp = 0);
            @(negedge vif.ACLK);
            vif.AWVALID = av;
            vif.AWREADY = ar;
            vif.AWADDR = ADDR_W'(addr);
            vif.AWID = ID_W'(id);
            vif.AWLEN = 8'(len);
            vif.AWSIZE = 3'(size);
            vif.AWBURST = 1;
            vif.AWLOCK = 0;
            vif.AWCACHE = 2;
            vif.AWPROT = 2;
            vif.AWQOS = 0;
            vif.WVALID = wv;
            vif.WREADY = wr;
            vif.WDATA = DATA_W'(data);
            vif.WSTRB = STRB_W'(strb);
            vif.WLAST = last;
            vif.BVALID = bv;
            vif.BREADY = br;
            vif.BID = ID_W'(bid);
            vif.BRESP = 2'(resp);
            @(vif.mon);
            #1;
        endtask
        task run_phase(uvm_phase phase);
            uvm_event reset_request;
            bit negative;
            phase.raise_objection(this);
            wait (vif.ARESETn);
            if (agent.driver != null) begin
                `uvm_fatal("UNIT_PASSIVE", "Passive agent created a driver")
            end
            negative = test_case.len() >= 4 && test_case.substr(0, 3) == "neg_";
            case (test_case)
                "smoke", "snapshot": begin
                    tick(.av(1));
                    tick(.wv(1));
                    tick(.bv(1));
                end
                "w_first": begin
                    tick(.wv(1));
                    tick(.av(1));
                    tick(.bv(1));
                end
                "order": begin
                    tick(.av(1), .addr('h1000), .id(0));
                    tick(.av(1), .addr('h1004), .id(0));
                    tick(.av(1), .addr('h1008), .id(1));
                    tick(.wv(1), .data(17));
                    tick(.wv(1), .data(34));
                    tick(.wv(1), .data(51));
                    tick(.bv(1), .bid(1));
                    tick(.bv(1), .bid(0));
                    tick(.bv(1), .bid(0));
                end
                "reset": begin
                    tick(.av(1), .len(1));
                    tick(.wv(1), .last(0));
                    tick();
                    reset_request = uvm_event_pool::get_global("monitor_reset_request");
                    reset_request.trigger();
                    wait (!vif.ARESETn);
                    wait (vif.ARESETn);
                    tick(.av(1));
                    tick(.wv(1));
                    tick(.bv(1));
                end
                "neg_orphan": tick(.bv(1));
                "neg_early": begin
                    tick(.av(1));
                    tick(.bv(1));
                end
                "neg_last": begin
                    tick(.av(1), .len(1));
                    tick(.wv(1));
                end
                "neg_strb": begin
                    tick(.av(1), .size(0));
                    tick(.wv(1), .strb(2));
                end
                "neg_awstable": begin
                    tick(.av(1), .ar(0));
                    tick(.av(1), .addr('h1004));
                end
                "neg_wstable": begin
                    tick(.wv(1), .wr(0), .data(17));
                    tick(.wv(1), .data(34));
                end
                "neg_bstable": begin
                    tick(.av(1));
                    tick(.wv(1));
                    tick(.bv(1), .br(0));
                    tick(.bv(1), .resp(2));
                end
                default: `uvm_fatal("UNIT_CASE", "Unknown test")
            endcase
            tick();
            if (!negative) begin
                if (!agent.idle()) begin
                    `uvm_error("UNIT_DRAIN", "Monitor did not drain")
                end
                if (test_case == "order") begin
                    if (listener.b_count != 3 || listener.completions[0].address != 'h1008 ||
                        listener.completions[1].address != 'h1000 || listener.completions[2].address != 'h1004 || agent.monitor.reordered != 1) begin
                        `uvm_error("UNIT_ORDER", "Wrong same-ID or cross-ID association")
                    end
                end
                else if (listener.write_count != 1 || listener.b_count != 1 ||
                         listener.aw_count != (test_case == "reset" ? 2 : 1)) begin
                    `uvm_error("UNIT_COUNTS", "Event counts differ")
                end
                if (test_case == "reset" && (listener.reset_count != 1 || listener.cancelled != 1 || agent.monitor.cancelled != 1)) begin
                    `uvm_error("UNIT_RESET", "Reset cancellation event differs")
                end
                if (test_case != "snapshot" && (listener.first_aw.kind != SLAVE_AW || listener.first_aw.data.size() != 0)) begin
                    `uvm_error("UNIT_SNAPSHOT", "AW event was mutated by later Monitor processing")
                end
            end
            `uvm_info("CHECK_PASS", $sformatf("case=%s completed; runner checks expected error IDs", test_case), UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass
endpackage
