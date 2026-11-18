// Per-ingress write admission. No AXI data or response buffering lives here.
module axi_write_tracker #(
    parameter int ID_WIDTH = 2,
    parameter int TARGETS = 5,
    parameter int MAX_OUTSTANDING = 2,
    parameter int TARGET_WIDTH = (TARGETS > 1) ? $clog2(TARGETS) : 1,
    parameter int COUNT_WIDTH = $clog2(MAX_OUTSTANDING + 1)
) (
    input  logic clk,
    input  logic reset_n,
    input  logic request_valid,
    output logic request_ready,
    input  logic [ID_WIDTH-1:0] request_id,
    input  logic [TARGET_WIDTH-1:0] request_target,
    // A pulse for the upstream B handshake, with the restored original ID.
    input  logic complete_valid,
    input  logic [ID_WIDTH-1:0] complete_id,
    output logic complete_known,
    output logic [TARGET_WIDTH-1:0] complete_target,
    output logic [COUNT_WIDTH-1:0] outstanding
);
    logic [ID_WIDTH-1:0] ids [MAX_OUTSTANDING];
    logic [TARGET_WIDTH-1:0] targets [MAX_OUTSTANDING];
    logic [COUNT_WIDTH-1:0] counts [MAX_OUTSTANDING];
    integer request_slot;
    integer complete_slot;
    integer free_slot;
    integer allocate_slot;
    logic accept_request;
    logic accept_completion;

    initial begin
        assert (ID_WIDTH >= 1 && TARGETS >= 1 && MAX_OUTSTANDING >= 1)
            else $fatal(1, "TRACKER_PARAMETERS");
        assert (TARGET_WIDTH >= ((TARGETS > 1) ? $clog2(TARGETS) : 1))
            else $fatal(1, "TRACKER_TARGET_WIDTH");
        assert (COUNT_WIDTH >= $clog2(MAX_OUTSTANDING + 1))
            else $fatal(1, "TRACKER_COUNT_WIDTH");
    end

    always_comb begin
        request_slot = -1;
        complete_slot = -1;
        free_slot = -1;
        for (int i = 0; i < MAX_OUTSTANDING; i++) begin
            if (counts[i] != 0) begin
                if (ids[i] == request_id) begin
                    request_slot = i;
                end
                if (ids[i] == complete_id) begin
                    complete_slot = i;
                end
            end
            else if (free_slot < 0) begin
                free_slot = i;
            end
        end
        allocate_slot = request_slot >= 0 ? request_slot : free_slot;
        complete_known = reset_n && complete_slot >= 0;
        complete_target = '0;
        if (complete_known) begin
            complete_target = targets[complete_slot];
        end
        request_ready = 0;
        if (reset_n && outstanding < COUNT_WIDTH'(MAX_OUTSTANDING) &&
            int'(request_target) < TARGETS && allocate_slot >= 0) begin
            if (request_slot < 0) begin
                request_ready = 1;
            end
            else begin
                request_ready = targets[request_slot] == request_target;
            end
        end
        accept_request = request_valid && request_ready;
        accept_completion = complete_valid && complete_known;
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            outstanding <= '0;
            for (int i = 0; i < MAX_OUTSTANDING; i++) begin
                ids[i] <= '0;
                targets[i] <= '0;
                counts[i] <= '0;
            end
        end
        else begin
            case ({accept_request, accept_completion})
                2'b10: outstanding <= outstanding + 1'b1;
                2'b01: outstanding <= outstanding - 1'b1;
                default: outstanding <= outstanding;
            endcase
            for (int i = 0; i < MAX_OUTSTANDING; i++) begin
                case ({accept_request && allocate_slot == i,
                       accept_completion && complete_slot == i})
                    2'b10: counts[i] <= counts[i] + 1'b1;
                    2'b01: counts[i] <= counts[i] - 1'b1;
                    default: counts[i] <= counts[i];
                endcase
                if (accept_request && allocate_slot == i) begin
                    ids[i] <= request_id;
                    targets[i] <= request_target;
                end
            end
        end
    end

    // These diagnose broken integration; they do not invent a B response.
    property completion_has_record;
        @(posedge clk) disable iff (!reset_n)
        complete_valid |-> complete_known;
    endproperty
    assert property (completion_has_record)
        else $fatal(1, "TRACKER_UNKNOWN_COMPLETION");

    property admission_has_capacity;
        @(posedge clk) disable iff (!reset_n)
        accept_request |-> outstanding < COUNT_WIDTH'(MAX_OUTSTANDING);
    endproperty
    assert property (admission_has_capacity)
        else $fatal(1, "TRACKER_OVERFLOW");
endmodule
