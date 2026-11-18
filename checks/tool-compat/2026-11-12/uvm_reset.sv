`timescale 1ns/1ps
interface tick_if(input bit clk);
 logic [7:0] value=0;
 clocking cb @(posedge clk);
  default input #1step output #0;
  output value;
 endclocking
endinterface
package probe_pkg;
 import uvm_pkg::*;
 `include "uvm_macros.svh"
 class item extends uvm_sequence_item;
  int tag;
  `uvm_object_utils(item)
  function new(string name="item");super.new(name);endfunction
 endclass
 class seq extends uvm_sequence#(item);
  int received=0;
  int order[$];
  `uvm_object_utils(seq)
  function new(string name="seq");super.new(name);endfunction
  function void response_handler(uvm_sequence_item response);
   item r;
   if(!$cast(r,response)) `uvm_fatal("CAST","response type")
   if(r.get_transaction_id()!=r.tag) `uvm_fatal("ROUTE","transaction ID mismatch")
   order.push_back(r.tag); received++;
  endfunction
  bit restart_mode=0;
  task body();
   use_response_handler(1);
   req=item::type_id::create("req");
   start_item(req);req.tag=restart_mode?10:0;req.set_transaction_id(req.tag);finish_item(req);
   wait(received==1);
   if(!restart_mode) `uvm_fatal("STALE","old sequence completed")
   if(order[0]!=10) `uvm_fatal("ROUTE","new sequence mismatch")
  endtask
 endclass
 class driver extends uvm_driver#(item);
  virtual tick_if vif;
  item saved[$];
  `uvm_component_utils(driver)
  function new(string name,uvm_component parent);super.new(name,parent);endfunction
  function void build_phase(uvm_phase phase);
   if(!uvm_config_db#(virtual tick_if)::get(this,"","vif",vif)) `uvm_fatal("VIF","missing")
  endfunction
  task run_phase(uvm_phase phase);
   forever begin
    item copy;
    seq_item_port.get_next_item(req);
    copy=item::type_id::create("copy");copy.tag=req.tag;copy.set_id_info(req);
    seq_item_port.item_done();
    if(copy.tag==10) begin
     repeat(2) @(vif.cb);
     seq_item_port.put_response(copy);
    end
   end
  endtask
 endclass
 class probe_test extends uvm_test;
  uvm_sequencer#(item) sq;driver dr;
  `uvm_component_utils(probe_test)
  function new(string name,uvm_component parent);super.new(name,parent);endfunction
  function void build_phase(uvm_phase phase);
   sq=new("sq",this);dr=driver::type_id::create("dr",this);
  endfunction
  function void connect_phase(uvm_phase phase);dr.seq_item_port.connect(sq.seq_item_export);endfunction
  task run_phase(uvm_phase phase);
   seq old_seq=seq::type_id::create("old_seq");
   seq new_seq=seq::type_id::create("new_seq");
   phase.raise_objection(this);
   fork
    old_seq.start(sq);
    begin
     #30;
     sq.stop_sequences();
    end
   join
   if(old_seq.get_sequence_state()!=UVM_STOPPED) `uvm_fatal("STOP","sequence not stopped")
   if(old_seq.received!=0) `uvm_fatal("STALE","old completion")
   new_seq.restart_mode=1;new_seq.start(sq);
   if(new_seq.received!=1) `uvm_fatal("NEW","new completion missing")
   `uvm_info("RESET_SEQUENCE_PASS","blocked old sequence stopped; new sequence completes",UVM_LOW)
   phase.drop_objection(this);
  endtask
 endclass
endpackage
module top;
 import uvm_pkg::*;import probe_pkg::*;
 bit clk=0;always #5 clk=~clk;
 tick_if bus(clk);
 initial begin
  uvm_config_db#(virtual tick_if)::set(null,"uvm_test_top.dr","vif",bus);
  run_test("probe_test");
 end
 initial begin #1000; $fatal(1,"WATCHDOG"); end
endmodule
