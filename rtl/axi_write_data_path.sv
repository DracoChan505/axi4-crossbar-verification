// Two beats per input. Route records remain owned until downstream WLAST fires.
module axi_write_data_path #(
    parameter int INPUTS = 4,
    parameter int OUTPUTS = 5,
    parameter int DATA_WIDTH = 32,
    parameter int STRB_WIDTH = DATA_WIDTH / 8,
    parameter int SOURCE_WIDTH = INPUTS > 1 ? $clog2(INPUTS) : 1,
    parameter int TARGET_WIDTH = OUTPUTS > 1 ? $clog2(OUTPUTS) : 1
) (
    input logic clk,
    input logic reset_n,
    input logic [INPUTS-1:0] s_wvalid,
    output logic [INPUTS-1:0] s_wready,
    input logic [INPUTS-1:0][DATA_WIDTH-1:0] s_wdata,
    input logic [INPUTS-1:0][STRB_WIDTH-1:0] s_wstrb,
    input logic [INPUTS-1:0] s_wlast,
    output logic [OUTPUTS-1:0] m_wvalid,
    input logic [OUTPUTS-1:0] m_wready,
    output logic [OUTPUTS-1:0][DATA_WIDTH-1:0] m_wdata,
    output logic [OUTPUTS-1:0][STRB_WIDTH-1:0] m_wstrb,
    output logic [OUTPUTS-1:0] m_wlast,
    input logic [INPUTS-1:0] w_target_valid,
    output logic [INPUTS-1:0] w_target_ready,
    input logic [INPUTS-1:0][TARGET_WIDTH-1:0] w_target,
    input logic [INPUTS-1:0][7:0] w_target_len,
    input logic [OUTPUTS-1:0] w_source_valid,
    output logic [OUTPUTS-1:0] w_source_ready,
    input logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] w_source,
    input logic [OUTPUTS-1:0][7:0] w_source_len
);
    localparam int BEAT_WIDTH = DATA_WIDTH + STRB_WIDTH + 1;
    logic [INPUTS-1:0] buffer_valid;
    logic [INPUTS-1:0] buffer_ready;
    logic [INPUTS-1:0] buffer_space;
    logic [INPUTS-1:0][BEAT_WIDTH-1:0] buffer_data;
    logic [INPUTS-1:0][8:0] accepted_beats;
    logic [OUTPUTS-1:0][7:0] sent_index;

    initial begin
        assert (INPUTS > 0 && OUTPUTS > 0 && DATA_WIDTH >= 8 &&
                DATA_WIDTH % 8 == 0 && STRB_WIDTH == DATA_WIDTH / 8)
            else $fatal(1, "WDATA_PARAMETERS");
    end

    for (genvar i = 0; i < INPUTS; i++) begin : ingress
        assign s_wready[i] = buffer_space[i] && w_target_valid[i] &&
                            accepted_beats[i] < ({1'b0, w_target_len[i]} + 9'd1);
        axi_record_fifo #(.WIDTH(BEAT_WIDTH), .DEPTH(2)) data_buffer (
            .clk(clk),
            .reset_n(reset_n),
            .push_valid(s_wvalid[i] && s_wready[i]),
            .push_ready(buffer_space[i]),
            .push_data({s_wdata[i], s_wstrb[i], s_wlast[i]}),
            .pop_valid(buffer_valid[i]),
            .pop_ready(buffer_ready[i]),
            .pop_data(buffer_data[i]),
            .count()
        );
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                accepted_beats[i] <= '0;
            end
            else if (w_target_ready[i]) begin
                accepted_beats[i] <= '0;
            end
            else if (s_wvalid[i] && s_wready[i]) begin
                accepted_beats[i] <= accepted_beats[i] + 9'd1;
            end
        end
        assert property (@(posedge clk) disable iff (!reset_n)
            s_wvalid[i] && s_wready[i] |->
                s_wlast[i] == (accepted_beats[i] == {1'b0, w_target_len[i]}))
            else $fatal(1, "WDATA_INPUT_LAST");
        assert property (@(posedge clk) disable iff (!reset_n)
            w_target_ready[i] |-> accepted_beats[i] == ({1'b0, w_target_len[i]} + 9'd1))
            else $fatal(1, "WDATA_EARLY_RELEASE");
    end

    always_comb begin
        m_wvalid = '0;
        m_wdata = '0;
        m_wstrb = '0;
        m_wlast = '0;
        w_source_ready = '0;
        w_target_ready = '0;
        buffer_ready = '0;
        // Match both queue heads; no new arbitration is needed on W.
        for (int o = 0; o < OUTPUTS; o++) begin
            for (int i = 0; i < INPUTS; i++) begin
                if (reset_n && w_source_valid[o] && w_target_valid[i] &&
                    w_source[o] == SOURCE_WIDTH'(i) && w_target[i] == TARGET_WIDTH'(o)) begin
                    m_wvalid[o] = buffer_valid[i];
                    {m_wdata[o], m_wstrb[o], m_wlast[o]} = buffer_data[i];
                    buffer_ready[i] = m_wready[o] && buffer_valid[i];
                    if (m_wvalid[o] && m_wready[o] && m_wlast[o]) begin
                        w_source_ready[o] = 1;
                        w_target_ready[i] = 1;
                    end
                end
            end
        end
    end

    for (genvar o = 0; o < OUTPUTS; o++) begin : egress
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                sent_index[o] <= '0;
            end
            else if (m_wvalid[o] && m_wready[o]) begin
                if (m_wlast[o]) begin
                    sent_index[o] <= '0;
                end
                else begin
                    sent_index[o] <= sent_index[o] + 1'b1;
                end
            end
        end
        assert property (@(posedge clk) disable iff (!reset_n)
            m_wvalid[o] |-> m_wlast[o] == (sent_index[o] == w_source_len[o]))
            else $fatal(1, "WDATA_OUTPUT_LAST");
        assert property (@(posedge clk) disable iff (!reset_n)
            m_wvalid[o] && !m_wready[o] |=> m_wvalid[o] &&
                $stable({m_wdata[o], m_wstrb[o], m_wlast[o]}))
            else $fatal(1, "WDATA_UNSTABLE");
    end
endmodule
