`timescale 1ns/1ps
module axi_write_checker(axi_write_if b);
 import uvm_pkg::*;
 `include "uvm_macros.svh"
 aw_stable: assert property(@(posedge b.ACLK) disable iff(!b.ARESETn)
  b.AWVALID && !b.AWREADY |=> b.AWVALID && $stable({b.AWADDR,b.AWID,b.AWLEN,b.AWSIZE,b.AWBURST,b.AWLOCK,b.AWCACHE,b.AWPROT,b.AWQOS}))
  else `uvm_error("AW_STABILITY","AW changed while stalled")
 w_stable: assert property(@(posedge b.ACLK) disable iff(!b.ARESETn)
  b.WVALID && !b.WREADY |=> b.WVALID && $stable({b.WDATA,b.WSTRB,b.WLAST}))
  else `uvm_error("W_STABILITY","W changed while stalled")
 b_stable: assert property(@(posedge b.ACLK) disable iff(!b.ARESETn)
  b.BVALID && !b.BREADY |=> b.BVALID && $stable({b.BID,b.BRESP}))
  else `uvm_error("B_STABILITY","B changed while stalled")
endmodule
