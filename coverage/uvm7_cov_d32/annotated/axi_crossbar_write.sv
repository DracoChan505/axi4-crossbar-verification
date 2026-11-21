//      // verilator_coverage annotation
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
 003318     input logic clk,
 000036     input logic reset_n,
~000018     input logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_base,
~000018     input logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_limit,
 000149     input logic [INPUTS-1:0] s_awvalid,
 000184     output logic [INPUTS-1:0] s_awready,
 000090     input logic [INPUTS-1:0][ID_WIDTH-1:0] s_awid,
~000090     input logic [INPUTS-1:0][ADDR_WIDTH-1:0] s_awaddr,
~000022     input logic [INPUTS-1:0][8-1:0] s_awlen,
~000018     input logic [INPUTS-1:0][3-1:0] s_awsize,
~000018     input logic [INPUTS-1:0][2-1:0] s_awburst,
%000000     input logic [INPUTS-1:0] s_awlock,
~000018     input logic [INPUTS-1:0][4-1:0] s_awcache,
~000018     input logic [INPUTS-1:0][3-1:0] s_awprot,
~000021     input logic [INPUTS-1:0][4-1:0] s_awqos,
 000147     input logic [INPUTS-1:0] s_wvalid,
 000180     output logic [INPUTS-1:0] s_wready,
~000097     input logic [INPUTS-1:0][DATA_WIDTH-1:0] s_wdata,
~000028     input logic [INPUTS-1:0][STRB_WIDTH-1:0] s_wstrb,
 000034     input logic [INPUTS-1:0] s_wlast,
 000156     output logic [INPUTS-1:0] s_bvalid,
 000292     input logic [INPUTS-1:0] s_bready,
 000075     output logic [INPUTS-1:0][ID_WIDTH-1:0] s_bid,
%000000     output logic [INPUTS-1:0][2-1:0] s_bresp,
 000183     output logic [SLAVES-1:0] m_awvalid,
 001024     input logic [SLAVES-1:0] m_awready,
~000087     output logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_awid,
~000087     output logic [SLAVES-1:0][ADDR_WIDTH-1:0] m_awaddr,
~000015     output logic [SLAVES-1:0][8-1:0] m_awlen,
~000033     output logic [SLAVES-1:0][3-1:0] m_awsize,
~000033     output logic [SLAVES-1:0][2-1:0] m_awburst,
%000000     output logic [SLAVES-1:0] m_awlock,
~000033     output logic [SLAVES-1:0][4-1:0] m_awcache,
~000033     output logic [SLAVES-1:0][3-1:0] m_awprot,
~000015     output logic [SLAVES-1:0][4-1:0] m_awqos,
 000142     output logic [SLAVES-1:0] m_wvalid,
 000195     input logic [SLAVES-1:0] m_wready,
 000128     output logic [SLAVES-1:0][DATA_WIDTH-1:0] m_wdata,
 000142     output logic [SLAVES-1:0][STRB_WIDTH-1:0] m_wstrb,
 000138     output logic [SLAVES-1:0] m_wlast,
 000153     input logic [SLAVES-1:0] m_bvalid,
 000046     output logic [SLAVES-1:0] m_bready,
~000075     input logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_bid,
%000000     input logic [SLAVES-1:0][2-1:0] m_bresp
        );
            localparam int OUTPUTS = SLAVES + 1;
            localparam int TARGET_WIDTH = $clog2(OUTPUTS);
~000021     logic [INPUTS-1:0][16:0] s_awattr;
~000033     logic [OUTPUTS-1:0][16:0] x_awattr;
 000173     logic [INPUTS-1:0] complete_valid;
 000075     logic [INPUTS-1:0][ID_WIDTH-1:0] complete_id;
~000152     logic [OUTPUTS-1:0] release_valid;
 000116     logic [INPUTS-1:0] w_target_valid;
 000202     logic [INPUTS-1:0] w_target_ready;
~000082     logic [INPUTS-1:0][TARGET_WIDTH-1:0] w_target;
~000021     logic [INPUTS-1:0][7:0] w_target_len;
~000127     logic [OUTPUTS-1:0] w_source_valid;
~000178     logic [OUTPUTS-1:0] w_source_ready;
~000083     logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] w_source;
~000014     logic [OUTPUTS-1:0][7:0] w_source_len;
~000183     logic [OUTPUTS-1:0] x_awvalid;
 001024     logic [OUTPUTS-1:0] x_awready;
~000087     logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] x_awid;
~000087     logic [OUTPUTS-1:0][ADDR_WIDTH-1:0] x_awaddr;
~000015     logic [OUTPUTS-1:0][8-1:0] x_awlen;
~000142     logic [OUTPUTS-1:0] x_wvalid;
~000195     logic [OUTPUTS-1:0] x_wready;
~000128     logic [OUTPUTS-1:0][DATA_WIDTH-1:0] x_wdata;
~000142     logic [OUTPUTS-1:0][STRB_WIDTH-1:0] x_wstrb;
~000138     logic [OUTPUTS-1:0] x_wlast;
~000153     logic [OUTPUTS-1:0] x_bvalid;
 000046     logic [OUTPUTS-1:0] x_bready;
~000075     logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] x_bid;
~000018     logic [OUTPUTS-1:0][2-1:0] x_bresp;
        
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
        
