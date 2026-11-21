//      // verilator_coverage annotation
        // Parameterized AXI4 five-channel memory-mapped crossbar (AW/W/B/AR/R).
        module axi_crossbar #(
            parameter int INPUTS       = 4,
            parameter int SLAVES       = 4,
            parameter int ADDR_WIDTH   = 32,
            parameter int DATA_WIDTH   = 32,
            parameter int ID_WIDTH     = 2,
            parameter int INPUT_LIMIT  = 2,
            parameter int OUTPUT_LIMIT = 4,
            parameter int STRB_WIDTH      = DATA_WIDTH / 8,
            parameter int SOURCE_WIDTH    = INPUTS > 1 ? $clog2(INPUTS) : 1,
            parameter int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH
        ) (
 003318     input  logic clk,
 000036     input  logic reset_n,
~000018     input  logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_base,
~000018     input  logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_limit,
            // Write address channel
 000149     input  logic [INPUTS-1:0]                  s_awvalid,
 000184     output logic [INPUTS-1:0]                  s_awready,
 000090     input  logic [INPUTS-1:0][ID_WIDTH-1:0]    s_awid,
~000090     input  logic [INPUTS-1:0][ADDR_WIDTH-1:0]  s_awaddr,
~000022     input  logic [INPUTS-1:0][7:0]             s_awlen,
~000018     input  logic [INPUTS-1:0][2:0]             s_awsize,
~000018     input  logic [INPUTS-1:0][1:0]             s_awburst,
%000000     input  logic [INPUTS-1:0]                  s_awlock,
~000018     input  logic [INPUTS-1:0][3:0]             s_awcache,
~000018     input  logic [INPUTS-1:0][2:0]             s_awprot,
~000021     input  logic [INPUTS-1:0][3:0]             s_awqos,
            // Write data channel
 000147     input  logic [INPUTS-1:0]                  s_wvalid,
 000180     output logic [INPUTS-1:0]                  s_wready,
~000097     input  logic [INPUTS-1:0][DATA_WIDTH-1:0]  s_wdata,
~000028     input  logic [INPUTS-1:0][STRB_WIDTH-1:0]  s_wstrb,
 000034     input  logic [INPUTS-1:0]                  s_wlast,
            // Write response channel
 000156     output logic [INPUTS-1:0]                  s_bvalid,
 000292     input  logic [INPUTS-1:0]                  s_bready,
 000075     output logic [INPUTS-1:0][ID_WIDTH-1:0]    s_bid,
%000000     output logic [INPUTS-1:0][1:0]             s_bresp,
            // Read address channel
 000141     input  logic [INPUTS-1:0]                  s_arvalid,
 000183     output logic [INPUTS-1:0]                  s_arready,
 000093     input  logic [INPUTS-1:0][ID_WIDTH-1:0]    s_arid,
~000093     input  logic [INPUTS-1:0][ADDR_WIDTH-1:0]  s_araddr,
~000024     input  logic [INPUTS-1:0][7:0]             s_arlen,
~000018     input  logic [INPUTS-1:0][2:0]             s_arsize,
~000018     input  logic [INPUTS-1:0][1:0]             s_arburst,
%000000     input  logic [INPUTS-1:0]                  s_arlock,
~000018     input  logic [INPUTS-1:0][3:0]             s_arcache,
~000018     input  logic [INPUTS-1:0][2:0]             s_arprot,
%000000     input  logic [INPUTS-1:0][3:0]             s_arqos,
            // Read data channel
 000179     output logic [INPUTS-1:0]                  s_rvalid,
 000175     input  logic [INPUTS-1:0]                  s_rready,
 000073     output logic [INPUTS-1:0][ID_WIDTH-1:0]    s_rid,
~000077     output logic [INPUTS-1:0][DATA_WIDTH-1:0]  s_rdata,
%000000     output logic [INPUTS-1:0][1:0]             s_rresp,
~000029     output logic [INPUTS-1:0]                  s_rlast,
            // Slave write address channel
 000183     output logic [SLAVES-1:0]                  m_awvalid,
 001024     input  logic [SLAVES-1:0]                  m_awready,
~000087     output logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_awid,
~000087     output logic [SLAVES-1:0][ADDR_WIDTH-1:0]  m_awaddr,
~000015     output logic [SLAVES-1:0][7:0]             m_awlen,
~000033     output logic [SLAVES-1:0][2:0]             m_awsize,
~000033     output logic [SLAVES-1:0][1:0]             m_awburst,
%000000     output logic [SLAVES-1:0]                  m_awlock,
~000033     output logic [SLAVES-1:0][3:0]             m_awcache,
~000033     output logic [SLAVES-1:0][2:0]             m_awprot,
~000015     output logic [SLAVES-1:0][3:0]             m_awqos,
            // Slave write data channel
 000142     output logic [SLAVES-1:0]                  m_wvalid,
 000195     input  logic [SLAVES-1:0]                  m_wready,
 000128     output logic [SLAVES-1:0][DATA_WIDTH-1:0]  m_wdata,
 000142     output logic [SLAVES-1:0][STRB_WIDTH-1:0]  m_wstrb,
 000138     output logic [SLAVES-1:0]                  m_wlast,
            // Slave write response channel
 000153     input  logic [SLAVES-1:0]                  m_bvalid,
 000046     output logic [SLAVES-1:0]                  m_bready,
~000075     input  logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_bid,
%000000     input  logic [SLAVES-1:0][1:0]             m_bresp,
            // Slave read address channel
 000194     output logic [SLAVES-1:0]                  m_arvalid,
 000631     input  logic [SLAVES-1:0]                  m_arready,
~000092     output logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_arid,
~000092     output logic [SLAVES-1:0][ADDR_WIDTH-1:0]  m_araddr,
~000018     output logic [SLAVES-1:0][7:0]             m_arlen,
~000036     output logic [SLAVES-1:0][2:0]             m_arsize,
~000036     output logic [SLAVES-1:0][1:0]             m_arburst,
%000000     output logic [SLAVES-1:0]                  m_arlock,
~000036     output logic [SLAVES-1:0][3:0]             m_arcache,
~000036     output logic [SLAVES-1:0][2:0]             m_arprot,
%000000     output logic [SLAVES-1:0][3:0]             m_arqos,
            // Slave read data channel
 000151     input  logic [SLAVES-1:0]                  m_rvalid,
 000074     output logic [SLAVES-1:0]                  m_rready,
~000151     input  logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_rid,
~000151     input  logic [SLAVES-1:0][DATA_WIDTH-1:0]  m_rdata,
%000000     input  logic [SLAVES-1:0][1:0]             m_rresp,
 000159     input  logic [SLAVES-1:0]                  m_rlast
        );
            axi_crossbar_write #(
                .INPUTS(INPUTS), .SLAVES(SLAVES), .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
                .INPUT_LIMIT(INPUT_LIMIT), .OUTPUT_LIMIT(OUTPUT_LIMIT)
            ) write_path (
                .clk(clk), .reset_n(reset_n),
                .map_base(map_base), .map_limit(map_limit),
                .s_awvalid(s_awvalid), .s_awready(s_awready),
                .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen),
                .s_awsize(s_awsize), .s_awburst(s_awburst), .s_awlock(s_awlock),
                .s_awcache(s_awcache), .s_awprot(s_awprot), .s_awqos(s_awqos),
                .s_wvalid(s_wvalid), .s_wready(s_wready),
                .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
                .s_bvalid(s_bvalid), .s_bready(s_bready),
                .s_bid(s_bid), .s_bresp(s_bresp),
                .m_awvalid(m_awvalid), .m_awready(m_awready),
                .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
                .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awlock(m_awlock),
                .m_awcache(m_awcache), .m_awprot(m_awprot), .m_awqos(m_awqos),
                .m_wvalid(m_wvalid), .m_wready(m_wready),
                .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
                .m_bvalid(m_bvalid), .m_bready(m_bready),
                .m_bid(m_bid), .m_bresp(m_bresp)
            );
        
            axi_crossbar_read #(
                .INPUTS(INPUTS), .SLAVES(SLAVES), .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
                .INPUT_LIMIT(INPUT_LIMIT), .OUTPUT_LIMIT(OUTPUT_LIMIT)
            ) read_path (
                .clk(clk), .reset_n(reset_n),
                .map_base(map_base), .map_limit(map_limit),
                .s_arvalid(s_arvalid), .s_arready(s_arready),
                .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
                .s_arsize(s_arsize), .s_arburst(s_arburst), .s_arlock(s_arlock),
                .s_arcache(s_arcache), .s_arprot(s_arprot), .s_arqos(s_arqos),
                .s_rvalid(s_rvalid), .s_rready(s_rready),
                .s_rid(s_rid), .s_rdata(s_rdata),
                .s_rresp(s_rresp), .s_rlast(s_rlast),
                .m_arvalid(m_arvalid), .m_arready(m_arready),
                .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
                .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arlock(m_arlock),
                .m_arcache(m_arcache), .m_arprot(m_arprot), .m_arqos(m_arqos),
                .m_rvalid(m_rvalid), .m_rready(m_rready),
                .m_rid(m_rid), .m_rdata(m_rdata),
                .m_rresp(m_rresp), .m_rlast(m_rlast)
            );
        endmodule
        
