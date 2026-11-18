`timescale 1ns/1ps
module top;
 bit clk=0,rst=0,valid=0,ready=0; bit [7:0] data=0;
 int errors=0;
 always #5 clk=~clk;
 property hold_payload;
  @(posedge clk) disable iff(!rst)
  valid && !ready |=> valid && $stable(data);
 endproperty
 a_hold: assert property(hold_payload) else begin errors++; $display("EXPECTED_HOLD_ERROR"); end
 initial begin
  @(negedge clk); rst=1; valid=1; data=3;
  repeat(2) @(negedge clk);
  if($test$plusargs("FAULT")) data=4;
  @(negedge clk); ready=1;
  @(negedge clk); valid=0;
  @(negedge clk); valid=1; ready=0;
  @(negedge clk); rst=0; data=8; valid=0;
  @(negedge clk);
  if(errors!=($test$plusargs("FAULT")?1:0)) $fatal(1,"ASSERT_COUNT %0d",errors);
  $display("ASSERTIONS_PASS errors=%0d",errors); $finish;
 end
endmodule
