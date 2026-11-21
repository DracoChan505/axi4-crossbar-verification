//      // verilator_coverage annotation
        // R data routing from slaves back to masters. Per-output FIFO buffers incoming
        // R beats; per-input locking keeps a burst's beats together until RLAST fires.
        module axi_read_data_path #(
            parameter int INPUTS          = 4,
            parameter int OUTPUTS         = 5,
            parameter int DATA_WIDTH      = 32,
            parameter int ID_WIDTH        = 2,
            parameter int RESPONSE_DEPTH  = 2,
            parameter int SOURCE_WIDTH    = INPUTS > 1 ? $clog2(INPUTS) : 1,
            parameter int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH,
            parameter int SELECT_WIDTH    = OUTPUTS > 1 ? $clog2(OUTPUTS) : 1,
            parameter int BEAT_WIDTH      = OUTPUT_ID_WIDTH + DATA_WIDTH + 3
        ) (
 003318     input  logic clk,
 000036     input  logic reset_n,
            // From slaves (downstream R)
~000151     input  logic [OUTPUTS-1:0]                       m_rvalid,
 000074     output logic [OUTPUTS-1:0]                       m_rready,
~000151     input  logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0]  m_rid,
~000151     input  logic [OUTPUTS-1:0][DATA_WIDTH-1:0]        m_rdata,
~000018     input  logic [OUTPUTS-1:0][1:0]                  m_rresp,
~000159     input  logic [OUTPUTS-1:0]                       m_rlast,
            // To masters (upstream R)
 000179     output logic [INPUTS-1:0]                  s_rvalid,
 000175     input  logic [INPUTS-1:0]                  s_rready,
 000073     output logic [INPUTS-1:0][ID_WIDTH-1:0]    s_rid,
~000077     output logic [INPUTS-1:0][DATA_WIDTH-1:0]  s_rdata,
%000000     output logic [INPUTS-1:0][1:0]             s_rresp,
~000029     output logic [INPUTS-1:0]                  s_rlast,
            // To frontend
~000155     output logic [OUTPUTS-1:0]                 release_valid,
 000183     output logic [INPUTS-1:0]                  complete_valid,
 000073     output logic [INPUTS-1:0][ID_WIDTH-1:0]    complete_id
        );
~000130     logic [OUTPUTS-1:0]            head_valid;
~000154     logic [OUTPUTS-1:0]            head_pop;
~000131     logic [OUTPUTS-1:0][BEAT_WIDTH-1:0] head_data;
~000130     logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] head_id;
~000130     logic [OUTPUTS-1:0][DATA_WIDTH-1:0]      head_pdata;
%000000     logic [OUTPUTS-1:0][1:0]                 head_resp;
~000131     logic [OUTPUTS-1:0]                      head_last;
 000179     logic [INPUTS-1:0]                       full;
 000182     logic [INPUTS-1:0]                       capture;
~000079     logic [INPUTS-1:0][SELECT_WIDTH-1:0]      selected;
~000016     logic [INPUTS-1:0]                        locked;
~000073     logic [INPUTS-1:0][SELECT_WIDTH-1:0]      locked_source;
        
            initial begin
                assert (INPUTS > 0 && OUTPUTS > 0 && DATA_WIDTH >= 8 &&
~000018                 DATA_WIDTH % 8 == 0 && RESPONSE_DEPTH > 0 &&
                        OUTPUT_ID_WIDTH == ID_WIDTH + SOURCE_WIDTH)
                    else $fatal(1, "RDATA_PARAMETERS");
            end
        
            for (genvar o = 0; o < OUTPUTS; o++) begin : egress
                axi_record_fifo #(.WIDTH(BEAT_WIDTH), .DEPTH(RESPONSE_DEPTH)) buffer (
                    .clk(clk), .reset_n(reset_n),
                    .push_valid(m_rvalid[o]), .push_ready(m_rready[o]),
                    .push_data({m_rid[o], m_rdata[o], m_rresp[o], m_rlast[o]}),
                    .pop_valid(head_valid[o]), .pop_ready(head_pop[o]),
                    .pop_data(head_data[o]), .count()
                );
                assign {head_id[o], head_pdata[o], head_resp[o], head_last[o]} = head_data[o];
~033528         assign release_valid[o] = m_rvalid[o] && m_rready[o] && m_rlast[o];
                assert property (@(posedge clk) disable iff (!reset_n)
                    m_rvalid[o] |-> int'(m_rid[o][OUTPUT_ID_WIDTH-1:ID_WIDTH]) < INPUTS)
                    else $fatal(1, "RDATA_INVALID_SOURCE");
            end
        
 031830     always_comb begin
 031830         head_pop = '0;
 127320         for (int i = 0; i < INPUTS; i++) begin
 121053             if (capture[i])
 006267                 head_pop[selected[i]] = 1;
                end
            end
        
 000653     for (genvar i = 0; i < INPUTS; i++) begin : ingress
~000047         logic [OUTPUTS-1:0] request;
 000147         logic selected_valid;
                for (genvar o = 0; o < OUTPUTS; o++) begin : contenders
                    assign request[o] = head_valid[o] &&
~127320                                 head_id[o][OUTPUT_ID_WIDTH-1:ID_WIDTH] == SOURCE_WIDTH'(i) &&
                                        (!locked[i] || locked_source[i] == SELECT_WIDTH'(o));
                end
                axi_rr_arbiter #(.PORTS(OUTPUTS)) arbiter (
                    .clk(clk), .reset_n(reset_n),
                    .request(request), .grant_ready(!full[i]),
                    .grant_valid(selected_valid), .grant_index(selected[i]),
                    .grant_onehot(), .request_ready()
                );
 114981         assign capture[i] = selected_valid && !full[i];
 027406         assign s_rvalid[i] = reset_n && full[i];
 028687         assign complete_valid[i] = s_rvalid[i] && s_rready[i] && s_rlast[i];
                assign complete_id[i] = s_rid[i];
 013344         always_ff @(posedge clk or negedge reset_n) begin
 012696             if (!reset_n) begin
 000648                 full[i]         <= 0;
 000648                 s_rid[i]        <= '0;
 000648                 s_rdata[i]      <= '0;
 000648                 s_rresp[i]      <= '0;
 000648                 s_rlast[i]      <= 0;
 000648                 locked[i]       <= 0;
 000648                 locked_source[i] <= '0;
                    end
 000653             else if (capture[i]) begin
 000653                 full[i]    <= 1;
 000653                 s_rid[i]   <= head_id[selected[i]][ID_WIDTH-1:0];
 000653                 s_rdata[i] <= head_pdata[selected[i]];
 000653                 s_rresp[i] <= head_resp[selected[i]];
 000653                 s_rlast[i] <= head_last[selected[i]];
~000653                 locked[i]  <= !head_last[selected[i]];
 000653                 locked_source[i] <= selected[i];
                    end
                    // Master accepted any beat: free the output register so the next
                    // beat can capture. complete_valid (RLAST only) drives the tracker
                    // separately and does not gate the output register here.
 011409             else if (s_rvalid[i] && s_rready[i]) begin
 000634                 full[i] <= 0;
                    end
                end
                assert property (@(posedge clk) disable iff (!reset_n)
                    s_rvalid[i] && !s_rready[i] |=>
                        s_rvalid[i] && $stable({s_rid[i], s_rdata[i], s_rresp[i], s_rlast[i]}))
                    else $fatal(1, "RDATA_UNSTABLE");
            end
        endmodule
        
