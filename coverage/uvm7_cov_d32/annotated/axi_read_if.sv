//      // verilator_coverage annotation
        `timescale 1ns/1ps
        `include "axi_widths.svh"
        interface axi_read_if #(
            parameter int AW = `AXI_ADDR_W,
            parameter int DW = `AXI_DATA_W,
            parameter int IW = `AXI_ID_W
 013272 ) (input logic ACLK, input logic ARESETn);
 002318  logic ARVALID, ARREADY;
~000365  logic [AW-1:0] ARADDR;
~000365  logic [IW-1:0] ARID;
~000086  logic [7:0] ARLEN;
~000108  logic [2:0] ARSIZE, ARPROT;
~000108  logic [1:0] ARBURST;
%000000  logic ARLOCK;
~000108  logic [3:0] ARCACHE, ARQOS;
 000653  logic RVALID, RREADY, RLAST;
~000508  logic [DW-1:0] RDATA;
 000303  logic [IW-1:0] RID;
%000000  logic [1:0] RRESP;
        
         // Only mon clocking block (input-only, no conflict with assign).
         // Drivers use direct vif.SIGNAL <= assignment.
 013272  clocking mon @(posedge ACLK);
          default input #1step;
          input ARESETn, ARVALID, ARREADY, ARADDR, ARID, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS;
          input RVALID, RREADY, RDATA, RID, RLAST, RRESP;
         endclocking
        endinterface
        
