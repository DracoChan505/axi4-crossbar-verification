// Registered storage, no fall-through and no full-cycle pop/push bypass.
module axi_record_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 2,
    parameter int COUNT_WIDTH = $clog2(DEPTH + 1),
    parameter int PTR_WIDTH = DEPTH > 1 ? $clog2(DEPTH) : 1
) (
    input logic clk,
    input logic reset_n,
    input logic push_valid,
    output logic push_ready,
    input logic [WIDTH-1:0] push_data,
    output logic pop_valid,
    input logic pop_ready,
    output logic [WIDTH-1:0] pop_data,
    output logic [COUNT_WIDTH-1:0] count
);
    logic [WIDTH-1:0] storage [DEPTH];
    logic [PTR_WIDTH-1:0] write_ptr;
    logic [PTR_WIDTH-1:0] read_ptr;
    logic push;
    logic pop;

    initial begin
        assert (WIDTH > 0 && DEPTH > 0)
            else $fatal(1, "FIFO_PARAMETERS");
    end
    assign push_ready = reset_n && count < COUNT_WIDTH'(DEPTH);
    assign pop_valid = reset_n && count != 0;
    assign pop_data = pop_valid ? storage[read_ptr] : '0;
    assign push = push_valid && push_ready;
    assign pop = pop_valid && pop_ready;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_ptr <= '0;
            read_ptr <= '0;
            count <= '0;
        end
        else begin
            if (push) begin
                storage[write_ptr] <= push_data;
                if (int'(write_ptr) == DEPTH - 1) begin
                    write_ptr <= '0;
                end
                else begin
                    write_ptr <= write_ptr + 1'b1;
                end
            end
            if (pop) begin
                if (int'(read_ptr) == DEPTH - 1) begin
                    read_ptr <= '0;
                end
                else begin
                    read_ptr <= read_ptr + 1'b1;
                end
            end
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
