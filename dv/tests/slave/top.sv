`timescale 1ns/1ps
module top;
    import uvm_pkg::*;
    import axi_slave_pkg::*;
    import slave_test_pkg::*;

    bit clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    axi_write_if bus(clk, rst_n);
    axi_write_checker checker_i(bus);

    initial begin
        uvm_event reset_request;
        reset_request = uvm_event_pool::get_global("slave_reset_request");
        repeat (3) @(posedge clk);
        #1;
        rst_n = 1;
        forever begin
            reset_request.wait_trigger();
            @(negedge clk);
            rst_n = 0;
            repeat (3) @(posedge clk);
            #1;
            rst_n = 1;
        end
    end

    initial begin
        string test_name;
        test_name = "slave_stage1_test";
        uvm_config_db#(virtual axi_write_if)::set(null, "uvm_test_top", "vif", bus);
        void'($value$plusargs("TEST=%s", test_name));
        run_test(test_name);
    end

    initial begin
        #100000;
        $fatal(1, "WATCHDOG: Slave test did not complete");
    end
endmodule
