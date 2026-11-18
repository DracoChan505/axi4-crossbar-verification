// Buffer each downstream B stream, then arbitrate into registered upstream B ports.
module axi_write_response_path #(
    parameter int INPUTS = 4,
    parameter int OUTPUTS = 5,
    parameter int ID_WIDTH = 2,
    parameter int SOURCE_WIDTH = INPUTS > 1 ? $clog2(INPUTS) : 1,
    parameter int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH,
    parameter int RESPONSE_DEPTH = 2,
    parameter int SELECT_WIDTH = OUTPUTS > 1 ? $clog2(OUTPUTS) : 1
) (
    input logic clk,
    input logic reset_n,
    input logic [OUTPUTS-1:0] m_bvalid,
    output logic [OUTPUTS-1:0] m_bready,
    input logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] m_bid,
    input logic [OUTPUTS-1:0][1:0] m_bresp,
    output logic [INPUTS-1:0] s_bvalid,
    input logic [INPUTS-1:0] s_bready,
    output logic [INPUTS-1:0][ID_WIDTH-1:0] s_bid,
    output logic [INPUTS-1:0][1:0] s_bresp,
    output logic [OUTPUTS-1:0] release_valid,
    output logic [INPUTS-1:0] complete_valid,
    output logic [INPUTS-1:0][ID_WIDTH-1:0] complete_id
);
    logic [OUTPUTS-1:0] head_valid;
    logic [OUTPUTS-1:0] head_pop;
    logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] head_id;
    logic [OUTPUTS-1:0][1:0] head_resp;
    logic [INPUTS-1:0] full;
    logic [INPUTS-1:0] capture;
    logic [INPUTS-1:0][SELECT_WIDTH-1:0] selected;

    initial begin
        assert (INPUTS > 0 && OUTPUTS > 0 && ID_WIDTH > 0 && RESPONSE_DEPTH > 0 &&
                OUTPUT_ID_WIDTH == ID_WIDTH + SOURCE_WIDTH)
            else $fatal(1, "BRESP_PARAMETERS");
    end

    for (genvar o = 0; o < OUTPUTS; o++) begin : egress
        axi_record_fifo #(
            .WIDTH(OUTPUT_ID_WIDTH + 2),
            .DEPTH(RESPONSE_DEPTH)
        ) response_buffer (
            .clk(clk),
            .reset_n(reset_n),
            .push_valid(m_bvalid[o]),
            .push_ready(m_bready[o]),
            .push_data({m_bid[o], m_bresp[o]}),
            .pop_valid(head_valid[o]),
            .pop_ready(head_pop[o]),
            .pop_data({head_id[o], head_resp[o]}),
            .count()
        );
        assign release_valid[o] = m_bvalid[o] && m_bready[o];
        assert property (@(posedge clk) disable iff (!reset_n)
            m_bvalid[o] |-> int'(m_bid[o][OUTPUT_ID_WIDTH-1:ID_WIDTH]) < INPUTS)
            else $fatal(1, "BRESP_INVALID_SOURCE");
    end

    always_comb begin
        head_pop = '0;
        for (int i = 0; i < INPUTS; i++) begin
            if (capture[i]) begin
                head_pop[selected[i]] = 1;
            end
        end
    end

    for (genvar i = 0; i < INPUTS; i++) begin : ingress
        logic [OUTPUTS-1:0] request;
        logic selected_valid;
        for (genvar o = 0; o < OUTPUTS; o++) begin : contenders
            assign request[o] = head_valid[o] &&
                                head_id[o][OUTPUT_ID_WIDTH-1:ID_WIDTH] == SOURCE_WIDTH'(i);
        end
        axi_rr_arbiter #(.PORTS(OUTPUTS)) arbiter (
            .clk(clk),
            .reset_n(reset_n),
            .request(request),
            .grant_ready(!full[i]),
            .grant_valid(selected_valid),
            .grant_index(selected[i]),
            .grant_onehot(),
            .request_ready()
        );
        assign capture[i] = selected_valid && !full[i];
        assign s_bvalid[i] = reset_n && full[i];
        assign complete_valid[i] = s_bvalid[i] && s_bready[i];
        assign complete_id[i] = s_bid[i];
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                full[i] <= 0;
                s_bid[i] <= '0;
                s_bresp[i] <= '0;
            end
            else if (capture[i]) begin
                full[i] <= 1;
                s_bid[i] <= head_id[selected[i]][ID_WIDTH-1:0];
                s_bresp[i] <= head_resp[selected[i]];
            end
            else if (complete_valid[i]) begin
                full[i] <= 0;
            end
        end
        assert property (@(posedge clk) disable iff (!reset_n)
            s_bvalid[i] && !s_bready[i] |=> s_bvalid[i] && $stable({s_bid[i], s_bresp[i]}))
            else $fatal(1, "BRESP_UNSTABLE");
    end
endmodule
