//      // verilator_coverage annotation
        // AR/control portion of the read crossbar path. No W routing queues needed;
        // R data carries source bits in RID for the return path.
        module axi_read_frontend #(
            parameter int INPUTS       = 4,
            parameter int SLAVES       = 4,
            parameter int ADDR_WIDTH   = 32,
            parameter int ID_WIDTH     = 2,
            parameter int INPUT_LIMIT  = 2,
            parameter int OUTPUT_LIMIT = 4,
            parameter int OUTPUTS         = SLAVES + 1,
            parameter int SOURCE_WIDTH    = INPUTS > 1 ? $clog2(INPUTS) : 1,
            parameter int TARGET_WIDTH    = $clog2(OUTPUTS),
            parameter int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH
        ) (
 003318     input  logic clk,
 000036     input  logic reset_n,
~000018     input  logic [SLAVES-1:0][ADDR_WIDTH-1:0]       map_base,
~000018     input  logic [SLAVES-1:0][ADDR_WIDTH-1:0]       map_limit,
 000141     input  logic [INPUTS-1:0]                        s_arvalid,
 000183     output logic [INPUTS-1:0]                        s_arready,
 000093     input  logic [INPUTS-1:0][ID_WIDTH-1:0]          s_arid,
~000093     input  logic [INPUTS-1:0][ADDR_WIDTH-1:0]        s_araddr,
~000024     input  logic [INPUTS-1:0][7:0]                   s_arlen,
~000018     input  logic [INPUTS-1:0][16:0]                  s_arattr,
~000194     output logic [OUTPUTS-1:0]                       m_arvalid,
 000631     input  logic [OUTPUTS-1:0]                       m_arready,
~000092     output logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0]  m_arid,
~000092     output logic [OUTPUTS-1:0][ADDR_WIDTH-1:0]       m_araddr,
~000018     output logic [OUTPUTS-1:0][7:0]                  m_arlen,
~000036     output logic [OUTPUTS-1:0][16:0]                 m_arattr,
            // From data_path: upstream RLAST accepted by master (tracker release).
 000183     input  logic [INPUTS-1:0]                        complete_valid,
 000073     input  logic [INPUTS-1:0][ID_WIDTH-1:0]          complete_id,
            // From data_path: downstream RLAST into per-output buffer (capacity release).
~000155     input  logic [OUTPUTS-1:0]                       release_valid
        );
            localparam int AR_WIDTH = TARGET_WIDTH + ID_WIDTH + ADDR_WIDTH + 25;
            localparam int OCW = $clog2(OUTPUT_LIMIT + 1);
            typedef struct packed {
                logic [TARGET_WIDTH-1:0] target;
                logic [ID_WIDTH-1:0]     id;
                logic [ADDR_WIDTH-1:0]   addr;
                logic [7:0]              len;
                logic [16:0]             attr;
            } ar_record_t;
        
~000122     ar_record_t head [INPUTS];
            ar_record_t output_record [OUTPUTS];
 000122     logic [INPUTS-1:0]                       head_valid;
 000211     logic [INPUTS-1:0]                       head_pop;
 000180     logic [INPUTS-1:0]                       issued;
 000183     logic [INPUTS-1:0]                       capture_input;
~000194     logic [OUTPUTS-1:0]                      output_full;
~000092     logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0]    output_owner;
~000161     logic [OUTPUTS-1:0][OCW-1:0]            output_count;
~000197     logic [OUTPUTS-1:0]                      capture_output;
~000216     logic [OUTPUTS-1:0]                      ar_fire;
~000098     logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0]    selected;
~000142     logic [OUTPUTS-1:0]                      selected_valid;
        
            initial begin
                assert (INPUTS > 0 && SLAVES > 0 && INPUT_LIMIT > 0 && OUTPUT_LIMIT > 0 &&
~000018                 OUTPUTS == SLAVES + 1 && OUTPUT_ID_WIDTH == ID_WIDTH + SOURCE_WIDTH)
                    else $fatal(1, "FRONTEND_READ_PARAMETERS");
            end
        
 000677     for (genvar i = 0; i < INPUTS; i++) begin : ingress
~000018         logic map_valid;
%000000         logic decode_error;
~000093         logic [TARGET_WIDTH-1:0] decoded;
 000132         logic tracker_ready;
 000080         logic ar_space;
 000183         logic accept_ar;
 000183         logic ready_registered;
~000122         logic [AR_WIDTH-1:0] fifo_head;
        
                axi_address_decode #(
                    .ADDR_WIDTH(ADDR_WIDTH), .TARGETS(SLAVES), .TARGET_WIDTH(TARGET_WIDTH)
                ) decode (
                    .address(s_araddr[i]), .map_base(map_base), .map_limit(map_limit),
                    .map_valid(map_valid), .decode_error(decode_error), .target(decoded)
                );
        
 119770         assign s_arready[i] = reset_n && ready_registered;
 013344         always_ff @(posedge clk or negedge reset_n) begin
 012696             if (!reset_n) begin
 000648                 ready_registered <= 0;
                    end
 000724             else if (ready_registered) begin
 000724                 ready_registered <= 0;
                    end
~011248             else if (s_arvalid[i] && tracker_ready && ar_space && map_valid) begin
 000724                 ready_registered <= 1;
                    end
                end
        
 030883         assign accept_ar = s_arvalid[i] && s_arready[i];
        
                axi_write_tracker #(
                    .ID_WIDTH(ID_WIDTH), .TARGETS(OUTPUTS), .MAX_OUTSTANDING(INPUT_LIMIT)
                ) tracker (
                    .clk(clk), .reset_n(reset_n),
                    .request_valid(accept_ar),
                    .request_ready(tracker_ready), .request_id(s_arid[i]), .request_target(decoded),
                    .complete_valid(complete_valid[i]), .complete_id(complete_id[i]),
                    .complete_known(), .complete_target(), .outstanding()
                );
        
                axi_record_fifo #(.WIDTH(AR_WIDTH), .DEPTH(INPUT_LIMIT)) ar_queue (
                    .clk(clk), .reset_n(reset_n),
                    .push_valid(accept_ar), .push_ready(ar_space),
                    .push_data({decoded, s_arid[i], s_araddr[i], s_arlen[i], s_arattr[i]}),
                    .pop_valid(head_valid[i]), .pop_ready(head_pop[i]),
                    .pop_data(fifo_head), .count()
                );
                assign head[i] = ar_record_t'(fifo_head);
        
 013344         always_ff @(posedge clk or negedge reset_n) begin
 012696             if (!reset_n)        issued[i] <= 0;
 000663             else if (head_pop[i]) issued[i] <= 0;
 011356             else if (capture_input[i]) issued[i] <= 1;
                end
        
                assert property (@(posedge clk) disable iff (!reset_n)
                    accept_ar |-> tracker_ready && ar_space && map_valid)
                    else $fatal(1, "FRONTEND_READ_ADMISSION_LOST");
                assert property (@(posedge clk) disable iff (!reset_n)
                    s_arvalid[i] |-> map_valid)
                    else $fatal(1, "FRONTEND_READ_INVALID_MAP");
            end
        
 037010     always_comb begin
 037010         capture_input = '0;
 037010         head_pop      = '0;
 185050         for (int o = 0; o < OUTPUTS; o++) begin
 177889             if (capture_output[o])
 007161                 capture_input[selected[o]] = 1;
 178577             if (ar_fire[o])
 006473                 head_pop[output_owner[o]] = 1;
                end
            end
        
 015870     for (genvar o = 0; o < OUTPUTS; o++) begin : egress
~000054         logic [INPUTS-1:0] request;
~000212         logic can_capture;
        
                for (genvar i = 0; i < INPUTS; i++) begin : contenders
~139340             assign request[i] = head_valid[i] && !issued[i] &&
                                         head[i].target == TARGET_WIDTH'(o);
                end
        
~003354         assign can_capture = !output_full[o] && output_count[o] < OCW'(OUTPUT_LIMIT);
        
                axi_rr_arbiter #(.PORTS(INPUTS)) arbiter (
                    .clk(clk), .reset_n(reset_n),
                    .request(request), .grant_ready(can_capture),
                    .grant_valid(selected_valid[o]), .grant_index(selected[o]),
                    .grant_onehot(), .request_ready()
                );
        
~031830         assign capture_output[o] = selected_valid[o] && can_capture;
~031830         assign m_arvalid[o]      = reset_n && output_full[o];
                assign m_arid[o]         = {output_owner[o], output_record[o].id};
                assign m_araddr[o]       = output_record[o].addr;
                assign m_arlen[o]        = output_record[o].len;
                assign m_arattr[o]       = output_record[o].attr;
~037010         assign ar_fire[o]        = m_arvalid[o] && m_arready[o];
        
 016680         always_ff @(posedge clk or negedge reset_n) begin
 015870             if (!reset_n) begin
 000810                 output_full[o]    <= 0;
 000810                 output_owner[o]   <= '0;
 000810                 output_record[o]  <= '0;
 000810                 output_count[o]   <= '0;
                    end
 015870             else begin
 000677                 if (capture_output[o]) begin
 000677                     output_full[o]   <= 1;
 000677                     output_owner[o]  <= selected[o];
 000677                     output_record[o] <= head[selected[o]];
                        end
 014530                 else if (ar_fire[o]) begin
 000663                     output_full[o] <= 0;
                        end
 015870                 case ({capture_output[o], release_valid[o]})
 000597                     2'b10:   output_count[o] <= output_count[o] + 1'b1;
 000533                     2'b01:   output_count[o] <= output_count[o] - 1'b1;
 014740                     default: output_count[o] <= output_count[o];
                        endcase
                    end
                end
        
                // Allow simultaneous capture+release (output_count stays 0→0 via default case).
                assert property (@(posedge clk) disable iff (!reset_n)
                    release_valid[o] |-> (output_count[o] != 0 || capture_output[o]))
                    else $fatal(1, "FRONTEND_READ_UNKNOWN_RELEASE");
                assert property (@(posedge clk) disable iff (!reset_n)
                    m_arvalid[o] && !m_arready[o] |=>
                        m_arvalid[o] && $stable({m_arid[o], m_araddr[o], m_arlen[o], m_arattr[o]}))
                    else $fatal(1, "FRONTEND_READ_AR_UNSTABLE");
            end
        endmodule
        
