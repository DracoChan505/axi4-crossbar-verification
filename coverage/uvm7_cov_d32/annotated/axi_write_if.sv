//      // verilator_coverage annotation
        `timescale 1ns/1ps
        `include "axi_widths.svh"
        interface axi_write_if #(
            parameter int AW = `AXI_ADDR_W,
            parameter int DW = `AXI_DATA_W,
            parameter int IW = `AXI_ID_W
 013272 ) (input logic ACLK, input logic ARESETn);
 003879  logic AWVALID, AWREADY;
~000356  logic [AW-1:0] AWADDR;
~000356  logic [IW-1:0] AWID;
~000085  logic [7:0] AWLEN;
~000102  logic [2:0] AWSIZE, AWPROT;
~000102  logic [1:0] AWBURST;
%000000  logic AWLOCK;
~000102  logic [3:0] AWCACHE, AWQOS;
 000699  logic WVALID, WREADY, WLAST;
~000467  logic [DW-1:0] WDATA;
 000494  logic [DW/8-1:0] WSTRB;
 001168  logic BVALID, BREADY;
~000295  logic [IW-1:0] BID;
%000000  logic [1:0] BRESP;
        
         // Only mon clocking block (input-only, no conflict with assign).
         // Drivers use direct vif.SIGNAL <= assignment.
 013272  clocking mon @(posedge ACLK);
          default input #1step;
          input ARESETn, AWVALID, AWREADY, AWADDR, AWID, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS;
          input WVALID, WREADY, WDATA, WSTRB, WLAST, BVALID, BREADY, BID, BRESP;
         endclocking
        endinterface
        
