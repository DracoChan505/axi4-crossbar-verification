`timescale 1ns / 1ps
`include "axi_widths.svh"
package axi_master_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    localparam ADDR_W = `AXI_ADDR_W, DATA_W = `AXI_DATA_W, ID_W = `AXI_MASTER_ID_W, STRB_W = DATA_W / 8;
    `include "axi_write_item.svh"
    `include "axi_master_cfg.svh"
    `include "axi_master_driver.svh"
    `include "axi_master_monitor.svh"
    `include "axi_master_agent.svh"
endpackage
