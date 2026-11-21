//      // verilator_coverage annotation
        // Internal valid/ready arbitration. Sources hold a selected request until taken.
        // This block selects an index; payload storage belongs to the channel wrapper.
        module axi_rr_arbiter #(
            parameter int PORTS = 4,
            parameter int INDEX_WIDTH = PORTS > 1 ? $clog2(PORTS) : 1
        ) (
 033180     input  logic clk,
 000360     input  logic reset_n,
~000362     input  logic [PORTS-1:0] request,
 001595     input  logic grant_ready,
 001138     output logic grant_valid,
~000671     output logic [INDEX_WIDTH-1:0] grant_index,
~000362     output logic [PORTS-1:0] grant_onehot,
~000362     output logic [PORTS-1:0] request_ready
        );
 000667     logic [INDEX_WIDTH-1:0] next_start;
 000514     logic locked;
~000269     logic [INDEX_WIDTH-1:0] locked_index;
            integer candidate;
        
            initial begin
~000180         assert (PORTS >= 1 && INDEX_WIDTH >= (PORTS > 1 ? $clog2(PORTS) : 1))
                    else $fatal(1, "ARBITER_PARAMETERS");
            end
        
 318300     always_comb begin
 318300         grant_valid = 0;
 318300         grant_index = '0;
 318300         grant_onehot = '0;
 318300         request_ready = '0;
 318300         candidate = 0;
 291400         if (reset_n) begin
 284412             if (locked) begin
 010214                 grant_valid = 1;
 010214                 grant_index = locked_index;
                    end
 284412             else begin
 1137648                 for (int offset = 0; offset < PORTS; offset++) begin
 1137648                     candidate = int'(next_start) + offset;
 1048557                     if (candidate >= PORTS) begin
 553782                         candidate = candidate - PORTS;
                            end
~1125083                     if (!grant_valid && request[candidate]) begin
 012565                         grant_valid = 1;
 012565                         grant_index = INDEX_WIDTH'(candidate);
                            end
                        end
                    end
 271847             if (grant_valid) begin
 021728                 grant_onehot[grant_index] = 1;
 021728                 request_ready[grant_index] = grant_ready;
                    end
                end
            end
        
 033360     always_ff @(posedge clk or negedge reset_n) begin
 031740         if (!reset_n) begin
 001620             next_start <= '0;
 001620             locked <= 0;
 001620             locked_index <= '0;
                end
 029552         else if (grant_valid && grant_ready) begin
~001258             if (int'(grant_index) == PORTS - 1) begin
~000317                 next_start <= '0;
                    end
 001258             else begin
 001258                 next_start <= grant_index + 1'b1;
                    end
 001338             locked <= 0;
                end
 029552         else if (grant_valid) begin
 001184             locked <= 1;
 001184             locked_index <= grant_index;
                end
            end
        
%000000     property selected_source_stays_valid;
%000000         @(posedge clk) disable iff (!reset_n)
%000000         locked |-> request[locked_index];
            endproperty
            assert property (selected_source_stays_valid)
                else $fatal(1, "ARBITER_REQUEST_WITHDRAWN");
        
%000000     property stalled_selection_stays;
%000000         @(posedge clk) disable iff (!reset_n)
%000000         grant_valid && !grant_ready |=> grant_valid && $stable(grant_index);
            endproperty
            assert property (stalled_selection_stays)
                else $fatal(1, "ARBITER_UNSTABLE_GRANT");
        endmodule
        
