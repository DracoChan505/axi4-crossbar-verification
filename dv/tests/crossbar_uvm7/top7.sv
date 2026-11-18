`timescale 1ns/1ps
`include "axi_widths.svh"
module top7;
    import uvm_pkg::*;
    import crossbar_uvm7_pkg::*;
    localparam int INPUTS        = 4;
    localparam int SLAVES        = 4;
    localparam int ADDR_WIDTH    = `AXI_ADDR_W;
    localparam int DATA_WIDTH    = `AXI_DATA_W;
    localparam int ID_WIDTH      = `AXI_MASTER_ID_W;
    localparam int OUTPUT_ID_WIDTH = `AXI_SLAVE_ID_W;
    localparam int STRB_WIDTH    = DATA_WIDTH / 8;

    bit   clk     = 0;
    logic reset_n;
    always #5 clk = ~clk;

    // ---- Write channel signals ----
    logic [INPUTS-1:0]                   s_awvalid, s_awready;
    logic [INPUTS-1:0][ID_WIDTH-1:0]     s_awid;
    logic [INPUTS-1:0][ADDR_WIDTH-1:0]   s_awaddr;
    logic [INPUTS-1:0][7:0]              s_awlen;
    logic [INPUTS-1:0][2:0]              s_awsize;
    logic [INPUTS-1:0][1:0]              s_awburst;
    logic [INPUTS-1:0]                   s_awlock;
    logic [INPUTS-1:0][3:0]              s_awcache;
    logic [INPUTS-1:0][2:0]              s_awprot;
    logic [INPUTS-1:0][3:0]              s_awqos;
    logic [INPUTS-1:0]                   s_wvalid, s_wready;
    logic [INPUTS-1:0][DATA_WIDTH-1:0]   s_wdata;
    logic [INPUTS-1:0][STRB_WIDTH-1:0]   s_wstrb;
    logic [INPUTS-1:0]                   s_wlast;
    logic [INPUTS-1:0]                   s_bvalid, s_bready;
    logic [INPUTS-1:0][ID_WIDTH-1:0]     s_bid;
    logic [INPUTS-1:0][1:0]              s_bresp;
    // ---- Read channel signals ----
    logic [INPUTS-1:0]                   s_arvalid, s_arready;
    logic [INPUTS-1:0][ID_WIDTH-1:0]     s_arid;
    logic [INPUTS-1:0][ADDR_WIDTH-1:0]   s_araddr;
    logic [INPUTS-1:0][7:0]              s_arlen;
    logic [INPUTS-1:0][2:0]              s_arsize;
    logic [INPUTS-1:0][1:0]              s_arburst;
    logic [INPUTS-1:0]                   s_arlock;
    logic [INPUTS-1:0][3:0]              s_arcache;
    logic [INPUTS-1:0][2:0]              s_arprot;
    logic [INPUTS-1:0][3:0]              s_arqos;
    logic [INPUTS-1:0]                   s_rvalid, s_rready;
    logic [INPUTS-1:0][ID_WIDTH-1:0]     s_rid;
    logic [INPUTS-1:0][DATA_WIDTH-1:0]   s_rdata;
    logic [INPUTS-1:0][1:0]              s_rresp;
    logic [INPUTS-1:0]                   s_rlast;
    // ---- Slave write signals ----
    logic [SLAVES-1:0]                   m_awvalid, m_awready;
    logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_awid;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0]   m_awaddr;
    logic [SLAVES-1:0][7:0]              m_awlen;
    logic [SLAVES-1:0][2:0]              m_awsize;
    logic [SLAVES-1:0][1:0]              m_awburst;
    logic [SLAVES-1:0]                   m_awlock;
    logic [SLAVES-1:0][3:0]              m_awcache;
    logic [SLAVES-1:0][2:0]              m_awprot;
    logic [SLAVES-1:0][3:0]              m_awqos;
    logic [SLAVES-1:0]                   m_wvalid, m_wready;
    logic [SLAVES-1:0][DATA_WIDTH-1:0]   m_wdata;
    logic [SLAVES-1:0][STRB_WIDTH-1:0]   m_wstrb;
    logic [SLAVES-1:0]                   m_wlast;
    logic [SLAVES-1:0]                   m_bvalid, m_bready;
    logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_bid;
    logic [SLAVES-1:0][1:0]              m_bresp;
    // ---- Slave read signals ----
    logic [SLAVES-1:0]                   m_arvalid, m_arready;
    logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_arid;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0]   m_araddr;
    logic [SLAVES-1:0][7:0]              m_arlen;
    logic [SLAVES-1:0][2:0]              m_arsize;
    logic [SLAVES-1:0][1:0]              m_arburst;
    logic [SLAVES-1:0]                   m_arlock;
    logic [SLAVES-1:0][3:0]              m_arcache;
    logic [SLAVES-1:0][2:0]              m_arprot;
    logic [SLAVES-1:0][3:0]             m_arqos;
    logic [SLAVES-1:0]                   m_rvalid, m_rready;
    logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_rid;
    logic [SLAVES-1:0][DATA_WIDTH-1:0]   m_rdata;
    logic [SLAVES-1:0][1:0]              m_rresp;
    logic [SLAVES-1:0]                   m_rlast;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0]   map_base, map_limit;

    // ---- UVM interfaces ----
    axi_write_if#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)        master_wbus[4](clk, reset_n);
    axi_write_if#(ADDR_WIDTH, DATA_WIDTH, OUTPUT_ID_WIDTH) slave_wbus[4](clk, reset_n);
    axi_read_if#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)          master_rbus[4](clk, reset_n);
    axi_read_if#(ADDR_WIDTH, DATA_WIDTH, OUTPUT_ID_WIDTH)   slave_rbus[4](clk, reset_n);
    axi_reset_if rst_if(clk);

    // reset_n driven from UVM via rst_if
    assign reset_n = rst_if.reset_n;

    // ---- DUT ----
    axi_crossbar #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (.*);

    for (genvar i = 0; i < 4; i++) begin : ports
        assign map_base[i]  = ADDR_WIDTH'(i) << 16;
        assign map_limit[i] = map_base[i] + ADDR_WIDTH'('hffff);
        // Write master side
        assign s_awvalid[i]=master_wbus[i].AWVALID; assign master_wbus[i].AWREADY=s_awready[i];
        assign s_awid[i]=master_wbus[i].AWID; assign s_awaddr[i]=master_wbus[i].AWADDR;
        assign s_awlen[i]=master_wbus[i].AWLEN; assign s_awsize[i]=master_wbus[i].AWSIZE;
        assign s_awburst[i]=master_wbus[i].AWBURST; assign s_awlock[i]=master_wbus[i].AWLOCK;
        assign s_awcache[i]=master_wbus[i].AWCACHE; assign s_awprot[i]=master_wbus[i].AWPROT;
        assign s_awqos[i]=master_wbus[i].AWQOS;
        assign s_wvalid[i]=master_wbus[i].WVALID; assign master_wbus[i].WREADY=s_wready[i];
        assign s_wdata[i]=master_wbus[i].WDATA; assign s_wstrb[i]=master_wbus[i].WSTRB;
        assign s_wlast[i]=master_wbus[i].WLAST;
        assign master_wbus[i].BVALID=s_bvalid[i]; assign s_bready[i]=master_wbus[i].BREADY;
        assign master_wbus[i].BID=s_bid[i]; assign master_wbus[i].BRESP=s_bresp[i];
        // Write slave side
        assign slave_wbus[i].AWVALID=m_awvalid[i]; assign m_awready[i]=slave_wbus[i].AWREADY;
        assign slave_wbus[i].AWID=m_awid[i]; assign slave_wbus[i].AWADDR=m_awaddr[i];
        assign slave_wbus[i].AWLEN=m_awlen[i]; assign slave_wbus[i].AWSIZE=m_awsize[i];
        assign slave_wbus[i].AWBURST=m_awburst[i]; assign slave_wbus[i].AWLOCK=m_awlock[i];
        assign slave_wbus[i].AWCACHE=m_awcache[i]; assign slave_wbus[i].AWPROT=m_awprot[i];
        assign slave_wbus[i].AWQOS=m_awqos[i];
        assign slave_wbus[i].WVALID=m_wvalid[i]; assign m_wready[i]=slave_wbus[i].WREADY;
        assign slave_wbus[i].WDATA=m_wdata[i]; assign slave_wbus[i].WSTRB=m_wstrb[i];
        assign slave_wbus[i].WLAST=m_wlast[i];
        assign m_bvalid[i]=slave_wbus[i].BVALID; assign slave_wbus[i].BREADY=m_bready[i];
        assign m_bid[i]=slave_wbus[i].BID; assign m_bresp[i]=slave_wbus[i].BRESP;
        // Read master side
        assign s_arvalid[i]=master_rbus[i].ARVALID; assign master_rbus[i].ARREADY=s_arready[i];
        assign s_arid[i]=master_rbus[i].ARID; assign s_araddr[i]=master_rbus[i].ARADDR;
        assign s_arlen[i]=master_rbus[i].ARLEN; assign s_arsize[i]=master_rbus[i].ARSIZE;
        assign s_arburst[i]=master_rbus[i].ARBURST; assign s_arlock[i]=master_rbus[i].ARLOCK;
        assign s_arcache[i]=master_rbus[i].ARCACHE; assign s_arprot[i]=master_rbus[i].ARPROT;
        assign s_arqos[i]=master_rbus[i].ARQOS;
        assign master_rbus[i].RVALID=s_rvalid[i]; assign s_rready[i]=master_rbus[i].RREADY;
        assign master_rbus[i].RID=s_rid[i]; assign master_rbus[i].RDATA=s_rdata[i];
        assign master_rbus[i].RRESP=s_rresp[i]; assign master_rbus[i].RLAST=s_rlast[i];
        // Read slave side
        assign slave_rbus[i].ARVALID=m_arvalid[i]; assign m_arready[i]=slave_rbus[i].ARREADY;
        assign slave_rbus[i].ARID=m_arid[i]; assign slave_rbus[i].ARADDR=m_araddr[i];
        assign slave_rbus[i].ARLEN=m_arlen[i]; assign slave_rbus[i].ARSIZE=m_arsize[i];
        assign slave_rbus[i].ARBURST=m_arburst[i]; assign slave_rbus[i].ARLOCK=m_arlock[i];
        assign slave_rbus[i].ARCACHE=m_arcache[i]; assign slave_rbus[i].ARPROT=m_arprot[i];
        assign slave_rbus[i].ARQOS=m_arqos[i];
        assign m_rvalid[i]=slave_rbus[i].RVALID; assign slave_rbus[i].RREADY=m_rready[i];
        assign m_rid[i]=slave_rbus[i].RID; assign m_rdata[i]=slave_rbus[i].RDATA;
        assign m_rresp[i]=slave_rbus[i].RRESP; assign m_rlast[i]=slave_rbus[i].RLAST;
        // UVM config_db
        initial begin
            uvm_config_db#(master_wvif_t)::set(null,"uvm_test_top*",$sformatf("master_wvif_%0d",i),master_wbus[i]);
            uvm_config_db#(slave_wvif_t)::set(null,"uvm_test_top*",$sformatf("slave_wvif_%0d",i),slave_wbus[i]);
            uvm_config_db#(master_rvif_t)::set(null,"uvm_test_top*",$sformatf("master_rvif_%0d",i),master_rbus[i]);
            uvm_config_db#(slave_rvif_t)::set(null,"uvm_test_top*",$sformatf("slave_rvif_%0d",i),slave_rbus[i]);
        end
    end

    initial begin
        uvm_config_db#(rst_vif_t)::set(null,"uvm_test_top*","rst_vif",rst_if);
    end

    // Initial reset: UVM test drives reset_n via rst_if from t=0
    initial begin
        rst_if.reset_n = 0;
        repeat(4) @(posedge clk); #1;
        rst_if.reset_n = 1;
    end
    initial begin run_test("crossbar_uvm7_test"); end
    initial begin
        #12000000;
        $fatal(1,"WATCHDOG: In-flight reset test did not complete");
    end
endmodule

