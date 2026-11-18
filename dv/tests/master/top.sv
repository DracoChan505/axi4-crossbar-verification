`timescale 1ns/1ps
module top;
 import uvm_pkg::*;import axi_master_pkg::*;import master_test_pkg::*;
 bit clk=0;logic rst_n=0;
 always #5 clk=~clk;
 axi_write_if bus(clk,rst_n);
 axi_write_checker checker_i(bus);
 initial begin
  if(ADDR_W<12 || ADDR_W>63 || DATA_W<8 || DATA_W>1024 || (STRB_W & (STRB_W-1))!=0 || ID_W<1 || ID_W>16)
   $fatal(1,"unsupported parameter configuration");
 end
 initial begin
  string mode;
  void'($value$plusargs("CASE=%s",mode));
  repeat(3)@(posedge clk);#1;rst_n=1;
  if(mode=="reset_aw")begin wait(bus.AWVALID && bus.AWREADY);@(posedge clk);@(negedge clk);rst_n=0;end
  else if(mode=="reset_w")begin repeat(3)begin do @(posedge clk);while(!(bus.WVALID && bus.WREADY));end @(negedge clk);rst_n=0;end
  else if(mode=="reset_b")begin do @(posedge clk);while(!(bus.WVALID && bus.WREADY && bus.WLAST));@(negedge clk);rst_n=0;end
  else if(mode=="reset_bvalid")begin do @(posedge clk);while(!(bus.BVALID && !bus.BREADY));@(negedge clk);rst_n=0;end
  else if(mode=="reset_queued")begin repeat(15)@(posedge clk);@(negedge clk);rst_n=0;end
  if(mode.substr(0,5)=="reset_")begin repeat(3)@(posedge clk);#1;rst_n=1;end
 end
 initial begin
  uvm_config_db#(virtual axi_write_if)::set(null,"uvm_test_top","vif",bus);
  run_test("master_test");
 end
 initial begin #1000000; $fatal(1,"WATCHDOG");end
endmodule
