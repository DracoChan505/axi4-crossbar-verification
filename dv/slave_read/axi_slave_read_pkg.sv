`timescale 1ns/1ps
`include "axi_widths.svh"
package axi_slave_read_pkg;
    import uvm_pkg::*;
    import axi_slave_pkg::*;
    `include "uvm_macros.svh"

    localparam ADDR_W  = `AXI_ADDR_W;
    localparam DATA_W  = `AXI_DATA_W;
    localparam ID_W    = `AXI_SLAVE_ID_W;   // expanded ID (source + original)
    localparam ORIG_ID_W = `AXI_MASTER_ID_W;
    localparam STRB_W  = DATA_W / 8;

    `include "axi_slave_read_driver.svh"
    `include "axi_slave_read_agent.svh"
endpackage
