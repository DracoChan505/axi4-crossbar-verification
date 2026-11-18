`timescale 1ns/1ps
package master_test_pkg;
 import uvm_pkg::*;import axi_master_pkg::*;
 `include "uvm_macros.svh"
 class test_plan;
  axi_write_item requests[$];
  int pattern[int unsigned],sparse[int unsigned];
 endclass
 class master_sequence extends uvm_sequence#(axi_write_item);
  `uvm_object_utils(master_sequence)
  test_plan plan;
  int responses=0;
  int tags[$];
  int response_status=0;
  function new(string name="master_sequence");super.new(name);endfunction
  function void response_handler(uvm_sequence_item response);
   axi_write_item t;
   if(!$cast(t,response))`uvm_fatal("RESP_TYPE","bad response type")
   if(t.get_transaction_id()<0 || t.get_transaction_id()>=plan.requests.size())`uvm_fatal("RESP_TAG","bad request tag")
   if(t.addr!=plan.requests[t.get_transaction_id()].addr)`uvm_error("RESP_MATCH","wrong task response")
   foreach(tags[i])if(tags[i]==t.get_transaction_id())`uvm_error("RESP_DUP","duplicate completion")
   if(t.resp!=2'(response_status))`uvm_error("RESP_STATUS","unexpected BRESP")
   tags.push_back(t.get_transaction_id());responses++;
  endfunction
  task body();
   use_response_handler(1);
   foreach(plan.requests[i])begin
    req=axi_write_item::type_id::create("request");req.copy(plan.requests[i]);req.set_transaction_id(i);
    start_item(req);finish_item(req);
   end
   wait(responses==plan.requests.size());
  endtask
 endclass
 // Independent byte-address oracle. It does not call allowed_mask/fill_pattern.
 class byte_scoreboard extends uvm_subscriber#(axi_write_item);
  `uvm_component_utils(byte_scoreboard)
  test_plan plan;
  byte unsigned memory[longint unsigned];
  int checked=0;bit seen[longint unsigned];
  function new(string name,uvm_component parent);super.new(name,parent);endfunction
  function void write(axi_write_item t);
   axi_write_item e;int found=-1;longint unsigned start,step,base;
   foreach(plan.requests[k])if(plan.requests[k].addr==t.addr)found=k;
   if(found<0)begin `uvm_error("UNEXPECTED_WRITE","unknown address") return;end
   e=plan.requests[found];
   if(seen.exists(64'(t.addr)))`uvm_error("DUP_WRITE","duplicate observed burst")
   seen[64'(t.addr)]=1;
   if(t.id!=e.id || t.size!=e.size || t.beats!=e.beats || t.burst!=1 || t.lock!=0 || t.cache!=2 || t.prot!=2 || t.qos!=e.qos)
    `uvm_error("AW_FIELDS","observed request differs from test intent")
   if(t.data.size()!=e.beats)begin `uvm_error("DATA_COUNT","wrong beat count") return;end
   step=64'(1)<<e.size;start=(64'(e.addr)/step)*step;
   for(int i=0;i<int'(e.beats);i++)begin
    bit [STRB_W-1:0] mask='0;
    base=((start)/STRB_W)*STRB_W;
    for(longint unsigned a=start;a<start+step;a++)begin
     int lane=int'(a%STRB_W);bit enabled;
     enabled=(a>=64'(e.addr));
     if(plan.sparse[found]==1 && a%2==0)enabled=0;
     if(plan.sparse[found]==2)enabled=0;
     if(enabled)begin
      byte unsigned expected_byte=8'(a^64'(plan.pattern[found]));
      mask[lane]=1;
      if(t.data[i][8*lane+:8]!=expected_byte)`uvm_error("BYTE_DATA",$sformatf("addr=%h got=%h expected=%h",a,t.data[i][8*lane+:8],expected_byte))
      memory[a]=expected_byte;
     end
    end
    if(t.strb[i]!=mask)`uvm_error("BYTE_MASK",$sformatf("addr=%h beat=%0d got=%b expected=%b",t.addr,i,t.strb[i],mask))
    start+=step;
   end
   checked++;
  endfunction
  function void reset_transactions();seen.delete();endfunction
  function void clear_memory();memory.delete();endfunction
 endclass
 // Test-only responder, not the production Slave agent. Independent beat FIFO
 // enables W-before-AW. Bytes commit when both address and data are available.
 class response_fixture extends uvm_component;
  `uvm_component_utils(response_fixture)
  virtual axi_write_if vif;
  axi_write_item writes[$],responses[$];
  typedef struct packed {bit [DATA_W-1:0] data;bit [STRB_W-1:0] strb;bit last;} beat_t;
  beat_t beats[$];
  byte unsigned memory[longint unsigned];
  int cycle=0,aw_count=0,w_count=0,b_count=0,committed=0;
  int aw_period=0,w_period=0,delay_cycles=4,resp_status=0;
  bit hold_aw=0,hold_w=0,hold_b=0,reorder=0,enabled=1;
  axi_write_item returning=null;
  function new(string name,uvm_component parent);super.new(name,parent);endfunction
  function void build_phase(uvm_phase phase);
   if(!uvm_config_db#(virtual axi_write_if)::get(this,"","vif",vif))`uvm_fatal("VIF","fixture")
  endfunction
  function void clear_memory();
   if(vif.ARESETn && (writes.size()!=0 || responses.size()!=0 || returning!=null || beats.size()!=0))`uvm_fatal("CLEAR_BUSY","clear with active transactions")
   memory.delete();
  endfunction
  task run_phase(uvm_phase phase);
   forever begin
    axi_write_item t;beat_t bt;int selected;
    @(vif.mon);cycle++;
    if(!enabled)continue;
    if(!vif.mon.ARESETn)begin
     writes.delete();responses.delete();beats.delete();returning=null;
     vif.AWREADY<=0;vif.WREADY<=0;vif.BVALID<=0;continue;
    end
    if(returning!=null && vif.mon.BVALID && vif.mon.BREADY)begin
     returning=null;vif.BVALID<=0;b_count++;
    end
    if(vif.mon.AWVALID && vif.mon.AWREADY)begin
     t=axi_write_item::type_id::create("fixture_aw");t.addr=vif.mon.AWADDR;t.id=vif.mon.AWID;
     t.size=int'(vif.mon.AWSIZE);t.beats=int'(vif.mon.AWLEN)+1;t.aw_cycle=64'(cycle);
     writes.push_back(t);responses.push_back(t);aw_count++;
    end
    if(vif.mon.WVALID && vif.mon.WREADY)begin
     bt='{vif.mon.WDATA,vif.mon.WSTRB,vif.mon.WLAST};beats.push_back(bt);w_count++;
    end
    while(writes.size()>0 && beats.size()>0)begin
     longint unsigned step,a,base;
     t=writes[0];bt=beats.pop_front();step=64'(1)<<t.size;
     a=(t.beat_index==0)?64'(t.addr):(64'(t.addr)/step+64'(t.beat_index))*step;
     base=(a/STRB_W)*STRB_W;
     for(int lane=0;lane<STRB_W;lane++)if(bt.strb[lane])begin memory[base+64'(lane)]=bt.data[8*lane+:8];committed++;end
     t.beat_index++;
     if(bt.last!=(t.beat_index==int'(t.beats)))`uvm_fatal("FIXTURE_WLAST","data length mismatch")
     if(bt.last)begin t.w_done=1;t.w_cycle=64'(cycle);t=writes.pop_front();end
    end
    if(returning==null && !hold_b)begin
     selected=-1;
     foreach(responses[i])begin
      bit earlier_same=0;int latency;
      for(int j=0;j<i;j++)if(responses[j].id==responses[i].id)earlier_same=1;
      latency=delay_cycles+((reorder && responses[i].id==0)?35:0);
      if(!earlier_same && responses[i].w_done && 64'(cycle)>=responses[i].w_cycle+64'(latency))begin
       if(selected<0 || reorder)selected=i;
      end
     end
     if(selected>=0)begin
      returning=responses[selected];responses.delete(selected);
      vif.BID<=returning.id;vif.BRESP<=2'(resp_status);vif.BVALID<=1;
     end
    end
    vif.AWREADY<= !hold_aw && (aw_period==0 || cycle%aw_period==0);
    vif.WREADY<= !hold_w && (w_period==0 || cycle%w_period==0);
   end
  endtask
 endclass
 class expected_error_catcher extends uvm_report_catcher;
  string allowed[$];int hits=0;int counts[string];
  function new(string name="catcher");super.new(name);endfunction
  function action_e catch();
   if(get_severity()==UVM_ERROR)foreach(allowed[i])if(get_id()==allowed[i])begin
    hits++;counts[get_id()]++;set_severity(UVM_INFO);return THROW;
   end
   return THROW;
  endfunction
 endclass
 class master_test extends uvm_test;
  `uvm_component_utils(master_test)
  axi_master_agent agent;axi_master_cfg cfg;response_fixture fixture;byte_scoreboard score;
  virtual axi_write_if vif;
  test_plan plan;master_sequence seq;
  string scenario="smoke";
  int max_out=2;
  expected_error_catcher catcher;
  function new(string name,uvm_component parent);super.new(name,parent);endfunction
  function void build_phase(uvm_phase phase);
   void'($value$plusargs("CASE=%s",scenario));void'($value$plusargs("MAX_OUT=%d",max_out));
   cfg=axi_master_cfg::type_id::create("cfg");cfg.max_outstanding=max_out;cfg.trace=$test$plusargs("TRACE");
   if(scenario.substr(0,3)=="neg_")cfg.active=0;
   if(scenario=="backpressure")begin cfg.b_stall_period=13;cfg.b_stall_cycles=10;end
   if(scenario=="reset_bvalid")begin cfg.b_stall_period=10000;cfg.b_stall_cycles=9999;end
   uvm_config_db#(axi_master_cfg)::set(this,"agent","cfg",cfg);
   if(!uvm_config_db#(virtual axi_write_if)::get(this,"","vif",vif))`uvm_fatal("VIF","test")
   uvm_config_db#(virtual axi_write_if)::set(this,"*","vif",vif);
   agent=axi_master_agent::type_id::create("agent",this);
   fixture=response_fixture::type_id::create("fixture",this);
   fixture.enabled=cfg.active;
   score=byte_scoreboard::type_id::create("score",this);
   plan=new;score.plan=plan;
  endfunction
  function void connect_phase(uvm_phase phase);if(cfg.active)agent.monitor.write_ap.connect(score.analysis_export);endfunction
  function void add(longint unsigned address,int sz,int n,int id,int pat=37,int sparse=0,int ad=0,int wd=0,int gap=0);
   axi_write_item t=axi_write_item::type_id::create("planned");
   int k=plan.requests.size();
   t.addr=ADDR_W'(address);t.size=sz;t.beats=n;t.id=ID_W'(id);
   t.aw_delay=ad;t.w_delay=wd;t.w_gap=gap;t.qos=4'(k%16);
   t.fill_pattern(pat,sparse);plan.requests.push_back(t);plan.pattern[k]=pat;plan.sparse[k]=sparse;
  endfunction
  task cycles(int n);repeat(n)@(vif.mon);endtask
  task run_sequence();
   seq=master_sequence::type_id::create("seq");seq.plan=plan;seq.response_status=fixture.resp_status;
   seq.start(agent.sequencer);cycles(3);
  endtask
  task negative_case();
   catcher=new;uvm_report_cb::add(null,catcher);
   if(scenario=="neg_orphan" || scenario=="neg_duplicate")catcher.allowed.push_back("B_NO_PENDING");
   else if(scenario=="neg_early")catcher.allowed.push_back("EARLY_B");
   else if(scenario=="neg_last")catcher.allowed.push_back("WLAST");
   else if(scenario=="neg_bstable")catcher.allowed.push_back("B_STABILITY");
   else if(scenario=="neg_awstable")catcher.allowed.push_back("AW_STABILITY");
   else if(scenario=="neg_wstable")catcher.allowed.push_back("W_STABILITY");
   else if(scenario=="neg_strb")catcher.allowed.push_back("WSTRB");
   else `uvm_fatal("CASE","unknown negative case")
   vif.AWVALID<=0;vif.WVALID<=0;vif.BREADY<=0;
   vif.BVALID<=0;vif.AWREADY<=1;vif.WREADY<=1;
   cycles(2);
   if(scenario=="neg_orphan" || scenario=="neg_early" || scenario=="neg_duplicate")vif.BREADY<=1;
   if(scenario=="neg_awstable")begin
    vif.AWREADY<=0;vif.AWVALID<=1;vif.AWADDR<=32'h1000;
    cycles(1);vif.AWADDR<=32'h2000;cycles(1);
   end else if(scenario=="neg_wstable")begin
    vif.WREADY<=0;vif.WVALID<=1;vif.WDATA<=0;
    cycles(1);vif.WDATA<=1;cycles(1);
   end else if(scenario=="neg_orphan")begin
    vif.BID<=0;vif.BVALID<=1;cycles(1);vif.BVALID<=0;
   end else begin
    vif.AWADDR<=32'h1000;vif.AWID<=0;vif.AWLEN<=0;
    vif.AWSIZE<=((scenario=="neg_strb")?0:2);vif.AWBURST<=1;vif.AWVALID<=1;
    cycles(1);vif.AWVALID<=0;
    if(scenario=="neg_early")begin
     // B presented on exactly the edge of the final W transfer must fail.
     vif.WDATA<=0;vif.WSTRB<=0;vif.WLAST<=1;vif.WVALID<=1;
     vif.BVALID<=1;vif.BID<=0;
     cycles(1);vif.BVALID<=0;vif.WVALID<=0;
    end else if(scenario=="neg_strb")begin
     vif.WLAST<=1;vif.WVALID<=1;vif.WSTRB<='1;
     cycles(1);vif.WVALID<=0;
    end else if(scenario=="neg_last")begin
     vif.WLAST<=0;vif.WVALID<=1;vif.WSTRB<=0;
     cycles(1);vif.WVALID<=0;
    end else begin
     vif.WLAST<=1;vif.WVALID<=1;vif.WSTRB<=0;
     cycles(1);vif.WVALID<=0;
     cycles(1);vif.BVALID<=1;vif.BID<=0;vif.BRESP<=0;
     if(scenario=="neg_duplicate")begin
      cycles(2);vif.BVALID<=0;
     end else begin cycles(1);vif.BRESP<=2;cycles(2);end
    end
   end
   cycles(3);
   if(catcher.hits!=1)`uvm_fatal("MISSED_FAULT","expected check did not fire")
   `uvm_info("EXPECTED_DETECTION",$sformatf("case=%s hits=%0d",scenario,catcher.hits),UVM_LOW)
  endtask
  task run_phase(uvm_phase phase);
   phase.raise_objection(this);
   wait(vif.ARESETn);cycles(2);
   if(!cfg.active)begin negative_case();end
   else begin
    if(scenario=="smoke")add('h1000,2,1,0);
    else if(scenario=="w_first")begin add('h1001,2,4,0,37,0,12,0);end
    else if(scenario=="aw_first")add('h1001,1,5,0,37,0,0,12);
    else if(scenario=="bursts")begin
     add('h1001,0,4,0);add('h2001,1,3,1);add('h3001,2,2,2);
     add('h4003,1,2,3);add('h4ffd,2,1,0);add('h5ffa,1,3,1);
     add('h6000,2,256,2);add('h7001,2,31,3,51,1);add('h8000,2,3,0,0,2);
    end else if(scenario=="same_id")begin
     fixture.delay_cycles=20;repeat(6)add('h1000+plan.requests.size()*64,2,3,0);
    end else if(scenario=="reorder")begin
     fixture.reorder=1;add('h1000,2,2,0);add('h2000,2,2,1);add('h3000,2,2,0);add('h4000,2,2,1);
    end else if(scenario=="backpressure")begin
     fixture.aw_period=4;fixture.w_period=3;fixture.delay_cycles=7;
     for(int i=0;i<8;i++)add('h1001+i*256,i%3,7,i%4,37+i,i%3, i%3, (i+1)%3,i%2);
    end else if(scenario=="error_resp")begin fixture.resp_status=2;add('h1000,2,3,0);end
    else if(scenario=="random")begin
     for(int i=0;i<48;i++)begin
      int sz=$urandom_range(0,$clog2(STRB_W));int n=$urandom_range(1,16);
      add('h1000+i*256+64'($urandom_range(0,STRB_W-1)),sz,n,$urandom_range(0,(1<<ID_W)-1),$urandom_range(0,255),$urandom_range(0,2),$urandom_range(0,4),$urandom_range(0,4),$urandom_range(0,2));
     end
     fixture.aw_period=3;fixture.w_period=2;fixture.reorder=1;
    end else if(scenario=="reset_aw" || scenario=="reset_w" || scenario=="reset_b" || scenario=="reset_bvalid" || scenario=="reset_queued")begin
     if(scenario=="reset_aw" || scenario=="reset_queued")fixture.hold_w=1;
     if(scenario=="reset_b")fixture.hold_b=1;
     add('h1000,2,32,0,37,0,0,0,1);
     if(scenario=="reset_queued")repeat(5)add('h1000+plan.requests.size()*256,2,8,0);
    end else if(scenario=="invalid_item")begin
     axi_write_item t=axi_write_item::type_id::create("invalid");
     t.addr='hffd;t.size=2;t.beats=2;t.fill_pattern(1);
     if(t.invalid_reason()=="")`uvm_fatal("VALIDATION","crossing not rejected")
     t.addr='h1000;t.beats=1;t.fill_pattern(1);t.size=0;t.strb[0]='1;
     if(t.invalid_reason()=="")`uvm_fatal("VALIDATION","illegal strobe not rejected")
     add('h1000,2,1,0);
    end else `uvm_fatal("CASE","unknown case")
    if(scenario.substr(0,5)=="reset_")begin
     seq=master_sequence::type_id::create("old_seq");seq.plan=plan;
     fork
      seq.start(agent.sequencer);
      begin wait(!vif.ARESETn);end
     join
     wait(vif.ARESETn);cycles(3);
     if(seq.responses!=0)`uvm_error("RESET_RESPONSE","cancelled task completed")
     if(!agent.driver.idle() || !agent.monitor.idle())`uvm_error("RESET_STATE","stale state")
     if(scenario!="reset_aw" && scenario!="reset_queued" && fixture.memory.num()==0)`uvm_error("RESET_MEMORY","committed bytes lost")
     // Only committed fixture bytes are checked here, without claiming a full
     // crossbar reference-memory reset test.
     foreach(fixture.memory[a])if(fixture.memory[a]!=8'(a^37))`uvm_error("RESET_BYTE","retained byte wrong")
     fixture.hold_w=0;fixture.hold_b=0;cfg.b_stall_period=0;score.reset_transactions();
     plan=new;score.plan=plan;add('h9000,2,2,1);run_sequence();
    end else run_sequence();
    if(score.checked!=((scenario=="reset_b" || scenario=="reset_bvalid")?2:plan.requests.size()))`uvm_error("SCORE_COUNT",$sformatf("checked=%0d expected=%0d",score.checked,plan.requests.size()))
    if(!agent.driver.idle() || !agent.monitor.idle())`uvm_error("NOT_DRAINED","queues not empty")
    foreach(score.memory[a])if(!fixture.memory.exists(a) || fixture.memory[a]!=score.memory[a])`uvm_error("MEMORY","fixture differs from byte oracle")
    if(scenario=="w_first" && agent.monitor.w_first==0)`uvm_error("SCENARIO_MISSED","W-first not exercised")
    if(scenario=="aw_first" && agent.monitor.aw_first==0)`uvm_error("SCENARIO_MISSED","AW-first not exercised")
    if(scenario=="same_id" && agent.driver.pending_peak<2)`uvm_error("SCENARIO_MISSED","pending queue never full")
    if(scenario=="smoke" && agent.monitor.same_edge==0)`uvm_error("SCENARIO_MISSED","same-edge AW/W missing")
    if(scenario=="same_id" && max_out>=2 && agent.monitor.peak<2)`uvm_error("SCENARIO_MISSED","two outstanding not exercised")
    if(scenario=="reorder" && max_out>=2 && agent.monitor.out_of_order==0)`uvm_error("SCENARIO_MISSED","reorder not exercised")
    if(scenario=="backpressure" && agent.monitor.b_stalled==0)`uvm_error("SCENARIO_MISSED","B stall not exercised")
    `uvm_info("COVER_BINS",$sformatf("sizes=%0d,%0d,%0d,%0d lengths=%0d,%0d,%0d,%0d",agent.monitor.size_hits[0],agent.monitor.size_hits[1],agent.monitor.size_hits[2],agent.monitor.size_hits[3],agent.monitor.length_hits[0],agent.monitor.length_hits[1],agent.monitor.length_hits[2],agent.monitor.length_hits[3]),UVM_LOW)
    fixture.clear_memory();score.clear_memory();
    if(fixture.memory.num()!=0 || score.memory.num()!=0)`uvm_error("CLEAR","explicit clear failed")
    `uvm_info("COUNTERS",$sformatf("case=%s aw=%0d w=%0d b=%0d peak=%0d pending_peak=%0d aw_first=%0d w_first=%0d same=%0d reorder=%0d b_stall=%0d",scenario,agent.monitor.aw_count,agent.monitor.w_count,agent.monitor.b_count,agent.monitor.peak,agent.driver.pending_peak,agent.monitor.aw_first,agent.monitor.w_first,agent.monitor.same_edge,agent.monitor.out_of_order,agent.monitor.b_stalled),UVM_LOW)
   end
   if(uvm_report_server::get_server().get_severity_count(UVM_ERROR)!=0 || uvm_report_server::get_server().get_severity_count(UVM_FATAL)!=0)
    begin `uvm_fatal("CHECK_FAILED","unexpected errors") return; end
   `uvm_info("CHECK_PASS",$sformatf("case=%s completed",scenario),UVM_LOW)
   phase.drop_objection(this);
  endtask
 endclass
endpackage
