// Internal read-error endpoint. Accepts AR, returns DECERR R burst, no memory.
module axi_read_decerr #(
    parameter int ID_WIDTH   = 4,
    parameter int DATA_WIDTH = 32,
    parameter int CAPACITY   = 4,
    parameter int COUNT_WIDTH = $clog2(CAPACITY + 1)
) (
    input  logic clk,
    input  logic reset_n,
    input  logic                   arvalid,
    output logic                   arready,
    input  logic [ID_WIDTH-1:0]    arid,
    input  logic [7:0]             arlen,
    output logic                   rvalid,
    input  logic                   rready,
    output logic [ID_WIDTH-1:0]    rid,
    output logic [DATA_WIDTH-1:0]  rdata,
    output logic [1:0]            rresp,
    output logic                   rlast
);
    logic record_space;
    logic record_valid;
    logic record_pop;
    logic [ID_WIDTH-1:0] record_id;
    logic [7:0]          record_len;
    logic [7:0]          beat_index;
    logic outstanding_space;
    logic [COUNT_WIDTH-1:0] outstanding;
    logic ar_fire;
    logic r_fire;
    logic record_pop_pulse;

    initial begin
        assert (ID_WIDTH > 0 && DATA_WIDTH > 0 && CAPACITY > 0)
            else $fatal(1, "DECERR_READ_PARAMETERS");
    end

    assign ar_fire = arvalid && arready;
    assign r_fire  = rvalid && rready;
    assign arready = reset_n && record_space && outstanding < COUNT_WIDTH'(CAPACITY);
    assign rvalid  = reset_n && record_valid;
    assign rid     = record_id;
    assign rdata   = '0;
    assign rresp   = 2'b11;
    assign rlast   = (beat_index == record_len);
    assign record_pop_pulse = r_fire && rlast;

    axi_record_fifo #(.WIDTH(ID_WIDTH + 8), .DEPTH(CAPACITY)) records (
        .clk(clk), .reset_n(reset_n),
        .push_valid(ar_fire), .push_ready(record_space),
        .push_data({arid, arlen}),
        .pop_valid(record_valid), .pop_ready(record_pop_pulse),
        .pop_data({record_id, record_len}), .count()
    );

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            outstanding <= '0;
            beat_index   <= '0;
        end
        else begin
            case ({ar_fire, record_pop_pulse})
                2'b10:   outstanding <= outstanding + 1'b1;
                2'b01:   outstanding <= outstanding - 1'b1;
                default: outstanding <= outstanding;
            endcase
            if (record_pop_pulse)
                beat_index <= '0;
            else if (r_fire)
                beat_index <= beat_index + 1'b1;
        end
    end

    assert property (@(posedge clk) disable iff (!reset_n)
        r_fire |-> rlast == (beat_index == record_len))
        else $fatal(1, "DECERR_READ_RLAST");
    assert property (@(posedge clk) disable iff (!reset_n)
        rvalid && !rready |=> rvalid && $stable({rid, rresp, rlast}))
        else $fatal(1, "DECERR_READ_R_UNSTABLE");
endmodule
