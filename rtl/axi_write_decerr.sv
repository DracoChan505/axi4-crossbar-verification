// Internal write-error endpoint. No address decode or memory side effects.
module axi_write_decerr #(
    parameter int ID_WIDTH = 4,
    parameter int CAPACITY = 4,
    parameter int COUNT_WIDTH = $clog2(CAPACITY + 1)
) (
    input logic clk,
    input logic reset_n,
    input logic awvalid,
    output logic awready,
    input logic [ID_WIDTH-1:0] awid,
    input logic [7:0] awlen,
    input logic wvalid,
    output logic wready,
    input logic wlast,
    output logic bvalid,
    input logic bready,
    output logic [ID_WIDTH-1:0] bid,
    output logic [1:0] bresp
);
    logic aw_space;
    logic record_valid;
    logic record_pop;
    logic [ID_WIDTH-1:0] record_id;
    logic [7:0] record_len;
    logic [7:0] beat_index;
    logic response_space;
    logic [COUNT_WIDTH-1:0] outstanding;
    logic aw_fire;
    logic b_fire;
    logic w_fire;

    initial begin
        assert (ID_WIDTH > 0 && CAPACITY > 0)
            else $fatal(1, "DECERR_PARAMETERS");
    end
    assign awready = reset_n && aw_space && outstanding < COUNT_WIDTH'(CAPACITY);
    assign aw_fire = awvalid && awready;
    assign wready = reset_n && record_valid && response_space;
    assign w_fire = wvalid && wready;
    assign record_pop = w_fire && beat_index == record_len;
    assign b_fire = bvalid && bready;
    assign bresp = 2'b11;

    axi_record_fifo #(.WIDTH(ID_WIDTH + 8), .DEPTH(CAPACITY)) address_records (
        .clk(clk),
        .reset_n(reset_n),
        .push_valid(aw_fire),
        .push_ready(aw_space),
        .push_data({awid, awlen}),
        .pop_valid(record_valid),
        .pop_ready(record_pop),
        .pop_data({record_id, record_len}),
        .count()
    );
    axi_record_fifo #(.WIDTH(ID_WIDTH), .DEPTH(CAPACITY)) responses (
        .clk(clk),
        .reset_n(reset_n),
        .push_valid(record_pop),
        .push_ready(response_space),
        .push_data(record_id),
        .pop_valid(bvalid),
        .pop_ready(bready),
        .pop_data(bid),
        .count()
    );
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            outstanding <= '0;
            beat_index <= '0;
        end
        else begin
            case ({aw_fire, b_fire})
                2'b10: outstanding <= outstanding + 1'b1;
                2'b01: outstanding <= outstanding - 1'b1;
                default: outstanding <= outstanding;
            endcase
            if (record_pop) begin
                beat_index <= '0;
            end
            else if (w_fire) begin
                beat_index <= beat_index + 1'b1;
            end
        end
    end
    assert property (@(posedge clk) disable iff (!reset_n)
        w_fire |-> wlast == (beat_index == record_len))
        else $fatal(1, "DECERR_WLAST");
    assert property (@(posedge clk) disable iff (!reset_n)
        bvalid && !bready |=> bvalid && $stable({bid, bresp}))
        else $fatal(1, "DECERR_B_UNSTABLE");
endmodule
