// Static, inclusive, non-overlapping 4 KiB-aligned address windows.
// The top-level must hold map_* constant while traffic is in flight.
module axi_address_decode #(
    parameter int ADDR_WIDTH = 32,
    parameter int TARGETS = 4,
    parameter int TARGET_WIDTH = $clog2(TARGETS + 1)
) (
    input  logic [ADDR_WIDTH-1:0] address,
    input  logic [TARGETS-1:0][ADDR_WIDTH-1:0] map_base,
    input  logic [TARGETS-1:0][ADDR_WIDTH-1:0] map_limit,
    output logic map_valid,
    output logic decode_error,
    output logic [TARGET_WIDTH-1:0] target
);
    initial begin
        assert (ADDR_WIDTH >= 12 && TARGETS >= 1 &&
                TARGET_WIDTH >= $clog2(TARGETS + 1))
            else $fatal(1, "DECODE_PARAMETERS");
    end

    always_comb begin
        map_valid = 1;
        for (int i = 0; i < TARGETS; i++) begin
            if (map_base[i] > map_limit[i] ||
                map_base[i][11:0] != 12'h000 || map_limit[i][11:0] != 12'hfff) begin
                map_valid = 0;
            end
            for (int j = 0; j < i; j++) begin
                if (map_base[i] <= map_limit[j] && map_base[j] <= map_limit[i]) begin
                    map_valid = 0;
                end
            end
        end
        decode_error = 1;
        target = TARGET_WIDTH'(TARGETS);
        if (map_valid) begin
            for (int i = 0; i < TARGETS; i++) begin
                if (address >= map_base[i] && address <= map_limit[i]) begin
                    decode_error = 0;
                    target = TARGET_WIDTH'(i);
                end
            end
        end
    end
endmodule
