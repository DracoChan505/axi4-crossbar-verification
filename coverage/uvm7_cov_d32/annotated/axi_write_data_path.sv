//      // verilator_coverage annotation
        // Two beats per input. Route records remain owned until downstream WLAST fires.
        module axi_write_data_path #(
            parameter int INPUTS = 4,
            parameter int OUTPUTS = 5,
            parameter int DATA_WIDTH = 32,
            parameter int STRB_WIDTH = DATA_WIDTH / 8,
            parameter int SOURCE_WIDTH = INPUTS > 1 ? $clog2(INPUTS) : 1,
            parameter int TARGET_WIDTH = OUTPUTS > 1 ? $clog2(OUTPUTS) : 1
        ) (
 003318     input logic clk,
 000036     input logic reset_n,
 000147     input logic [INPUTS-1:0] s_wvalid,
 000180     output logic [INPUTS-1:0] s_wready,
~000097     input logic [INPUTS-1:0][DATA_WIDTH-1:0] s_wdata,
~000028     input logic [INPUTS-1:0][STRB_WIDTH-1:0] s_wstrb,
 000034     input logic [INPUTS-1:0] s_wlast,
~000142     output logic [OUTPUTS-1:0] m_wvalid,
~000195     input logic [OUTPUTS-1:0] m_wready,
~000128     output logic [OUTPUTS-1:0][DATA_WIDTH-1:0] m_wdata,
~000142     output logic [OUTPUTS-1:0][STRB_WIDTH-1:0] m_wstrb,
~000138     output logic [OUTPUTS-1:0] m_wlast,
 000116     input logic [INPUTS-1:0] w_target_valid,
 000202     output logic [INPUTS-1:0] w_target_ready,
~000082     input logic [INPUTS-1:0][TARGET_WIDTH-1:0] w_target,
~000021     input logic [INPUTS-1:0][7:0] w_target_len,
~000127     input logic [OUTPUTS-1:0] w_source_valid,
~000178     output logic [OUTPUTS-1:0] w_source_ready,
~000083     input logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] w_source,
~000014     input logic [OUTPUTS-1:0][7:0] w_source_len
        );
            localparam int BEAT_WIDTH = DATA_WIDTH + STRB_WIDTH + 1;
 000181     logic [INPUTS-1:0] buffer_valid;
 000211     logic [INPUTS-1:0] buffer_ready;
 000054     logic [INPUTS-1:0] buffer_space;
 000178     logic [INPUTS-1:0][BEAT_WIDTH-1:0] buffer_data;
~000183     logic [INPUTS-1:0][8:0] accepted_beats;
~000022     logic [OUTPUTS-1:0][7:0] sent_index;
        
            initial begin
                assert (INPUTS > 0 && OUTPUTS > 0 && DATA_WIDTH >= 8 &&
~000018                 DATA_WIDTH % 8 == 0 && STRB_WIDTH == DATA_WIDTH / 8)
                    else $fatal(1, "WDATA_PARAMETERS");
            end
        
 000788     for (genvar i = 0; i < INPUTS; i++) begin : ingress
 024147         assign s_wready[i] = buffer_space[i] && w_target_valid[i] &&
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
 013344         always_ff @(posedge clk or negedge reset_n) begin
 012696             if (!reset_n) begin
 000648                 accepted_beats[i] <= '0;
                    end
 000610             else if (w_target_ready[i]) begin
 000610                 accepted_beats[i] <= '0;
                    end
 011298             else if (s_wvalid[i] && s_wready[i]) begin
 000788                 accepted_beats[i] <= accepted_beats[i] + 9'd1;
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
        
 033881     always_comb begin
 033881         m_wvalid = '0;
 033881         m_wdata = '0;
 033881         m_wstrb = '0;
 033881         m_wlast = '0;
 033881         w_source_ready = '0;
 033881         w_target_ready = '0;
 033881         buffer_ready = '0;
                // Match both queue heads; no new arbitration is needed on W.
 169405         for (int o = 0; o < OUTPUTS; o++) begin
 677620             for (int i = 0; i < INPUTS; i++) begin
 657659                 if (reset_n && w_source_valid[o] && w_target_valid[i] &&
 592492                     w_source[o] == SOURCE_WIDTH'(i) && w_target[i] == TARGET_WIDTH'(o)) begin
 019961                     m_wvalid[o] = buffer_valid[i];
 019961                     {m_wdata[o], m_wstrb[o], m_wlast[o]} = buffer_data[i];
 019961                     buffer_ready[i] = m_wready[o] && buffer_valid[i];
 014562                     if (m_wvalid[o] && m_wready[o] && m_wlast[o]) begin
 005399                         w_source_ready[o] = 1;
 005399                         w_target_ready[i] = 1;
                            end
                        end
                    end
                end
            end
        
 000810     for (genvar o = 0; o < OUTPUTS; o++) begin : egress
 016680         always_ff @(posedge clk or negedge reset_n) begin
 015870             if (!reset_n) begin
 000810                 sent_index[o] <= '0;
                    end
~015184             else if (m_wvalid[o] && m_wready[o]) begin
 000610                 if (m_wlast[o]) begin
 000610                     sent_index[o] <= '0;
                        end
 000076                 else begin
 000076                     sent_index[o] <= sent_index[o] + 1'b1;
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
        
