//      // verilator_coverage annotation
        // Static, inclusive, non-overlapping 4 KiB-aligned address windows.
        // The top-level must hold map_* constant while traffic is in flight.
        module axi_address_decode #(
            parameter int ADDR_WIDTH = 32,
            parameter int TARGETS = 4,
            parameter int TARGET_WIDTH = $clog2(TARGETS + 1)
        ) (
~000721     input  logic [ADDR_WIDTH-1:0] address,
~000144     input  logic [TARGETS-1:0][ADDR_WIDTH-1:0] map_base,
~000144     input  logic [TARGETS-1:0][ADDR_WIDTH-1:0] map_limit,
~000144     output logic map_valid,
%000000     output logic decode_error,
~000721     output logic [TARGET_WIDTH-1:0] target
        );
            initial begin
~000144         assert (ADDR_WIDTH >= 12 && TARGETS >= 1 &&
                        TARGET_WIDTH >= $clog2(TARGETS + 1))
                    else $fatal(1, "DECODE_PARAMETERS");
            end
        
 005184     always_comb begin
 005184         map_valid = 1;
 020736         for (int i = 0; i < TARGETS; i++) begin
~020736             if (map_base[i] > map_limit[i] ||
~020736                 map_base[i][11:0] != 12'h000 || map_limit[i][11:0] != 12'hfff) begin
%000000                 map_valid = 0;
                    end
 031104             for (int j = 0; j < i; j++) begin
~031104                 if (map_base[i] <= map_limit[j] && map_base[j] <= map_limit[i]) begin
%000000                     map_valid = 0;
                        end
                    end
                end
 005184         decode_error = 1;
 005184         target = TARGET_WIDTH'(TARGETS);
~005184         if (map_valid) begin
 020736             for (int i = 0; i < TARGETS; i++) begin
 015552                 if (address >= map_base[i] && address <= map_limit[i]) begin
 005184                     decode_error = 0;
 005184                     target = TARGET_WIDTH'(i);
                        end
                    end
                end
            end
        endmodule
        
