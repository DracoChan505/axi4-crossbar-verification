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
  if(cov.get_inst_coverage()!=25.0) $fatal(1,"COVER_PARTIAL");
  id=0; stall=1; cov.sample();
  id=1; stall=0; cov.sample();
  id=1; stall=1; cov.sample();
  if(cov.get_inst_coverage()!=100.0) $fatal(1,"COVER_FULL");
  $display("COVERAGE_PASS"); $finish;
 end
endmodule
