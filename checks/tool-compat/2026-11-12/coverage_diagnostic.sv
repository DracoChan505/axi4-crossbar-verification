`timescale 1ns/1ps
module top;
 bit id,stall;
 covergroup cg;
  option.per_instance=1;
  cp_id: coverpoint id {option.weight=0;bins zero={0}; bins one={1};}
  cp_stall: coverpoint stall {option.weight=0;bins no={0}; bins yes={1};}
  pairs: cross cp_id,cp_stall;
 endgroup
 cg cov=new;
 initial begin
  id=0; stall=0; cov.sample();
  $display("PARTIAL=%f",cov.get_inst_coverage());
  id=0; stall=1; cov.sample();
  id=1; stall=0; cov.sample();
  id=1; stall=1; cov.sample();
  $display("FULL=%f",cov.get_inst_coverage());
  $display("COVERAGE_DIAGNOSTIC_ONLY"); $finish;
 end
endmodule
