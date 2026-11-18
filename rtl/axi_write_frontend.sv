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
    input logic clk,
    input logic reset_n,
    input logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_base,
    input logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_limit,
    input logic [INPUTS-1:0] s_awvalid,
    output logic [INPUTS-1:0] s_awready,
    input logic [INPUTS-1:0][ID_WIDTH-1:0] s_awid,
    input logic [INPUTS-1:0][ADDR_WIDTH-1:0] s_awaddr,
    input logic [INPUTS-1:0][7:0] s_awlen,
    // {AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS}
    input logic [INPUTS-1:0][16:0] s_awattr,
    output logic [OUTPUTS-1:0] m_awvalid,
    input logic [OUTPUTS-1:0] m_awready,
    output logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] m_awid,
    output logic [OUTPUTS-1:0][ADDR_WIDTH-1:0] m_awaddr,
    output logic [OUTPUTS-1:0][7:0] m_awlen,
    output logic [OUTPUTS-1:0][16:0] m_awattr,
    // Upstream B handshake notification: original ID, one per input per cycle.
    input logic [INPUTS-1:0] complete_valid,
    input logic [INPUTS-1:0][ID_WIDTH-1:0] complete_id,
    // Downstream B accepted into response storage: one per output per cycle.
    input logic [OUTPUTS-1:0] release_valid,
    output logic [INPUTS-1:0] w_target_valid,
    input logic [INPUTS-1:0] w_target_ready,
    output logic [INPUTS-1:0][TARGET_WIDTH-1:0] w_target,
    output logic [INPUTS-1:0][7:0] w_target_len,
    output logic [OUTPUTS-1:0] w_source_valid,
    input logic [OUTPUTS-1:0] w_source_ready,
    output logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] w_source,
    output logic [OUTPUTS-1:0][7:0] w_source_len
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

    aw_record_t head [INPUTS];
    aw_record_t output_record [OUTPUTS];
    logic [INPUTS-1:0] head_valid;
    logic [INPUTS-1:0] head_pop;
    logic [INPUTS-1:0] issued;
    logic [INPUTS-1:0] capture_input;
    logic [OUTPUTS-1:0] output_full;
    logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] output_owner;
    logic [OUTPUTS-1:0][OCW-1:0] output_count;
    logic [OUTPUTS-1:0] capture_output;
    logic [OUTPUTS-1:0] aw_fire;
    logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] selected;
    logic [OUTPUTS-1:0] selected_valid;
    logic [OUTPUTS-1:0] source_space;

    initial begin
        assert (INPUTS > 0 && SLAVES > 0 && INPUT_LIMIT > 0 && OUTPUT_LIMIT > 0 &&
                OUTPUTS == SLAVES + 1 && OUTPUT_ID_WIDTH == ID_WIDTH + SOURCE_WIDTH)
            else $fatal(1, "FRONTEND_PARAMETERS");
    end

    for (genvar i = 0; i < INPUTS; i++) begin : ingress
        logic map_valid;
        logic decode_error;
        logic [TARGET_WIDTH-1:0] decoded;
        logic tracker_ready;
        logic aw_space;
        logic route_space;
        logic accept_aw;
        logic ready_registered;
        logic [AW_WIDTH-1:0] fifo_head;
        axi_address_decode #(
            .ADDR_WIDTH(ADDR_WIDTH), .TARGETS(SLAVES), .TARGET_WIDTH(TARGET_WIDTH)
        ) decode (
            .address(s_awaddr[i]), .map_base(map_base), .map_limit(map_limit),
            .map_valid(map_valid), .decode_error(decode_error), .target(decoded)
        );
        // One producer owns these resources. Once granted, only completions
        // can change availability until this held request handshakes.
        assign s_awready[i] = reset_n && ready_registered;
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                ready_registered <= 0;
            end
            else if (ready_registered) begin
                ready_registered <= 0;
            end
            else if (s_awvalid[i] && tracker_ready && aw_space && route_space && map_valid) begin
                ready_registered <= 1;
            end
        end
        assign accept_aw = s_awvalid[i] && s_awready[i];
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
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                issued[i] <= 0;
            end
            else if (head_pop[i]) begin
                issued[i] <= 0;
            end
            else if (capture_input[i]) begin
                issued[i] <= 1;
            end
        end
        assert property (@(posedge clk) disable iff (!reset_n)
            accept_aw |-> tracker_ready && aw_space && route_space && map_valid)
            else $fatal(1, "FRONTEND_ADMISSION_LOST");
        assert property (@(posedge clk) disable iff (!reset_n)
            s_awvalid[i] |-> map_valid)
            else $fatal(1, "FRONTEND_INVALID_MAP");
    end

    always_comb begin
        capture_input = '0;
        head_pop = '0;
        for (int o = 0; o < OUTPUTS; o++) begin
            if (capture_output[o]) begin
                capture_input[selected[o]] = 1;
            end
            if (aw_fire[o]) begin
                head_pop[output_owner[o]] = 1;
            end
        end
    end

    for (genvar o = 0; o < OUTPUTS; o++) begin : egress
        logic [INPUTS-1:0] request;
        logic can_capture;
        for (genvar i = 0; i < INPUTS; i++) begin : contenders
            assign request[i] = head_valid[i] && !issued[i] && head[i].target == TARGET_WIDTH'(o);
        end
        assign can_capture = !output_full[o] && source_space[o] &&
                             output_count[o] < OCW'(OUTPUT_LIMIT);
        axi_rr_arbiter #(.PORTS(INPUTS)) arbiter (
            .clk(clk), .reset_n(reset_n), .request(request), .grant_ready(can_capture),
            .grant_valid(selected_valid[o]), .grant_index(selected[o]),
            .grant_onehot(), .request_ready()
        );
        assign capture_output[o] = selected_valid[o] && can_capture;
        assign m_awvalid[o] = reset_n && output_full[o];
        assign m_awid[o] = {output_owner[o], output_record[o].id};
        assign m_awaddr[o] = output_record[o].addr;
        assign m_awlen[o] = output_record[o].len;
        assign m_awattr[o] = output_record[o].attr;
        assign aw_fire[o] = m_awvalid[o] && m_awready[o];
        axi_record_fifo #(.WIDTH(SOURCE_WIDTH + 8), .DEPTH(OUTPUT_LIMIT)) source_queue (
            .clk(clk), .reset_n(reset_n), .push_valid(aw_fire[o]), .push_ready(source_space[o]),
            .push_data({output_owner[o], output_record[o].len}),
            .pop_valid(w_source_valid[o]), .pop_ready(w_source_ready[o]),
            .pop_data({w_source[o], w_source_len[o]}), .count()
        );
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                output_full[o] <= 0;
                output_owner[o] <= '0;
                output_record[o] <= '0;
                output_count[o] <= '0;
            end
            else begin
                if (capture_output[o]) begin
                    output_full[o] <= 1;
                    output_owner[o] <= selected[o];
                    output_record[o] <= head[selected[o]];
                end
                else if (aw_fire[o]) begin
                    output_full[o] <= 0;
                end
                case ({capture_output[o], release_valid[o]})
                    2'b10: output_count[o] <= output_count[o] + 1'b1;
                    2'b01: output_count[o] <= output_count[o] - 1'b1;
                    default: output_count[o] <= output_count[o];
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
