`timescale 1ns/1ps
module top;
    import uvm_pkg::*;
    import monitor_test_pkg::*;
    bit clk = 0;
    logic reset_n = 0;
    always #5 clk = ~clk;
    axi_write_if bus(clk, reset_n);
    initial begin
        uvm_event reset_request;
        reset_request = uvm_event_pool::get_global("monitor_reset_request");
        repeat (3) @(posedge clk);
        #1;
        reset_n = 1;
        forever begin
            reset_request.wait_trigger();
            @(negedge clk);
            reset_n = 0;
            repeat (3) @(posedge clk);
            #1;
            reset_n = 1;
        end
    end
    initial begin
        uvm_config_db#(virtual axi_write_if)::set(null, "uvm_test_top", "vif", bus);
        run_test("slave_monitor_test");
    end
    initial begin
        #100000;
        $fatal(1, "MONITOR_WATCHDOG");
    end
endmodule
