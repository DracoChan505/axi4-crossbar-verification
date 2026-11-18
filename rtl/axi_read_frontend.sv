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
    input  logic clk,
    input  logic reset_n,
    input  logic [SLAVES-1:0][ADDR_WIDTH-1:0]       map_base,
    input  logic [SLAVES-1:0][ADDR_WIDTH-1:0]       map_limit,
    input  logic [INPUTS-1:0]                        s_arvalid,
    output logic [INPUTS-1:0]                        s_arready,
    input  logic [INPUTS-1:0][ID_WIDTH-1:0]          s_arid,
    input  logic [INPUTS-1:0][ADDR_WIDTH-1:0]        s_araddr,
    input  logic [INPUTS-1:0][7:0]                   s_arlen,
    input  logic [INPUTS-1:0][16:0]                  s_arattr,
    output logic [OUTPUTS-1:0]                       m_arvalid,
    input  logic [OUTPUTS-1:0]                       m_arready,
    output logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0]  m_arid,
    output logic [OUTPUTS-1:0][ADDR_WIDTH-1:0]       m_araddr,
    output logic [OUTPUTS-1:0][7:0]                  m_arlen,
    output logic [OUTPUTS-1:0][16:0]                 m_arattr,
    // From data_path: upstream RLAST accepted by master (tracker release).
    input  logic [INPUTS-1:0]                        complete_valid,
    input  logic [INPUTS-1:0][ID_WIDTH-1:0]          complete_id,
    // From data_path: downstream RLAST into per-output buffer (capacity release).
    input  logic [OUTPUTS-1:0]                       release_valid
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

    ar_record_t head [INPUTS];
    ar_record_t output_record [OUTPUTS];
    logic [INPUTS-1:0]                       head_valid;
    logic [INPUTS-1:0]                       head_pop;
    logic [INPUTS-1:0]                       issued;
    logic [INPUTS-1:0]                       capture_input;
    logic [OUTPUTS-1:0]                      output_full;
    logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0]    output_owner;
    logic [OUTPUTS-1:0][OCW-1:0]            output_count;
    logic [OUTPUTS-1:0]                      capture_output;
    logic [OUTPUTS-1:0]                      ar_fire;
    logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0]    selected;
    logic [OUTPUTS-1:0]                      selected_valid;

    initial begin
        assert (INPUTS > 0 && SLAVES > 0 && INPUT_LIMIT > 0 && OUTPUT_LIMIT > 0 &&
                OUTPUTS == SLAVES + 1 && OUTPUT_ID_WIDTH == ID_WIDTH + SOURCE_WIDTH)
            else $fatal(1, "FRONTEND_READ_PARAMETERS");
    end

    for (genvar i = 0; i < INPUTS; i++) begin : ingress
        logic map_valid;
        logic decode_error;
        logic [TARGET_WIDTH-1:0] decoded;
        logic tracker_ready;
        logic ar_space;
        logic accept_ar;
        logic ready_registered;
        logic [AR_WIDTH-1:0] fifo_head;

        axi_address_decode #(
            .ADDR_WIDTH(ADDR_WIDTH), .TARGETS(SLAVES), .TARGET_WIDTH(TARGET_WIDTH)
        ) decode (
            .address(s_araddr[i]), .map_base(map_base), .map_limit(map_limit),
            .map_valid(map_valid), .decode_error(decode_error), .target(decoded)
        );

        assign s_arready[i] = reset_n && ready_registered;
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                ready_registered <= 0;
            end
            else if (ready_registered) begin
                ready_registered <= 0;
            end
            else if (s_arvalid[i] && tracker_ready && ar_space && map_valid) begin
                ready_registered <= 1;
            end
        end

        assign accept_ar = s_arvalid[i] && s_arready[i];

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

        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n)        issued[i] <= 0;
            else if (head_pop[i]) issued[i] <= 0;
            else if (capture_input[i]) issued[i] <= 1;
        end

        assert property (@(posedge clk) disable iff (!reset_n)
            accept_ar |-> tracker_ready && ar_space && map_valid)
            else $fatal(1, "FRONTEND_READ_ADMISSION_LOST");
        assert property (@(posedge clk) disable iff (!reset_n)
            s_arvalid[i] |-> map_valid)
            else $fatal(1, "FRONTEND_READ_INVALID_MAP");
    end

    always_comb begin
        capture_input = '0;
        head_pop      = '0;
        for (int o = 0; o < OUTPUTS; o++) begin
            if (capture_output[o])
                capture_input[selected[o]] = 1;
            if (ar_fire[o])
                head_pop[output_owner[o]] = 1;
        end
    end

    for (genvar o = 0; o < OUTPUTS; o++) begin : egress
        logic [INPUTS-1:0] request;
        logic can_capture;

        for (genvar i = 0; i < INPUTS; i++) begin : contenders
            assign request[i] = head_valid[i] && !issued[i] &&
                                 head[i].target == TARGET_WIDTH'(o);
        end

        assign can_capture = !output_full[o] && output_count[o] < OCW'(OUTPUT_LIMIT);

        axi_rr_arbiter #(.PORTS(INPUTS)) arbiter (
            .clk(clk), .reset_n(reset_n),
            .request(request), .grant_ready(can_capture),
            .grant_valid(selected_valid[o]), .grant_index(selected[o]),
            .grant_onehot(), .request_ready()
        );

        assign capture_output[o] = selected_valid[o] && can_capture;
        assign m_arvalid[o]      = reset_n && output_full[o];
        assign m_arid[o]         = {output_owner[o], output_record[o].id};
        assign m_araddr[o]       = output_record[o].addr;
        assign m_arlen[o]        = output_record[o].len;
        assign m_arattr[o]       = output_record[o].attr;
        assign ar_fire[o]        = m_arvalid[o] && m_arready[o];

        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                output_full[o]    <= 0;
                output_owner[o]   <= '0;
                output_record[o]  <= '0;
                output_count[o]   <= '0;
            end
            else begin
                if (capture_output[o]) begin
                    output_full[o]   <= 1;
                    output_owner[o]  <= selected[o];
                    output_record[o] <= head[selected[o]];
                end
                else if (ar_fire[o]) begin
                    output_full[o] <= 0;
                end
                case ({capture_output[o], release_valid[o]})
                    2'b10:   output_count[o] <= output_count[o] + 1'b1;
                    2'b01:   output_count[o] <= output_count[o] - 1'b1;
                    default: output_count[o] <= output_count[o];
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
