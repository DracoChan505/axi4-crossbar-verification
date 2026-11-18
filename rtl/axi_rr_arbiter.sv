// Internal valid/ready arbitration. Sources hold a selected request until taken.
// This block selects an index; payload storage belongs to the channel wrapper.
module axi_rr_arbiter #(
    parameter int PORTS = 4,
    parameter int INDEX_WIDTH = PORTS > 1 ? $clog2(PORTS) : 1
) (
    input  logic clk,
    input  logic reset_n,
    input  logic [PORTS-1:0] request,
    input  logic grant_ready,
    output logic grant_valid,
    output logic [INDEX_WIDTH-1:0] grant_index,
    output logic [PORTS-1:0] grant_onehot,
    output logic [PORTS-1:0] request_ready
);
    logic [INDEX_WIDTH-1:0] next_start;
    logic locked;
    logic [INDEX_WIDTH-1:0] locked_index;
    integer candidate;

    initial begin
        assert (PORTS >= 1 && INDEX_WIDTH >= (PORTS > 1 ? $clog2(PORTS) : 1))
            else $fatal(1, "ARBITER_PARAMETERS");
    end

    always_comb begin
        grant_valid = 0;
        grant_index = '0;
        grant_onehot = '0;
        request_ready = '0;
        candidate = 0;
        if (reset_n) begin
            if (locked) begin
                grant_valid = 1;
                grant_index = locked_index;
            end
            else begin
                for (int offset = 0; offset < PORTS; offset++) begin
                    candidate = int'(next_start) + offset;
                    if (candidate >= PORTS) begin
                        candidate = candidate - PORTS;
                    end
                    if (!grant_valid && request[candidate]) begin
                        grant_valid = 1;
                        grant_index = INDEX_WIDTH'(candidate);
                    end
                end
            end
            if (grant_valid) begin
                grant_onehot[grant_index] = 1;
                request_ready[grant_index] = grant_ready;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            next_start <= '0;
            locked <= 0;
            locked_index <= '0;
        end
        else if (grant_valid && grant_ready) begin
            if (int'(grant_index) == PORTS - 1) begin
                next_start <= '0;
            end
            else begin
                next_start <= grant_index + 1'b1;
            end
            locked <= 0;
        end
        else if (grant_valid) begin
            locked <= 1;
            locked_index <= grant_index;
        end
    end

    property selected_source_stays_valid;
        @(posedge clk) disable iff (!reset_n)
        locked |-> request[locked_index];
    endproperty
    assert property (selected_source_stays_valid)
        else $fatal(1, "ARBITER_REQUEST_WITHDRAWN");

    property stalled_selection_stays;
        @(posedge clk) disable iff (!reset_n)
        grant_valid && !grant_ready |=> grant_valid && $stable(grant_index);
    endproperty
    assert property (stalled_selection_stays)
        else $fatal(1, "ARBITER_UNSTABLE_GRANT");
endmodule
