// Parameterized AXI4 read-only crossbar. The error endpoint is internal.
module axi_crossbar_read #(
    parameter int INPUTS       = 4,
    parameter int SLAVES       = 4,
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int ID_WIDTH     = 2,
    parameter int INPUT_LIMIT  = 2,
    parameter int OUTPUT_LIMIT = 4,
    parameter int SOURCE_WIDTH    = INPUTS > 1 ? $clog2(INPUTS) : 1,
    parameter int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH
) (
    input  logic clk,
    input  logic reset_n,
    input  logic [SLAVES-1:0][ADDR_WIDTH-1:0]  map_base,
    input  logic [SLAVES-1:0][ADDR_WIDTH-1:0]  map_limit,
    input  logic [INPUTS-1:0]                   s_arvalid,
    output logic [INPUTS-1:0]                   s_arready,
    input  logic [INPUTS-1:0][ID_WIDTH-1:0]     s_arid,
    input  logic [INPUTS-1:0][ADDR_WIDTH-1:0]   s_araddr,
    input  logic [INPUTS-1:0][7:0]              s_arlen,
    input  logic [INPUTS-1:0][2:0]              s_arsize,
    input  logic [INPUTS-1:0][1:0]              s_arburst,
    input  logic [INPUTS-1:0]                   s_arlock,
    input  logic [INPUTS-1:0][3:0]              s_arcache,
    input  logic [INPUTS-1:0][2:0]              s_arprot,
    input  logic [INPUTS-1:0][3:0]              s_arqos,
    output logic [INPUTS-1:0]                   s_rvalid,
    input  logic [INPUTS-1:0]                   s_rready,
    output logic [INPUTS-1:0][ID_WIDTH-1:0]     s_rid,
    output logic [INPUTS-1:0][DATA_WIDTH-1:0]   s_rdata,
    output logic [INPUTS-1:0][1:0]              s_rresp,
    output logic [INPUTS-1:0]                   s_rlast,
    output logic [SLAVES-1:0]                   m_arvalid,
    input  logic [SLAVES-1:0]                   m_arready,
    output logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_arid,
    output logic [SLAVES-1:0][ADDR_WIDTH-1:0]   m_araddr,
    output logic [SLAVES-1:0][7:0]              m_arlen,
    output logic [SLAVES-1:0][2:0]              m_arsize,
    output logic [SLAVES-1:0][1:0]              m_arburst,
    output logic [SLAVES-1:0]                   m_arlock,
    output logic [SLAVES-1:0][3:0]              m_arcache,
    output logic [SLAVES-1:0][2:0]              m_arprot,
    output logic [SLAVES-1:0][3:0]              m_arqos,
    input  logic [SLAVES-1:0]                   m_rvalid,
    output logic [SLAVES-1:0]                   m_rready,
    input  logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_rid,
    input  logic [SLAVES-1:0][DATA_WIDTH-1:0]   m_rdata,
    input  logic [SLAVES-1:0][1:0]              m_rresp,
    input  logic [SLAVES-1:0]                   m_rlast
);
    localparam int OUTPUTS = SLAVES + 1;

    logic [INPUTS-1:0][16:0]                  s_arattr;
    logic [OUTPUTS-1:0][16:0]                 x_arattr;
    logic [OUTPUTS-1:0]                       x_arvalid;
    logic [OUTPUTS-1:0]                       x_arready;
    logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0]  x_arid;
    logic [OUTPUTS-1:0][ADDR_WIDTH-1:0]       x_araddr;
    logic [OUTPUTS-1:0][7:0]                  x_arlen;
    logic [OUTPUTS-1:0]                       x_rvalid;
    logic [OUTPUTS-1:0]                       x_rready;
    logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0]  x_rid;
    logic [OUTPUTS-1:0][DATA_WIDTH-1:0]       x_rdata;
    logic [OUTPUTS-1:0][1:0]                  x_rresp;
    logic [OUTPUTS-1:0]                       x_rlast;
    logic [INPUTS-1:0]                        complete_valid;
    logic [INPUTS-1:0][ID_WIDTH-1:0]          complete_id;
    logic [OUTPUTS-1:0]                       release_valid;

    for (genvar i = 0; i < INPUTS; i++) begin : pack_attributes
        assign s_arattr[i] = {s_arsize[i], s_arburst[i], s_arlock[i],
                              s_arcache[i], s_arprot[i], s_arqos[i]};
    end

    for (genvar o = 0; o < SLAVES; o++) begin : physical_ports
        assign {m_arsize[o], m_arburst[o], m_arlock[o],
                m_arcache[o], m_arprot[o], m_arqos[o]} = x_arattr[o];
        assign m_arvalid[o]  = x_arvalid[o];
        assign x_arready[o]  = m_arready[o];
        assign m_arid[o]     = x_arid[o];
        assign m_araddr[o]   = x_araddr[o];
        assign m_arlen[o]    = x_arlen[o];
        assign x_rvalid[o]   = m_rvalid[o];
        assign m_rready[o]   = x_rready[o];
        assign x_rid[o]      = m_rid[o];
        assign x_rdata[o]    = m_rdata[o];
        assign x_rresp[o]    = m_rresp[o];
        assign x_rlast[o]    = m_rlast[o];
    end

    axi_read_frontend #(
        .INPUTS(INPUTS), .SLAVES(SLAVES), .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH), .INPUT_LIMIT(INPUT_LIMIT), .OUTPUT_LIMIT(OUTPUT_LIMIT)
    ) frontend (
        .clk(clk), .reset_n(reset_n),
        .map_base(map_base), .map_limit(map_limit),
        .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_arid(s_arid), .s_araddr(s_araddr),
        .s_arlen(s_arlen), .s_arattr(s_arattr),
        .m_arvalid(x_arvalid), .m_arready(x_arready),
        .m_arid(x_arid), .m_araddr(x_araddr),
        .m_arlen(x_arlen), .m_arattr(x_arattr),
        .complete_valid(complete_valid), .complete_id(complete_id),
        .release_valid(release_valid)
    );

    axi_read_data_path #(
        .INPUTS(INPUTS), .OUTPUTS(OUTPUTS), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) data_path (
        .clk(clk), .reset_n(reset_n),
        .m_rvalid(x_rvalid), .m_rready(x_rready),
        .m_rid(x_rid), .m_rdata(x_rdata),
        .m_rresp(x_rresp), .m_rlast(x_rlast),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .s_rid(s_rid), .s_rdata(s_rdata),
        .s_rresp(s_rresp), .s_rlast(s_rlast),
        .release_valid(release_valid),
        .complete_valid(complete_valid), .complete_id(complete_id)
    );

    axi_read_decerr #(
        .ID_WIDTH(OUTPUT_ID_WIDTH), .DATA_WIDTH(DATA_WIDTH), .CAPACITY(OUTPUT_LIMIT)
    ) error_endpoint (
        .clk(clk), .reset_n(reset_n),
        .arvalid(x_arvalid[SLAVES]), .arready(x_arready[SLAVES]),
        .arid(x_arid[SLAVES]), .arlen(x_arlen[SLAVES]),
        .rvalid(x_rvalid[SLAVES]), .rready(x_rready[SLAVES]),
        .rid(x_rid[SLAVES]), .rdata(x_rdata[SLAVES]),
        .rresp(x_rresp[SLAVES]), .rlast(x_rlast[SLAVES])
    );
endmodule
