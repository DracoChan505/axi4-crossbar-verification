//      // verilator_coverage annotation
 000648 class axi_r_burst;
            bit [DATA_W - 1 : 0] data[$];
            bit [1:0]            resp[$];
            longint unsigned first_cycle, last_cycle;
        endclass
        
        class axi_r_beat extends uvm_object;
            bit [DATA_W - 1 : 0] data;
            bit [1:0]            resp;
            bit                  last;
            longint unsigned cycle, epoch, burst_seq;
            int beat_index;
%000000     `uvm_object_utils(axi_r_beat)
~000634     function new(string name = "axi_r_beat");
 000634         super.new(name);
            endfunction
        endclass
        
        class axi_master_read_monitor extends uvm_monitor;
~000072     `uvm_component_utils(axi_master_read_monitor)
            virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;
            axi_master_read_cfg cfg;
            uvm_analysis_port#(axi_read_item) ar_ap, complete_ap;
            uvm_analysis_port#(axi_r_beat) beat_ap;
 000072     longint unsigned r_serial = 0;
            axi_read_item awaiting_r[$];
            axi_r_burst bursts[$], current;
 000072     longint unsigned cycle = 0, epoch = 0, serial = 0;
 000072     int ar_count = 0, r_count = 0, peak = 0, out_of_order = 0, r_stalled = 0;
 000072     bit in_reset = 1;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
 000072         ar_ap = new("ar_ap", this);
 000072         complete_ap = new("complete_ap", this);
 000072         beat_ap = new("beat_ap", this);
 000072         current = new;
            endfunction
        
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
%000000             `uvm_fatal("VIF", "Read master monitor interface missing")
~000072         if (!uvm_config_db#(axi_master_read_cfg)::get(this, "", "cfg", cfg))
%000000             `uvm_fatal("CONFIG", "Read master monitor config missing")
            endfunction
        
%000000     function bit idle();
%000000         return awaiting_r.size() == 0 && bursts.size() == 0 && current.data.size() == 0;
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 013272         forever begin
 013272             axi_read_item t, e;
 013272             axi_r_burst w;
 013272             axi_r_beat beat_event;
 013272             int idx;
 013272             @(vif.mon);
 013272             cycle++;
~012696             if (!vif.mon.ARESETn) begin
~000504                 if (!in_reset) begin epoch++; in_reset = 1; end
%000000                 awaiting_r.delete(); bursts.delete(); current = new;
%000000                 continue;
                    end
 013272             in_reset = 0;
                    // Check R before processing this edge's AR; same-edge early R is illegal.
 010064             if (vif.mon.RVALID) begin
 002632                 idx = -1;
 004802                 foreach (awaiting_r[i])
 002632                     if (idx < 0 && awaiting_r[i].id == vif.mon.RID)
 002632                         idx = i;
%000000                 if (idx < 0)
%000000                     `uvm_error("R_NO_PENDING", "no AR for observed RVALID")
 001998                 else if (vif.mon.RREADY) begin
 000634                     t = awaiting_r[idx];
 000602                     if (t.data.size() == 0) begin
 000602                         t.data = new[t.beats];
 000602                         t.rresp = new[t.beats];
                            end
 000634                     t.data[t.beat_index] = vif.mon.RDATA;
 000634                     t.rresp[t.beat_index] = vif.mon.RRESP;
 000634                     t.beat_index++;
 000634                     beat_event = axi_r_beat::type_id::create("beat_event");
 000634                     beat_event.data = vif.mon.RDATA;
 000634                     beat_event.resp = vif.mon.RRESP;
 000634                     beat_event.last = vif.mon.RLAST;
 000634                     beat_event.cycle = cycle;
 000634                     beat_event.epoch = epoch;
 000634                     beat_event.burst_seq = r_serial;
 000634                     beat_event.beat_index = current.data.size();
 000634                     beat_ap.write(beat_event);
 000595                     if (vif.mon.RLAST) begin
 000595                         t.r_done = 1;
 000595                         t.r_cycle = cycle;
 000595                         t.resp = vif.mon.RRESP;
 000595                         e = axi_read_item::type_id::create("r_event");
 000595                         e.copy(t);
 000595                         complete_ap.write(e);
 000595                         awaiting_r.delete(idx);
 000595                         r_count++;
 000550                         if (idx != 0) out_of_order++;
                            end
                        end
 001998                 else begin
 001998                     r_stalled++;
                        end
                    end
 011972             if (vif.mon.ARVALID && vif.mon.ARREADY) begin
 000724                 t = axi_read_item::type_id::create("ar_record");
 000724                 t.addr = vif.mon.ARADDR;
 000724                 t.id = vif.mon.ARID;
 000724                 t.beats = int'(vif.mon.ARLEN) + 1;
 000724                 t.size = int'(vif.mon.ARSIZE);
 000724                 t.burst = vif.mon.ARBURST;
 000724                 t.lock = vif.mon.ARLOCK;
 000724                 t.cache = vif.mon.ARCACHE;
 000724                 t.prot = vif.mon.ARPROT;
 000724                 t.qos = vif.mon.ARQOS;
 000724                 t.uid = serial++;
 000724                 t.epoch = epoch;
 000724                 t.ar_cycle = cycle;
 000724                 t.ar_done = 1;
~000724                 if (t.burst != 1 || t.size > $clog2(STRB_W))
%000000                     `uvm_fatal("AR_PROFILE", "unsupported observed profile")
 000724                 awaiting_r.push_back(t);
 000724                 ar_count++;
 000724                 e = axi_read_item::type_id::create("ar_event");
 000724                 e.copy(t);
 000724                 ar_ap.write(e);
                    end
 012552             if (awaiting_r.size() > peak)
 000144                 peak = awaiting_r.size();
~012696             if (awaiting_r.size() > cfg.max_outstanding)
%000000                 `uvm_error("CAPACITY", "observed too many AR outstanding")
                end
            endtask
        endclass
        
