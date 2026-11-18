`timescale 1ns/1ps
module top;
 int aw=0,w=0,b=0;
 task run_workers;
  fork
   forever begin #2; aw++; end
   forever begin #3; w++; end
   forever begin #4; b++; end
  join
 endtask
 initial begin
  int a0,w0,b0;
  fork
   run_workers();
   begin #13; end
  join_any
  disable fork;
  a0=aw; w0=w; b0=b;
  if(a0!=6 || w0!=4 || b0!=3) $fatal(1,"WORKER_COUNTS");
  #10;
  if(aw!=a0 || w!=w0 || b!=b0) $fatal(1,"WORKER_NOT_STOPPED");
  fork
   run_workers();
   begin #5; end
  join_any
  disable fork;
  if(aw!=a0+2 || w!=w0+1 || b!=b0+1) $fatal(1,"RESTART");
  $display("CONCURRENCY_PASS"); $finish;
 end
 initial begin #100; $fatal(1,"TIMEOUT"); end
endmodule
