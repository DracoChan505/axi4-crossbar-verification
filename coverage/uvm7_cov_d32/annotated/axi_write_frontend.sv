//      // verilator_coverage annotation
        // AW/control portion only. The last logical output is the future DECERR endpoint.
        module axi_write_frontend #(
            parameter int INPUTS = 4,
            parameter int SLAVES = 4,
            parameter int ADDR_WIDTH = 32,
            parameter int ID_WIDTH = 2,
            parameter int INPUT_LIMIT = 2,
            parameter int OUTPUT_LIMIT = 4,
            parameter int OUTPUTS = SLAVES + 1,
            parameter int SOURCE_WIDTH = INPUTS > 1 ? $clog2(INPUTS) : 1,
            parameter int TARGET_WIDTH = $clog2(OUTPUTS),
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
~000022     input logic [INPUTS-1:0][7:0] s_awlen,
            // {AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS}
~000021     input logic [INPUTS-1:0][16:0] s_awattr,
~000183     output logic [OUTPUTS-1:0] m_awvalid,
 001024     input logic [OUTPUTS-1:0] m_awready,
~000087     output logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] m_awid,
~000087     output logic [OUTPUTS-1:0][ADDR_WIDTH-1:0] m_awaddr,
~000015     output logic [OUTPUTS-1:0][7:0] m_awlen,
~000033     output logic [OUTPUTS-1:0][16:0] m_awattr,
            // Upstream B handshake notification: original ID, one per input per cycle.
 000173     input logic [INPUTS-1:0] complete_valid,
 000075     input logic [INPUTS-1:0][ID_WIDTH-1:0] complete_id,
            // Downstream B accepted into response storage: one per output per cycle.
~000152     input logic [OUTPUTS-1:0] release_valid,
 000116     output logic [INPUTS-1:0] w_target_valid,
 000202     input logic [INPUTS-1:0] w_target_ready,
~000082     output logic [INPUTS-1:0][TARGET_WIDTH-1:0] w_target,
~000021     output logic [INPUTS-1:0][7:0] w_target_len,
~000127     output logic [OUTPUTS-1:0] w_source_valid,
~000178     input logic [OUTPUTS-1:0] w_source_ready,
~000083     output logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] w_source,
~000014     output logic [OUTPUTS-1:0][7:0] w_source_len
        );
            localparam int AW_WIDTH = TARGET_WIDTH + ID_WIDTH + ADDR_WIDTH + 25;
            localparam int OCW = $clog2(OUTPUT_LIMIT + 1);
            typedef struct packed {
                logic [TARGET_WIDTH-1:0] target;
                logic [ID_WIDTH-1:0] id;
                logic [ADDR_WIDTH-1:0] addr;
                logic [7:0] len;
                logic [16:0] attr;
            } aw_record_t;
        
~000132     aw_record_t head [INPUTS];
            aw_record_t output_record [OUTPUTS];
 000132     logic [INPUTS-1:0] head_valid;
 000214     logic [INPUTS-1:0] head_pop;
 000175     logic [INPUTS-1:0] issued;
 000179     logic [INPUTS-1:0] capture_input;
~000183     logic [OUTPUTS-1:0] output_full;
~000087     logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] output_owner;
~000164     logic [OUTPUTS-1:0][OCW-1:0] output_count;
~000188     logic [OUTPUTS-1:0] capture_output;
~000211     logic [OUTPUTS-1:0] aw_fire;
~000095     logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] selected;
~000145     logic [OUTPUTS-1:0] selected_valid;
 000037     logic [OUTPUTS-1:0] source_space;
        
            initial begin
                assert (INPUTS > 0 && SLAVES > 0 && INPUT_LIMIT > 0 && OUTPUT_LIMIT > 0 &&
~000018                 OUTPUTS == SLAVES + 1 && OUTPUT_ID_WIDTH == ID_WIDTH + SOURCE_WIDTH)
                    else $fatal(1, "FRONTEND_PARAMETERS");
            end
        
 000661     for (genvar i = 0; i < INPUTS; i++) begin : ingress
~000018         logic map_valid;
%000000         logic decode_error;
~000090         logic [TARGET_WIDTH-1:0] decoded;
 000146         logic tracker_ready;
 000079         logic aw_space;
 000100         logic route_space;
 000184         logic accept_aw;
 000184         logic ready_registered;
~000132         logic [AW_WIDTH-1:0] fifo_head;
                axi_address_decode #(
                    .ADDR_WIDTH(ADDR_WIDTH), .TARGETS(SLAVES), .TARGET_WIDTH(TARGET_WIDTH)
                ) decode (
                    .address(s_awaddr[i]), .map_base(map_base), .map_limit(map_limit),
                    .map_valid(map_valid), .decode_error(decode_error), .target(decoded)
                );
                // One producer owns these resources. Once granted, only completions
                // can change availability until this held request handshakes.
 119931         assign s_awready[i] = reset_n && ready_registered;
 013344         always_ff @(posedge clk or negedge reset_n) begin
 012696             if (!reset_n) begin
 000648                 ready_registered <= 0;
                    end
 000717             else if (ready_registered) begin
 000717                 ready_registered <= 0;
                    end
~011250             else if (s_awvalid[i] && tracker_ready && aw_space && route_space && map_valid) begin
 000729                 ready_registered <= 1;
                    end
                end
 031006         assign accept_aw = s_awvalid[i] && s_awready[i];
                axi_write_tracker #(
                    .ID_WIDTH(ID_WIDTH), .TARGETS(OUTPUTS), .MAX_OUTSTANDING(INPUT_LIMIT)
                ) tracker (
                    .clk(clk), .reset_n(reset_n),
                    .request_valid(accept_aw),
                    .request_ready(tracker_ready), .request_id(s_awid[i]), .request_target(decoded),
                    .complete_valid(complete_valid[i]), .complete_id(complete_id[i]),
                    .complete_known(), .complete_target(), .outstanding()
                );
                axi_record_fifo #(.WIDTH(AW_WIDTH), .DEPTH(INPUT_LIMIT)) aw_queue (
                    .clk(clk), .reset_n(reset_n), .push_valid(accept_aw), .push_ready(aw_space),
                    .push_data({decoded, s_awid[i], s_awaddr[i], s_awlen[i], s_awattr[i]}),
                    .pop_valid(head_valid[i]), .pop_ready(head_pop[i]), .pop_data(fifo_head), .count()
                );
                assign head[i] = aw_record_t'(fifo_head);
                axi_record_fifo #(.WIDTH(TARGET_WIDTH + 8), .DEPTH(INPUT_LIMIT)) route_queue (
                    .clk(clk), .reset_n(reset_n), .push_valid(accept_aw), .push_ready(route_space),
                    .push_data({decoded, s_awlen[i]}),
                    .pop_valid(w_target_valid[i]), .pop_ready(w_target_ready[i]),
                    .pop_data({w_target[i], w_target_len[i]}), .count()
                );
 013344         always_ff @(posedge clk or negedge reset_n) begin
 012696             if (!reset_n) begin
 000648                 issued[i] <= 0;
                    end
 000648             else if (head_pop[i]) begin
 000648                 issued[i] <= 0;
                    end
 011387             else if (capture_input[i]) begin
 000661                 issued[i] <= 1;
                    end
                end
                assert property (@(posedge clk) disable iff (!reset_n)
                    accept_aw |-> tracker_ready && aw_space && route_space && map_valid)
                    else $fatal(1, "FRONTEND_ADMISSION_LOST");
                assert property (@(posedge clk) disable iff (!reset_n)
                    s_awvalid[i] |-> map_valid)
                    else $fatal(1, "FRONTEND_INVALID_MAP");
            end
        
 038014     always_comb begin
 038014         capture_input = '0;
 038014         head_pop = '0;
 190070         for (int o = 0; o < OUTPUTS; o++) begin
 182821             if (capture_output[o]) begin
 007249                 capture_input[selected[o]] = 1;
                    end
 184236             if (aw_fire[o]) begin
 005834                 head_pop[output_owner[o]] = 1;
                    end
                end
            end
        
 015870     for (genvar o = 0; o < OUTPUTS; o++) begin : egress
~000055         logic [INPUTS-1:0] request;
 000212         logic can_capture;
                for (genvar i = 0; i < INPUTS; i++) begin : contenders
~137320             assign request[i] = head_valid[i] && !issued[i] && head[i].target == TARGET_WIDTH'(o);
                end
~029140         assign can_capture = !output_full[o] && source_space[o] &&
                                     output_count[o] < OCW'(OUTPUT_LIMIT);
                axi_rr_arbiter #(.PORTS(INPUTS)) arbiter (
                    .clk(clk), .reset_n(reset_n), .request(request), .grant_ready(can_capture),
                    .grant_valid(selected_valid[o]), .grant_index(selected[o]),
                    .grant_onehot(), .request_ready()
                );
~031830         assign capture_output[o] = selected_valid[o] && can_capture;
~031830         assign m_awvalid[o] = reset_n && output_full[o];
                assign m_awid[o] = {output_owner[o], output_record[o].id};
                assign m_awaddr[o] = output_record[o].addr;
                assign m_awlen[o] = output_record[o].len;
                assign m_awattr[o] = output_record[o].attr;
~038014         assign aw_fire[o] = m_awvalid[o] && m_awready[o];
                axi_record_fifo #(.WIDTH(SOURCE_WIDTH + 8), .DEPTH(OUTPUT_LIMIT)) source_queue (
                    .clk(clk), .reset_n(reset_n), .push_valid(aw_fire[o]), .push_ready(source_space[o]),
                    .push_data({output_owner[o], output_record[o].len}),
                    .pop_valid(w_source_valid[o]), .pop_ready(w_source_ready[o]),
                    .pop_data({w_source[o], w_source_len[o]}), .count()
                );
 016680         always_ff @(posedge clk or negedge reset_n) begin
 015870             if (!reset_n) begin
 000810                 output_full[o] <= 0;
 000810                 output_owner[o] <= '0;
 000810                 output_record[o] <= '0;
 000810                 output_count[o] <= '0;
                    end
 015870             else begin
 000661                 if (capture_output[o]) begin
 000661                     output_full[o] <= 1;
 000661                     output_owner[o] <= selected[o];
 000661                     output_record[o] <= head[selected[o]];
                        end
 014561                 else if (aw_fire[o]) begin
 000648                     output_full[o] <= 0;
                        end
 015870                 case ({capture_output[o], release_valid[o]})
 000613                     2'b10: output_count[o] <= output_count[o] + 1'b1;
 000557                     2'b01: output_count[o] <= output_count[o] - 1'b1;
 014700                     default: output_count[o] <= output_count[o];
                        endcase
                    end
                end
                assert property (@(posedge clk) disable iff (!reset_n)
                    release_valid[o] |-> output_count[o] != 0)
                    else $fatal(1, "FRONTEND_UNKNOWN_RELEASE");
                assert property (@(posedge clk) disable iff (!reset_n)
                    aw_fire[o] |-> source_space[o])
                    else $fatal(1, "FRONTEND_SOURCE_OVERFLOW");
                assert property (@(posedge clk) disable iff (!reset_n)
                    m_awvalid[o] && !m_awready[o] |=> m_awvalid[o] &&
                        $stable({m_awid[o], m_awaddr[o], m_awlen[o], m_awattr[o]}))
                    else $fatal(1, "FRONTEND_AW_UNSTABLE");
            end
        endmodule
        
