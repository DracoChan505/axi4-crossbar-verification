`timescale 1ns/1ps
`include "axi_widths.svh"
interface axi_write_if #(
    parameter int AW = `AXI_ADDR_W,
    parameter int DW = `AXI_DATA_W,
    parameter int IW = `AXI_ID_W
) (input logic ACLK, input logic ARESETn);
 logic AWVALID, AWREADY;
 logic [AW-1:0] AWADDR;
 logic [IW-1:0] AWID;
 logic [7:0] AWLEN;
 logic [2:0] AWSIZE, AWPROT;
 logic [1:0] AWBURST;
 logic AWLOCK;
 logic [3:0] AWCACHE, AWQOS;
 logic WVALID, WREADY, WLAST;
 logic [DW-1:0] WDATA;
 logic [DW/8-1:0] WSTRB;
 logic BVALID, BREADY;
 logic [IW-1:0] BID;
 logic [1:0] BRESP;

 // Only mon clocking block (input-only, no conflict with assign).
 // Drivers use direct vif.SIGNAL <= assignment.
 clocking mon @(posedge ACLK);
  default input #1step;
  input ARESETn, AWVALID, AWREADY, AWADDR, AWID, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS;
  input WVALID, WREADY, WDATA, WSTRB, WLAST, BVALID, BREADY, BID, BRESP;
 endclocking
endinterface
