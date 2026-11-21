//      // verilator_coverage annotation
        // Internal write-error endpoint. No address decode or memory side effects.
        module axi_write_decerr #(
            parameter int ID_WIDTH = 4,
            parameter int CAPACITY = 4,
            parameter int COUNT_WIDTH = $clog2(CAPACITY + 1)
        ) (
 003318     input logic clk,
 000036     input logic reset_n,
%000000     input logic awvalid,
 000036     output logic awready,
%000000     input logic [ID_WIDTH-1:0] awid,
%000000     input logic [7:0] awlen,
%000000     input logic wvalid,
%000000     output logic wready,
%000000     input logic wlast,
%000000     output logic bvalid,
 000036     input logic bready,
%000000     output logic [ID_WIDTH-1:0] bid,
~000018     output logic [1:0] bresp
        );
 000036     logic aw_space;
%000000     logic record_valid;
%000000     logic record_pop;
%000000     logic [ID_WIDTH-1:0] record_id;
%000000     logic [7:0] record_len;
%000000     logic [7:0] beat_index;
 000036     logic response_space;
%000000     logic [COUNT_WIDTH-1:0] outstanding;
%000000     logic aw_fire;
%000000     logic b_fire;
%000000     logic w_fire;
        
            initial begin
~000018         assert (ID_WIDTH > 0 && CAPACITY > 0)
                    else $fatal(1, "DECERR_PARAMETERS");
            end
~029140     assign awready = reset_n && aw_space && outstanding < COUNT_WIDTH'(CAPACITY);
~031830     assign aw_fire = awvalid && awready;
~031830     assign wready = reset_n && record_valid && response_space;
~033881     assign w_fire = wvalid && wready;
~033881     assign record_pop = w_fire && beat_index == record_len;
~031830     assign b_fire = bvalid && bready;
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
 003336     always_ff @(posedge clk or negedge reset_n) begin
 003174         if (!reset_n) begin
 000162             outstanding <= '0;
 000162             beat_index <= '0;
                end
 003174         else begin
 003174             case ({aw_fire, b_fire})
%000000                 2'b10: outstanding <= outstanding + 1'b1;
%000000                 2'b01: outstanding <= outstanding - 1'b1;
 003174                 default: outstanding <= outstanding;
                    endcase
%000000             if (record_pop) begin
%000000                 beat_index <= '0;
                    end
~003174             else if (w_fire) begin
%000000                 beat_index <= beat_index + 1'b1;
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
        
