`timescale 1ns/1ps
package slave_test_pkg;
    import uvm_pkg::*;
    import axi_slave_pkg::*;
    `include "uvm_macros.svh"

    // Deliberately drives pins directly: no Master item or Slave byte algorithm.
    class slave_stage1_test extends uvm_test;
        `uvm_component_utils(slave_stage1_test)

        virtual axi_write_if vif;
        axi_slave_cfg cfg;
        axi_slave_driver driver;
        string test_case = "smoke";
        longint unsigned cycle = 0;
        longint unsigned last_w_cycle;
        longint unsigned first_b_cycle;
        int aw_count = 0;
        int w_count = 0;
        int b_count = 0;
        bit aw_seen = 0;
        bit w_done = 0;
        bit b_seen = 0;
        bit [ID_W-1:0] requested_id;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual axi_write_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("VIF", "Test interface missing")
            end
            void'($value$plusargs("CASE=%s", test_case));
            cfg = axi_slave_cfg::type_id::create("cfg");
            if (test_case == "delay") begin
                cfg.b_delay_cycles = 3;
            end
            if (test_case == "reject") begin
                cfg.reject_enable = 1;
                cfg.reject_first = 'h1000;
                cfg.reject_last = 'h1fff;
            end
            uvm_config_db#(axi_slave_cfg)::set(this, "driver", "cfg", cfg);
            uvm_config_db#(virtual axi_write_if)::set(this, "driver", "vif", vif);
            driver = axi_slave_driver::type_id::create("driver", this);
        endfunction

        // Observe protocol events independently of Driver state.
        virtual task tick();
            @(vif.mon);
            cycle++;
            if (!vif.mon.ARESETn) begin
                aw_seen = 0;
                w_done = 0;
                b_seen = 0;
            end
            else begin
                if (vif.mon.BVALID) begin
                    if (!aw_seen || !w_done) begin
                        `uvm_error("TEST_EARLY_B", "B appeared before accepted AW and final W")
                    end
                    if (vif.mon.BID != requested_id) begin
                        `uvm_error("TEST_BID", "BID did not preserve the full AWID")
                    end
                    if (!b_seen) begin
                        first_b_cycle = cycle;
                        b_seen = 1;
                    end
                end
                if (vif.mon.WVALID && vif.mon.WREADY) begin
                    if (!aw_seen) begin
                        `uvm_error("TEST_W_WITHOUT_AW", "W accepted before AW")
                    end
                    w_count++;
                    if (vif.mon.WLAST) begin
                        w_done = 1;
                        last_w_cycle = cycle;
                    end
                end
                if (vif.mon.AWVALID && vif.mon.AWREADY) begin
                    aw_seen = 1;
                    aw_count++;
                end
                if (vif.mon.BVALID && vif.mon.BREADY) begin
                    b_count++;
                end
            end
        endtask

        task send_aw(longint unsigned address, int beats, int size);
            aw_seen = 0;
            w_done = 0;
            b_seen = 0;
            requested_id = '1;
            vif.AWADDR <= ADDR_W'(address);
            vif.AWID <= requested_id;
            vif.AWLEN <= 8'(beats - 1);
            vif.AWSIZE <= 3'(size);
            vif.AWBURST <= 2'b01;
            vif.AWLOCK <= 0;
            vif.AWCACHE <= 2;
            vif.AWPROT <= 2;
            vif.AWQOS <= 0;
            vif.AWVALID <= 1;
            do begin
                tick();
            end while (!(vif.mon.AWVALID && vif.mon.AWREADY));
            vif.AWVALID <= 0;
        endtask

        task send_w(bit [DATA_W-1:0] data, bit [STRB_W-1:0] mask, bit last);
            vif.WDATA <= data;
            vif.WSTRB <= mask;
            vif.WLAST <= last;
            vif.WVALID <= 1;
            do begin
                tick();
            end while (!(vif.mon.WVALID && vif.mon.WREADY));
            vif.WVALID <= 0;
            // Drive at the sampling event, then allow memory updates to settle.
            #1;
        endtask

        task take_b(bit [1:0] status, int stall_cycles = 0);
            do begin
                tick();
            end while (!vif.mon.BVALID);
            if (first_b_cycle != last_w_cycle + 64'(cfg.b_delay_cycles) + 1) begin
                `uvm_error("TEST_B_DELAY", "Unexpected first BVALID cycle")
            end
            repeat (stall_cycles) begin
                if (!vif.mon.BVALID || vif.mon.BRESP != status || driver.idle()) begin
                    `uvm_error("TEST_B_HOLD", "Response changed or retired under backpressure")
                end
                tick();
            end
            if (vif.mon.BRESP != status) begin
                `uvm_error("TEST_BRESP", "Unexpected response status")
            end
            vif.BREADY <= 1;
            tick();
            if (!vif.mon.BVALID || !vif.mon.BREADY) begin
                `uvm_error("TEST_B_HANDSHAKE", "Expected response handshake")
            end
            vif.BREADY <= 0;
            tick();
            #1;
            if (!driver.idle() || vif.mon.BVALID) begin
                `uvm_error("TEST_DRAIN", "Transaction did not drain exactly once")
            end
        endtask

        function void expect_byte(longint unsigned address, byte unsigned value);
            if (driver.memory.peek_byte(address) != value) begin
                `uvm_error("TEST_MEMORY", $sformatf("address=%h actual=%h expected=%h",
                    address, driver.memory.peek_byte(address), value))
            end
        endfunction

        task reset_during_transfer();
            uvm_event reset_request;
            reset_request = uvm_event_pool::get_global("slave_reset_request");
            reset_request.trigger();
            do begin
                tick();
            end while (vif.mon.ARESETn);
            do begin
                if (vif.mon.AWREADY || vif.mon.WREADY || vif.mon.BVALID) begin
                    `uvm_error("TEST_RESET_OUTPUT", "Slave outputs active during reset")
                end
                tick();
            end while (!vif.mon.ARESETn);
            repeat (3) begin
                tick();
                if (vif.mon.BVALID || !driver.idle()) begin
                    `uvm_error("TEST_RESET_STALE", "Cancelled response survived reset")
                end
            end
        endtask

        task run_phase(uvm_phase phase);
            bit [DATA_W-1:0] data;
            bit [STRB_W-1:0] mask;
            int expected_aw;
            int expected_w;
            int expected_b;
            phase.raise_objection(this);
            vif.AWVALID <= 0;
            vif.WVALID <= 0;
            vif.BREADY <= 0;
            do begin
                tick();
            end while (!vif.mon.ARESETn);
            tick();
            driver.memory.clear_memory();
            expected_aw = 1;
            expected_w = 1;
            expected_b = 1;

            case (test_case)
                "smoke", "delay", "b_stall", "clear": begin
                    send_aw('h1000, 1, 2);
                    send_w(DATA_W'('h44332211), STRB_W'('b1111), 1);
                    // Check that bytes commit before the response handshake.
                    expect_byte('h1000, 'h11);
                    expect_byte('h1001, 'h22);
                    expect_byte('h1002, 'h33);
                    expect_byte('h1003, 'h44);
                    expect_byte('h1004, 0);
                    take_b(0, test_case == "b_stall" ? 7 : 0);
                    if (test_case == "clear") begin
                        driver.memory.clear_memory();
                        for (int i = 0; i < 4; i++) begin
                            expect_byte('h1000 + 64'(i), 0);
                        end
                    end
                end
                "w_first": begin
                    vif.WDATA <= DATA_W'('haabbccdd);
                    vif.WSTRB <= STRB_W'('b1111);
                    vif.WLAST <= 1;
                    vif.WVALID <= 1;
                    repeat (5) begin
                        tick();
                        if (vif.mon.WREADY || vif.mon.BVALID) begin
                            `uvm_error("TEST_W_FIRST", "Accepted W or responded before AW")
                        end
                    end
                    send_aw('h1000, 1, 2);
                    do begin
                        tick();
                    end while (!(vif.mon.WVALID && vif.mon.WREADY));
                    vif.WVALID <= 0;
                    take_b(0);
                    expect_byte('h1000, 'hdd);
                    expect_byte('h1003, 'haa);
                end
                "unaligned", "sparse": begin
                    // Literal byte expectations, independent of Slave address math.
                    expected_w = 2;
                    send_aw('h1001, 2, 2);
                    send_w(DATA_W'('h44332211), STRB_W'('b1110), 0);
                    if (DATA_W == 32) begin
                        data = DATA_W'('h88776655);
                        mask = STRB_W'(test_case == "sparse" ? 'b0101 : 'b1111);
                    end
                    else begin
                        data = DATA_W'(64'h88776655_00000000);
                        mask = STRB_W'(test_case == "sparse" ? 'h50 : 'hf0);
                    end
                    send_w(data, mask, 1);
                    take_b(0);
                    expect_byte('h1000, 0);
                    expect_byte('h1001, 'h22);
                    expect_byte('h1002, 'h33);
                    expect_byte('h1003, 'h44);
                    expect_byte('h1004, 'h55);
                    expect_byte('h1005, test_case == "sparse" ? 0 : 'h66);
                    expect_byte('h1006, 'h77);
                    expect_byte('h1007, test_case == "sparse" ? 0 : 'h88);
                    expect_byte('h1008, 0);
                end
                "max_burst": begin
                    expected_w = 256;
                    // 256 one-byte beats, ending exactly at the 4KB boundary.
                    send_aw('hf00, 256, 0);
                    for (int i = 0; i < 256; i++) begin
                        data = '0;
                        mask = '0;
                        data[8*(i % STRB_W) +: 8] = 8'(i ^ 'ha5);
                        mask[i % STRB_W] = 1;
                        send_w(data, mask, i == 255);
                    end
                    take_b(0);
                    for (int i = 0; i < 256; i++) begin
                        expect_byte('hf00 + 64'(i), 8'(i ^ 'ha5));
                    end
                    expect_byte('heff, 0);
                    expect_byte('h1000, 0);
                end
                "reject", "outside": begin
                    expected_w = 2;
                    // Known nonzero initialization makes accidental erasure visible.
                    for (int i = 0; i < 8; i++) begin
                        driver.memory.write_byte('h1000 + 64'(i), 8'('hc0 + i));
                    end
                    // Rejection must consume both beats, without storing either.
                    send_aw(test_case == "reject" ? 'h1000 : 'h10000, 2, 2);
                    send_w(DATA_W'('h44332211), STRB_W'('b1111), 0);
                    if (DATA_W == 32) begin
                        send_w(DATA_W'('h88776655), STRB_W'('b1111), 1);
                    end
                    else begin
                        send_w(DATA_W'(64'h88776655_00000000), STRB_W'('hf0), 1);
                    end
                    take_b(2'b10);
                    for (int i = 0; i < 8; i++) begin
                        expect_byte('h1000 + 64'(i), 8'('hc0 + i));
                        expect_byte(64'(i), 0);
                    end
                end
                "reset_partial": begin
                    expected_aw = 2;
                    expected_w = 2;
                    send_aw('h1000, 2, 2);
                    send_w(DATA_W'('h44332211), STRB_W'('b1111), 0);
                    reset_during_transfer();
                    expect_byte('h1000, 'h11);
                    expect_byte('h1003, 'h44);
                    expect_byte('h1004, 0);
                    send_aw('h1010, 1, 2);
                    send_w(DATA_W'('h88776655), STRB_W'('b1111), 1);
                    take_b(0);
                    expect_byte('h1010, 'h55);
                    expect_byte('h1000, 'h11);
                end
                "neg_wlast": begin
                    send_aw('h1000, 2, 2);
                    send_w('0, STRB_W'('b1111), 1);
                    `uvm_fatal("TEST_MISSED_FAULT", "Wrong WLAST was not rejected")
                end
                "neg_strb": begin
                    send_aw('h1001, 1, 0);
                    send_w('0, STRB_W'('b0001), 1);
                    `uvm_fatal("TEST_MISSED_FAULT", "Wrong WSTRB was not rejected")
                end
                "neg_boundary": begin
                    send_aw('hfff, 2, 0);
                    tick();
                    `uvm_fatal("TEST_MISSED_FAULT", "4KB crossing was not rejected")
                end
                default: begin
                    `uvm_fatal("TEST_CASE", "Unknown test case")
                end
            endcase
            if (aw_count != expected_aw || w_count != expected_w || b_count != expected_b) begin
                `uvm_error("TEST_COUNTS", $sformatf("AW=%0d W=%0d B=%0d", aw_count, w_count, b_count))
            end
            `uvm_info("CHECK_PASS", $sformatf("case=%s AW=%0d W=%0d B=%0d stage=single_transaction",
                test_case, aw_count, w_count, b_count), UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass
    `include "slave_acceptance_test.svh"
endpackage
