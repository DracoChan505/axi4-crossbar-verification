// Parameterized AXI4 write-only crossbar. The error endpoint is internal.
module axi_crossbar_write #(
    parameter int INPUTS = 4,
    parameter int SLAVES = 4,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH = 2,
    parameter int INPUT_LIMIT = 2,
    parameter int OUTPUT_LIMIT = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8,
    parameter int SOURCE_WIDTH = INPUTS > 1 ? $clog2(INPUTS) : 1,
    parameter int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH
) (
    input logic clk,
    input logic reset_n,
    input logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_base,
    input logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_limit,
    input logic [INPUTS-1:0] s_awvalid,
    output logic [INPUTS-1:0] s_awready,
    input logic [INPUTS-1:0][ID_WIDTH-1:0] s_awid,
    input logic [INPUTS-1:0][ADDR_WIDTH-1:0] s_awaddr,
    input logic [INPUTS-1:0][8-1:0] s_awlen,
    input logic [INPUTS-1:0][3-1:0] s_awsize,
    input logic [INPUTS-1:0][2-1:0] s_awburst,
    input logic [INPUTS-1:0] s_awlock,
    input logic [INPUTS-1:0][4-1:0] s_awcache,
    input logic [INPUTS-1:0][3-1:0] s_awprot,
    input logic [INPUTS-1:0][4-1:0] s_awqos,
    input logic [INPUTS-1:0] s_wvalid,
    output logic [INPUTS-1:0] s_wready,
    input logic [INPUTS-1:0][DATA_WIDTH-1:0] s_wdata,
    input logic [INPUTS-1:0][STRB_WIDTH-1:0] s_wstrb,
    input logic [INPUTS-1:0] s_wlast,
    output logic [INPUTS-1:0] s_bvalid,
    input logic [INPUTS-1:0] s_bready,
    output logic [INPUTS-1:0][ID_WIDTH-1:0] s_bid,
    output logic [INPUTS-1:0][2-1:0] s_bresp,
    output logic [SLAVES-1:0] m_awvalid,
    input logic [SLAVES-1:0] m_awready,
    output logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_awid,
    output logic [SLAVES-1:0][ADDR_WIDTH-1:0] m_awaddr,
    output logic [SLAVES-1:0][8-1:0] m_awlen,
    output logic [SLAVES-1:0][3-1:0] m_awsize,
    output logic [SLAVES-1:0][2-1:0] m_awburst,
    output logic [SLAVES-1:0] m_awlock,
    output logic [SLAVES-1:0][4-1:0] m_awcache,
    output logic [SLAVES-1:0][3-1:0] m_awprot,
    output logic [SLAVES-1:0][4-1:0] m_awqos,
    output logic [SLAVES-1:0] m_wvalid,
    input logic [SLAVES-1:0] m_wready,
    output logic [SLAVES-1:0][DATA_WIDTH-1:0] m_wdata,
    output logic [SLAVES-1:0][STRB_WIDTH-1:0] m_wstrb,
    output logic [SLAVES-1:0] m_wlast,
    input logic [SLAVES-1:0] m_bvalid,
    output logic [SLAVES-1:0] m_bready,
    input logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_bid,
    input logic [SLAVES-1:0][2-1:0] m_bresp
);
    localparam int OUTPUTS = SLAVES + 1;
    localparam int TARGET_WIDTH = $clog2(OUTPUTS);
    logic [INPUTS-1:0][16:0] s_awattr;
    logic [OUTPUTS-1:0][16:0] x_awattr;
    logic [INPUTS-1:0] complete_valid;
    logic [INPUTS-1:0][ID_WIDTH-1:0] complete_id;
    logic [OUTPUTS-1:0] release_valid;
    logic [INPUTS-1:0] w_target_valid;
    logic [INPUTS-1:0] w_target_ready;
    logic [INPUTS-1:0][TARGET_WIDTH-1:0] w_target;
    logic [INPUTS-1:0][7:0] w_target_len;
    logic [OUTPUTS-1:0] w_source_valid;
    logic [OUTPUTS-1:0] w_source_ready;
    logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] w_source;
    logic [OUTPUTS-1:0][7:0] w_source_len;
    logic [OUTPUTS-1:0] x_awvalid;
    logic [OUTPUTS-1:0] x_awready;
    logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] x_awid;
    logic [OUTPUTS-1:0][ADDR_WIDTH-1:0] x_awaddr;
    logic [OUTPUTS-1:0][8-1:0] x_awlen;
    logic [OUTPUTS-1:0] x_wvalid;
    logic [OUTPUTS-1:0] x_wready;
    logic [OUTPUTS-1:0][DATA_WIDTH-1:0] x_wdata;
    logic [OUTPUTS-1:0][STRB_WIDTH-1:0] x_wstrb;
    logic [OUTPUTS-1:0] x_wlast;
    logic [OUTPUTS-1:0] x_bvalid;
    logic [OUTPUTS-1:0] x_bready;
    logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] x_bid;
    logic [OUTPUTS-1:0][2-1:0] x_bresp;

    for (genvar i = 0; i < INPUTS; i++) begin : pack_attributes
        assign s_awattr[i] = {s_awsize[i], s_awburst[i], s_awlock[i],
                              s_awcache[i], s_awprot[i], s_awqos[i]};
    end
    for (genvar o = 0; o < SLAVES; o++) begin : physical_ports
        assign {m_awsize[o], m_awburst[o], m_awlock[o], m_awcache[o], m_awprot[o], m_awqos[o]} = x_awattr[o];
        assign m_awvalid[o] = x_awvalid[o];
        assign x_awready[o] = m_awready[o];
        assign m_awid[o] = x_awid[o];
        assign m_awaddr[o] = x_awaddr[o];
        assign m_awlen[o] = x_awlen[o];
        assign m_wvalid[o] = x_wvalid[o];
        assign x_wready[o] = m_wready[o];
        assign m_wdata[o] = x_wdata[o];
        assign m_wstrb[o] = x_wstrb[o];
        assign m_wlast[o] = x_wlast[o];
        assign x_bvalid[o] = m_bvalid[o];
        assign m_bready[o] = x_bready[o];
        assign x_bid[o] = m_bid[o];
        assign x_bresp[o] = m_bresp[o];
    end

    axi_write_frontend #(
        .INPUTS(INPUTS),
        .SLAVES(SLAVES),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .INPUT_LIMIT(INPUT_LIMIT),
        .OUTPUT_LIMIT(OUTPUT_LIMIT)
    ) frontend (
        .clk(clk),
        .reset_n(reset_n),
        .map_base(map_base),
        .map_limit(map_limit),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_awid(s_awid),
        .s_awaddr(s_awaddr),
        .s_awlen(s_awlen),
        .s_awattr(s_awattr),
        .m_awvalid(x_awvalid),
        .m_awready(x_awready),
        .m_awid(x_awid),
        .m_awaddr(x_awaddr),
        .m_awlen(x_awlen),
        .m_awattr(x_awattr),
        .complete_valid(complete_valid),
        .complete_id(complete_id),
        .release_valid(release_valid),
        .w_target_valid(w_target_valid),
        .w_target_ready(w_target_ready),
        .w_target(w_target),
        .w_target_len(w_target_len),
        .w_source_valid(w_source_valid),
        .w_source_ready(w_source_ready),
        .w_source(w_source),
        .w_source_len(w_source_len)
    );

    axi_write_data_path #(
        .INPUTS(INPUTS),
        .OUTPUTS(OUTPUTS),
        .DATA_WIDTH(DATA_WIDTH)
    ) data_path (
        .clk(clk),
        .reset_n(reset_n),
        .s_wvalid(s_wvalid),
        .s_wready(s_wready),
        .s_wdata(s_wdata),
        .s_wstrb(s_wstrb),
        .s_wlast(s_wlast),
        .m_wvalid(x_wvalid),
        .m_wready(x_wready),
        .m_wdata(x_wdata),
        .m_wstrb(x_wstrb),
        .m_wlast(x_wlast),
        .w_target_valid(w_target_valid),
        .w_target_ready(w_target_ready),
        .w_target(w_target),
        .w_target_len(w_target_len),
        .w_source_valid(w_source_valid),
        .w_source_ready(w_source_ready),
        .w_source(w_source),
        .w_source_len(w_source_len)
    );

    axi_write_response_path #(
        .INPUTS(INPUTS),
        .OUTPUTS(OUTPUTS),
        .ID_WIDTH(ID_WIDTH)
    ) response_path (
        .clk(clk),
        .reset_n(reset_n),
        .m_bvalid(x_bvalid),
        .m_bready(x_bready),
        .m_bid(x_bid),
        .m_bresp(x_bresp),
        .s_bvalid(s_bvalid),
        .s_bready(s_bready),
        .s_bid(s_bid),
        .s_bresp(s_bresp),
        .complete_valid(complete_valid),
        .complete_id(complete_id),
        .release_valid(release_valid)
    );

    axi_write_decerr #(
        .ID_WIDTH(OUTPUT_ID_WIDTH),
        .CAPACITY(OUTPUT_LIMIT)
    ) error_endpoint (
        .clk(clk),
        .reset_n(reset_n),
        .awvalid(x_awvalid[SLAVES]),
        .awready(x_awready[SLAVES]),
        .awid(x_awid[SLAVES]),
        .awlen(x_awlen[SLAVES]),
        .wvalid(x_wvalid[SLAVES]),
        .wready(x_wready[SLAVES]),
        .wlast(x_wlast[SLAVES]),
        .bvalid(x_bvalid[SLAVES]),
        .bready(x_bready[SLAVES]),
        .bid(x_bid[SLAVES]),
        .bresp(x_bresp[SLAVES])
    );
endmodule
