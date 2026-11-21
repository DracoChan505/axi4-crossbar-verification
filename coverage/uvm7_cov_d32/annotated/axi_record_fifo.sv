//      // verilator_coverage annotation
        // Registered storage, no fall-through and no full-cycle pop/push bypass.
        module axi_record_fifo #(
            parameter int WIDTH = 8,
            parameter int DEPTH = 2,
            parameter int COUNT_WIDTH = $clog2(DEPTH + 1),
            parameter int PTR_WIDTH = DEPTH > 1 ? $clog2(DEPTH) : 1
        ) (
 026544     input logic clk,
 000288     input logic reset_n,
~001453     input logic push_valid,
 000557     output logic push_ready,
~000721     input logic [WIDTH-1:0] push_data,
~000968     output logic pop_valid,
~001574     input logic pop_ready,
~000968     output logic [WIDTH-1:0] pop_data,
~001237     output logic [COUNT_WIDTH-1:0] count
        );
~000396     logic [WIDTH-1:0] storage [DEPTH];
~000744     logic [PTR_WIDTH-1:0] write_ptr;
~000671     logic [PTR_WIDTH-1:0] read_ptr;
~001453     logic push;
~001574     logic pop;
        
            initial begin
~000144         assert (WIDTH > 0 && DEPTH > 0)
                    else $fatal(1, "FIFO_PARAMETERS");
            end
~224243     assign push_ready = reset_n && count < COUNT_WIDTH'(DEPTH);
~206092     assign pop_valid = reset_n && count != 0;
~206239     assign pop_data = pop_valid ? storage[read_ptr] : '0;
~247072     assign push = push_valid && push_ready;
~287789     assign pop = pop_valid && pop_ready;
        
 026688     always_ff @(posedge clk or negedge reset_n) begin
 025392         if (!reset_n) begin
 001296             write_ptr <= '0;
 001296             read_ptr <= '0;
 001296             count <= '0;
                end
 025392         else begin
~023951             if (push) begin
~001441                 storage[write_ptr] <= push_data;
~000744                 if (int'(write_ptr) == DEPTH - 1) begin
~000697                     write_ptr <= '0;
                        end
~000744                 else begin
~000744                     write_ptr <= write_ptr + 1'b1;
                        end
                    end
~024081             if (pop) begin
~000671                 if (int'(read_ptr) == DEPTH - 1) begin
~000640                     read_ptr <= '0;
                        end
~000671                 else begin
~000671                     read_ptr <= read_ptr + 1'b1;
                        end
                    end
 025392             case ({push, pop})
~001271                 2'b10: count <= count + 1'b1;
~001141                 2'b01: count <= count - 1'b1;
 022980                 default: count <= count;
                    endcase
                end
            end
        endmodule
        
