//      // verilator_coverage annotation
        // Per-ingress write admission. No AXI data or response buffering lives here.
        module axi_write_tracker #(
            parameter int ID_WIDTH = 2,
            parameter int TARGETS = 5,
            parameter int MAX_OUTSTANDING = 2,
            parameter int TARGET_WIDTH = (TARGETS > 1) ? $clog2(TARGETS) : 1,
            parameter int COUNT_WIDTH = $clog2(MAX_OUTSTANDING + 1)
        ) (
 026544     input  logic clk,
 000288     input  logic reset_n,
 001453     input  logic request_valid,
 001059     output logic request_ready,
 000721     input  logic [ID_WIDTH-1:0] request_id,
~000721     input  logic [TARGET_WIDTH-1:0] request_target,
            // A pulse for the upstream B handshake, with the restored original ID.
 001380     input  logic complete_valid,
 000582     input  logic [ID_WIDTH-1:0] complete_id,
 001325     output logic complete_known,
~000598     output logic [TARGET_WIDTH-1:0] complete_target,
 001060     output logic [COUNT_WIDTH-1:0] outstanding
        );
 000311     logic [ID_WIDTH-1:0] ids [MAX_OUTSTANDING];
~000311     logic [TARGET_WIDTH-1:0] targets [MAX_OUTSTANDING];
~000753     logic [COUNT_WIDTH-1:0] counts [MAX_OUTSTANDING];
            integer request_slot;
            integer complete_slot;
            integer free_slot;
            integer allocate_slot;
 001453     logic accept_request;
 001380     logic accept_completion;
        
            initial begin
~000144         assert (ID_WIDTH >= 1 && TARGETS >= 1 && MAX_OUTSTANDING >= 1)
                    else $fatal(1, "TRACKER_PARAMETERS");
                assert (TARGET_WIDTH >= ((TARGETS > 1) ? $clog2(TARGETS) : 1))
                    else $fatal(1, "TRACKER_TARGET_WIDTH");
                assert (COUNT_WIDTH >= $clog2(MAX_OUTSTANDING + 1))
                    else $fatal(1, "TRACKER_COUNT_WIDTH");
            end
        
 268384     always_comb begin
 268384         request_slot = -1;
 268384         complete_slot = -1;
 268384         free_slot = -1;
 536768         for (int i = 0; i < MAX_OUTSTANDING; i++) begin
 208477             if (counts[i] != 0) begin
 105840                 if (ids[i] == request_id) begin
 102637                     request_slot = i;
                        end
 128891                 if (ids[i] == complete_id) begin
 079586                     complete_slot = i;
                        end
                    end
 185197             else if (free_slot < 0) begin
 185197                 free_slot = i;
                    end
                end
 268384         allocate_slot = request_slot >= 0 ? request_slot : free_slot;
 268384         complete_known = reset_n && complete_slot >= 0;
 268384         complete_target = '0;
 188989         if (complete_known) begin
 079395             complete_target = targets[complete_slot];
                end
 268384         request_ready = 0;
 163640         if (reset_n && outstanding < COUNT_WIDTH'(MAX_OUTSTANDING) &&
~163640             int'(request_target) < TARGETS && allocate_slot >= 0) begin
 144242             if (request_slot < 0) begin
 144242                 request_ready = 1;
                    end
 019398             else begin
 019398                 request_ready = targets[request_slot] == request_target;
                    end
                end
 268384         accept_request = request_valid && request_ready;
 268384         accept_completion = complete_valid && complete_known;
            end
        
 026688     always_ff @(posedge clk or negedge reset_n) begin
 025392         if (!reset_n) begin
 001296             outstanding <= '0;
 002592             for (int i = 0; i < MAX_OUTSTANDING; i++) begin
 002592                 ids[i] <= '0;
 002592                 targets[i] <= '0;
 002592                 counts[i] <= '0;
                    end
                end
 025392         else begin
 025392             case ({accept_request, accept_completion})
 001163                 2'b10: outstanding <= outstanding + 1'b1;
 000916                 2'b01: outstanding <= outstanding - 1'b1;
 023313                 default: outstanding <= outstanding;
                    endcase
 050784             for (int i = 0; i < MAX_OUTSTANDING; i++) begin
 050784                 case ({accept_request && allocate_slot == i,
 050784                        accept_completion && complete_slot == i})
 001441                     2'b10: counts[i] <= counts[i] + 1'b1;
 001194                     2'b01: counts[i] <= counts[i] - 1'b1;
 048149                     default: counts[i] <= counts[i];
                        endcase
 049343                 if (accept_request && allocate_slot == i) begin
 001441                     ids[i] <= request_id;
 001441                     targets[i] <= request_target;
                        end
                    end
                end
            end
        
            // These diagnose broken integration; they do not invent a B response.
%000000     property completion_has_record;
%000000         @(posedge clk) disable iff (!reset_n)
%000000         complete_valid |-> complete_known;
            endproperty
            assert property (completion_has_record)
                else $fatal(1, "TRACKER_UNKNOWN_COMPLETION");
        
%000000     property admission_has_capacity;
%000000         @(posedge clk) disable iff (!reset_n)
%000000         accept_request |-> outstanding < COUNT_WIDTH'(MAX_OUTSTANDING);
            endproperty
            assert property (admission_has_capacity)
                else $fatal(1, "TRACKER_OVERFLOW");
        endmodule
        
