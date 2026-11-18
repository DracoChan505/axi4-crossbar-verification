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
  task body();
   use_response_handler(1);
   for(int i=0;i<2;i++) begin
    req=item::type_id::create("req");
    start_item(req);req.tag=i;req.set_transaction_id(i);finish_item(req);
   end
   if(received!=0) `uvm_fatal("EARLY","completion before both submissions accepted")
   wait(received==2);
   if(order[0]!=1 || order[1]!=0) `uvm_fatal("ORDER","wrong response order")
   `uvm_info("RESPONSE_PASS","two accepted, separate out-of-order callbacks matched",UVM_LOW)
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
   fork
    forever begin
     item copy;
     seq_item_port.get_next_item(req);
     copy=item::type_id::create("copy");copy.tag=req.tag;copy.set_id_info(req);
     saved.push_back(copy);
     seq_item_port.item_done();
    end
    begin
     wait(saved.size()==2);
     repeat(3) @(vif.cb);
     for(int i=1;i>=0;i--) begin
      item rsp=item::type_id::create("rsp");
      rsp.tag=saved[i].tag;rsp.set_id_info(saved[i]);
      vif.cb.value <= 8'(rsp.tag+1);
      seq_item_port.put_response(rsp);
      @(vif.cb);
     end
    end
   join
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
   seq s=seq::type_id::create("s");
   phase.raise_objection(this);s.start(sq);phase.drop_objection(this);
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
