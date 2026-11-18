`timescale 1ns/1ps
`include "axi_widths.svh"
module top;
    import uvm_pkg::*;
    import crossbar_uvm_pkg::*;
    localparam int INPUTS = 4;
    localparam int SLAVES = 4;
    localparam int ADDR_WIDTH = `AXI_ADDR_W;
    localparam int DATA_WIDTH = `AXI_DATA_W;
    localparam int ID_WIDTH = `AXI_MASTER_ID_W;
    localparam int OUTPUT_ID_WIDTH = `AXI_SLAVE_ID_W;
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    bit clk = 0;
    logic reset_n = 0;
    always #5 clk = ~clk;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_base;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_limit;
    logic [INPUTS-1:0] s_awvalid;
    logic [INPUTS-1:0] s_awready;
    logic [INPUTS-1:0][ID_WIDTH-1:0] s_awid;
    logic [INPUTS-1:0][ADDR_WIDTH-1:0] s_awaddr;
    logic [INPUTS-1:0][8-1:0] s_awlen;
    logic [INPUTS-1:0][3-1:0] s_awsize;
    logic [INPUTS-1:0][2-1:0] s_awburst;
    logic [INPUTS-1:0] s_awlock;
    logic [INPUTS-1:0][4-1:0] s_awcache;
    logic [INPUTS-1:0][3-1:0] s_awprot;
    logic [INPUTS-1:0][4-1:0] s_awqos;
    logic [INPUTS-1:0] s_wvalid;
    logic [INPUTS-1:0] s_wready;
    logic [INPUTS-1:0][DATA_WIDTH-1:0] s_wdata;
    logic [INPUTS-1:0][STRB_WIDTH-1:0] s_wstrb;
    logic [INPUTS-1:0] s_wlast;
    logic [INPUTS-1:0] s_bvalid;
    logic [INPUTS-1:0] s_bready;
    logic [INPUTS-1:0][ID_WIDTH-1:0] s_bid;
    logic [INPUTS-1:0][2-1:0] s_bresp;
    logic [SLAVES-1:0] m_awvalid;
    logic [SLAVES-1:0] m_awready;
    logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_awid;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0] m_awaddr;
    logic [SLAVES-1:0][8-1:0] m_awlen;
    logic [SLAVES-1:0][3-1:0] m_awsize;
    logic [SLAVES-1:0][2-1:0] m_awburst;
    logic [SLAVES-1:0] m_awlock;
    logic [SLAVES-1:0][4-1:0] m_awcache;
    logic [SLAVES-1:0][3-1:0] m_awprot;
    logic [SLAVES-1:0][4-1:0] m_awqos;
    logic [SLAVES-1:0] m_wvalid;
    logic [SLAVES-1:0] m_wready;
    logic [SLAVES-1:0][DATA_WIDTH-1:0] m_wdata;
    logic [SLAVES-1:0][STRB_WIDTH-1:0] m_wstrb;
    logic [SLAVES-1:0] m_wlast;
    logic [SLAVES-1:0] m_bvalid;
    logic [SLAVES-1:0] m_bready;
    logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_bid;
    logic [SLAVES-1:0][2-1:0] m_bresp;
    axi_write_if#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) master_bus[4](clk, reset_n);
    axi_write_if#(ADDR_WIDTH, DATA_WIDTH, OUTPUT_ID_WIDTH) slave_bus[4](clk, reset_n);
    axi_crossbar_write #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (.*);
    for (genvar i = 0; i < 4; i++) begin : ports
        assign map_base[i] = ADDR_WIDTH'(i) << 16;
        assign map_limit[i] = map_base[i] + ADDR_WIDTH'('hffff);
        axi_write_checker master_checker(master_bus[i]);
        axi_write_checker slave_checker(slave_bus[i]);
        assign s_awvalid[i] = master_bus[i].AWVALID;
        assign master_bus[i].AWREADY = s_awready[i];
        assign s_awid[i] = master_bus[i].AWID;
        assign s_awaddr[i] = master_bus[i].AWADDR;
        assign s_awlen[i] = master_bus[i].AWLEN;
        assign s_awsize[i] = master_bus[i].AWSIZE;
        assign s_awburst[i] = master_bus[i].AWBURST;
        assign s_awlock[i] = master_bus[i].AWLOCK;
        assign s_awcache[i] = master_bus[i].AWCACHE;
        assign s_awprot[i] = master_bus[i].AWPROT;
        assign s_awqos[i] = master_bus[i].AWQOS;
        assign s_wvalid[i] = master_bus[i].WVALID;
        assign master_bus[i].WREADY = s_wready[i];
        assign s_wdata[i] = master_bus[i].WDATA;
        assign s_wstrb[i] = master_bus[i].WSTRB;
        assign s_wlast[i] = master_bus[i].WLAST;
        assign master_bus[i].BVALID = s_bvalid[i];
        assign s_bready[i] = master_bus[i].BREADY;
        assign master_bus[i].BID = s_bid[i];
        assign master_bus[i].BRESP = s_bresp[i];
        assign slave_bus[i].AWVALID = m_awvalid[i];
        assign m_awready[i] = slave_bus[i].AWREADY;
        assign slave_bus[i].AWID = m_awid[i];
        assign slave_bus[i].AWADDR = m_awaddr[i];
        assign slave_bus[i].AWLEN = m_awlen[i];
        assign slave_bus[i].AWSIZE = m_awsize[i];
        assign slave_bus[i].AWBURST = m_awburst[i];
        assign slave_bus[i].AWLOCK = m_awlock[i];
        assign slave_bus[i].AWCACHE = m_awcache[i];
        assign slave_bus[i].AWPROT = m_awprot[i];
        assign slave_bus[i].AWQOS = m_awqos[i];
        assign slave_bus[i].WVALID = m_wvalid[i];
        assign m_wready[i] = slave_bus[i].WREADY;
        assign slave_bus[i].WDATA = m_wdata[i];
        assign slave_bus[i].WSTRB = m_wstrb[i];
        assign slave_bus[i].WLAST = m_wlast[i];
        assign m_bvalid[i] = slave_bus[i].BVALID;
        assign slave_bus[i].BREADY = m_bready[i];
        assign m_bid[i] = slave_bus[i].BID;
        assign m_bresp[i] = slave_bus[i].BRESP;
        initial begin
            uvm_config_db#(master_vif_t)::set(null, "uvm_test_top*", $sformatf("master_vif_%0d", i), master_bus[i]);
            uvm_config_db#(slave_vif_t)::set(null, "uvm_test_top*", $sformatf("slave_vif_%0d", i), slave_bus[i]);
        end
    end
    initial begin
        repeat (4) @(posedge clk);
        #1;
        reset_n = 1;
    end
    initial begin
        run_test("crossbar_uvm_test");
    end
    initial begin
        #2000000;
        $fatal(1, "WATCHDOG: UVM Crossbar test did not complete");
    end
endmodule
