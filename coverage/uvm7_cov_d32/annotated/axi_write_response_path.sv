//      // verilator_coverage annotation
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
 003318     input logic clk,
 000036     input logic reset_n,
~000153     input logic [OUTPUTS-1:0] m_bvalid,
 000046     output logic [OUTPUTS-1:0] m_bready,
~000075     input logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] m_bid,
~000018     input logic [OUTPUTS-1:0][1:0] m_bresp,
 000156     output logic [INPUTS-1:0] s_bvalid,
 000292     input logic [INPUTS-1:0] s_bready,
 000075     output logic [INPUTS-1:0][ID_WIDTH-1:0] s_bid,
%000000     output logic [INPUTS-1:0][1:0] s_bresp,
~000152     output logic [OUTPUTS-1:0] release_valid,
 000173     output logic [INPUTS-1:0] complete_valid,
 000075     output logic [INPUTS-1:0][ID_WIDTH-1:0] complete_id
        );
~000149     logic [OUTPUTS-1:0] head_valid;
~000150     logic [OUTPUTS-1:0] head_pop;
~000130     logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] head_id;
%000000     logic [OUTPUTS-1:0][1:0] head_resp;
 000156     logic [INPUTS-1:0] full;
 000156     logic [INPUTS-1:0] capture;
~000075     logic [INPUTS-1:0][SELECT_WIDTH-1:0] selected;
        
            initial begin
~000018         assert (INPUTS > 0 && OUTPUTS > 0 && ID_WIDTH > 0 && RESPONSE_DEPTH > 0 &&
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
~033582         assign release_valid[o] = m_bvalid[o] && m_bready[o];
                assert property (@(posedge clk) disable iff (!reset_n)
                    m_bvalid[o] |-> int'(m_bid[o][OUTPUT_ID_WIDTH-1:ID_WIDTH]) < INPUTS)
                    else $fatal(1, "BRESP_INVALID_SOURCE");
            end
        
 031830     always_comb begin
 031830         head_pop = '0;
 127320         for (int i = 0; i < INPUTS; i++) begin
 121665             if (capture[i]) begin
 005655                 head_pop[selected[i]] = 1;
                    end
                end
            end
        
 000648     for (genvar i = 0; i < INPUTS; i++) begin : ingress
~000042         logic [OUTPUTS-1:0] request;
 000149         logic selected_valid;
                for (genvar o = 0; o < OUTPUTS; o++) begin : contenders
~127320             assign request[o] = head_valid[o] &&
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
 117931         assign capture[i] = selected_valid && !full[i];
 026964         assign s_bvalid[i] = reset_n && full[i];
 028020         assign complete_valid[i] = s_bvalid[i] && s_bready[i];
                assign complete_id[i] = s_bid[i];
 013344         always_ff @(posedge clk or negedge reset_n) begin
 012696             if (!reset_n) begin
 000648                 full[i] <= 0;
 000648                 s_bid[i] <= '0;
 000648                 s_bresp[i] <= '0;
                    end
 000605             else if (capture[i]) begin
 000605                 full[i] <= 1;
 000605                 s_bid[i] <= head_id[selected[i]][ID_WIDTH-1:0];
 000605                 s_bresp[i] <= head_resp[selected[i]];
                    end
 011492             else if (complete_valid[i]) begin
 000599                 full[i] <= 0;
                    end
                end
                assert property (@(posedge clk) disable iff (!reset_n)
                    s_bvalid[i] && !s_bready[i] |=> s_bvalid[i] && $stable({s_bid[i], s_bresp[i]}))
                    else $fatal(1, "BRESP_UNSTABLE");
            end
        endmodule
        
