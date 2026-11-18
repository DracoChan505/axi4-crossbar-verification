`timescale 1ns/1ps
`include "axi_widths.svh"
package axi_slave_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam ADDR_W = `AXI_ADDR_W;
    localparam DATA_W = `AXI_DATA_W;
    localparam ID_W = `AXI_SLAVE_ID_W;
    localparam STRB_W = DATA_W / 8;

    typedef enum int { B_IN_ORDER, B_OLDEST_READY, B_RANDOM_READY } axi_slave_response_order;

    `include "axi_slave_observation.svh"
    `include "axi_slave_cfg.svh"
    `include "axi_slave_record.svh"
    `include "axi_slave_memory.svh"
    `include "axi_slave_driver.svh"
    `include "axi_slave_monitor.svh"
    `include "axi_slave_agent.svh"
endpackage
