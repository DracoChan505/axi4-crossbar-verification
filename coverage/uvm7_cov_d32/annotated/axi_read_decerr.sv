//      // verilator_coverage annotation
        // Internal read-error endpoint. Accepts AR, returns DECERR R burst, no memory.
        module axi_read_decerr #(
            parameter int ID_WIDTH   = 4,
            parameter int DATA_WIDTH = 32,
            parameter int CAPACITY   = 4,
            parameter int COUNT_WIDTH = $clog2(CAPACITY + 1)
        ) (
 003318     input  logic clk,
 000036     input  logic reset_n,
%000000     input  logic                   arvalid,
 000036     output logic                   arready,
%000000     input  logic [ID_WIDTH-1:0]    arid,
%000000     input  logic [7:0]             arlen,
%000000     output logic                   rvalid,
 000036     input  logic                   rready,
%000000     output logic [ID_WIDTH-1:0]    rid,
%000000     output logic [DATA_WIDTH-1:0]  rdata,
~000018     output logic [1:0]            rresp,
~000018     output logic                   rlast
        );
 000036     logic record_space;
%000000     logic record_valid;
%000000     logic record_pop;
%000000     logic [ID_WIDTH-1:0] record_id;
%000000     logic [7:0]          record_len;
%000000     logic [7:0]          beat_index;
%000000     logic outstanding_space;
%000000     logic [COUNT_WIDTH-1:0] outstanding;
%000000     logic ar_fire;
%000000     logic r_fire;
%000000     logic record_pop_pulse;
        
            initial begin
~000018         assert (ID_WIDTH > 0 && DATA_WIDTH > 0 && CAPACITY > 0)
                    else $fatal(1, "DECERR_READ_PARAMETERS");
            end
        
~031830     assign ar_fire = arvalid && arready;
~031830     assign r_fire  = rvalid && rready;
~029140     assign arready = reset_n && record_space && outstanding < COUNT_WIDTH'(CAPACITY);
~031830     assign rvalid  = reset_n && record_valid;
            assign rid     = record_id;
            assign rdata   = '0;
            assign rresp   = 2'b11;
            assign rlast   = (beat_index == record_len);
~031830     assign record_pop_pulse = r_fire && rlast;
        
            axi_record_fifo #(.WIDTH(ID_WIDTH + 8), .DEPTH(CAPACITY)) records (
                .clk(clk), .reset_n(reset_n),
                .push_valid(ar_fire), .push_ready(record_space),
                .push_data({arid, arlen}),
                .pop_valid(record_valid), .pop_ready(record_pop_pulse),
                .pop_data({record_id, record_len}), .count()
            );
        
 003336     always_ff @(posedge clk or negedge reset_n) begin
 003174         if (!reset_n) begin
 000162             outstanding <= '0;
 000162             beat_index   <= '0;
                end
 003174         else begin
 003174             case ({ar_fire, record_pop_pulse})
%000000                 2'b10:   outstanding <= outstanding + 1'b1;
%000000                 2'b01:   outstanding <= outstanding - 1'b1;
 003174                 default: outstanding <= outstanding;
                    endcase
%000000             if (record_pop_pulse)
%000000                 beat_index <= '0;
~003174             else if (r_fire)
%000000                 beat_index <= beat_index + 1'b1;
                end
            end
        
            assert property (@(posedge clk) disable iff (!reset_n)
                r_fire |-> rlast == (beat_index == record_len))
                else $fatal(1, "DECERR_READ_RLAST");
            assert property (@(posedge clk) disable iff (!reset_n)
                rvalid && !rready |=> rvalid && $stable({rid, rresp, rlast}))
                else $fatal(1, "DECERR_READ_R_UNSTABLE");
        endmodule
        
