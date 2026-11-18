`timescale 1ns/1ps
`include "axi_widths.svh"
interface axi_read_if #(
    parameter int AW = `AXI_ADDR_W,
    parameter int DW = `AXI_DATA_W,
    parameter int IW = `AXI_ID_W
) (input logic ACLK, input logic ARESETn);
 logic ARVALID, ARREADY;
 logic [AW-1:0] ARADDR;
 logic [IW-1:0] ARID;
 logic [7:0] ARLEN;
 logic [2:0] ARSIZE, ARPROT;
 logic [1:0] ARBURST;
 logic ARLOCK;
 logic [3:0] ARCACHE, ARQOS;
 logic RVALID, RREADY, RLAST;
 logic [DW-1:0] RDATA;
 logic [IW-1:0] RID;
 logic [1:0] RRESP;

 // Only mon clocking block (input-only, no conflict with assign).
 // Drivers use direct vif.SIGNAL <= assignment.
 clocking mon @(posedge ACLK);
  default input #1step;
  input ARESETn, ARVALID, ARREADY, ARADDR, ARID, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS;
  input RVALID, RREADY, RDATA, RID, RLAST, RRESP;
 endclocking
endinterface
