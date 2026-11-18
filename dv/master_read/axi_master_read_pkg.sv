`timescale 1ns / 1ps
`include "axi_widths.svh"
package axi_master_read_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    localparam ADDR_W  = `AXI_ADDR_W;
    localparam DATA_W  = `AXI_DATA_W;
    localparam ID_W    = `AXI_MASTER_ID_W;
    localparam STRB_W  = DATA_W / 8;
    `include "axi_read_item.svh"
    `include "axi_master_read_cfg.svh"
    `include "axi_master_read_driver.svh"
    `include "axi_master_read_monitor.svh"
    `include "axi_master_read_agent.svh"
endpackage
