`timescale 1ns/1ps
interface probe_if(input logic clk);
 logic [7:0] drive=0, captured=0;
 clocking cb @(posedge clk);
  default input #1step output #0;
  output drive;
  input captured;
 endclocking
endinterface
module top;
 bit clk=0; always #5 clk=~clk;
 probe_if bus(clk);
 always @(posedge clk) bus.captured <= bus.drive;
 initial begin
  @(bus.cb); bus.cb.drive <= 8'h35;
  @(bus.cb);
  if(bus.cb.captured !== 0) $fatal(1,"CLOCK_SAMPLE_EARLY");
  @(bus.cb);
  if(bus.cb.captured !== 8'h35) $fatal(1,"CLOCK_SAMPLE_LATE");
  $display("CLOCKING_PASS"); $finish;
 end
 initial begin #100; $fatal(1,"TIMEOUT"); end
endmodule
