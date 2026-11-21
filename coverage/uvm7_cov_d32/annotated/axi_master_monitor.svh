//      // verilator_coverage annotation
 001305 class axi_w_burst;
            bit [DATA_W - 1 : 0] data[$];
            bit [STRB_W - 1 : 0] strb[$];
            longint unsigned first_cycle, last_cycle;
        endclass
        
        class axi_w_beat extends uvm_object;
            bit [DATA_W - 1 : 0] data;
            bit [STRB_W - 1 : 0] strb;
            bit last;
            longint unsigned cycle, epoch, burst_seq;
            int beat_index;
%000000     `uvm_object_utils(axi_w_beat)
        
~000788     function new(string name = "axi_w_beat");
 000788         super.new(name);
            endfunction
        endclass
        
        class axi_master_monitor extends uvm_monitor;
~000072     `uvm_component_utils(axi_master_monitor)
            virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
            axi_master_cfg cfg;
            uvm_analysis_port#(axi_write_item) aw_ap, write_ap, complete_ap;
            uvm_analysis_port#(axi_w_beat) beat_ap;
 000072     longint unsigned w_serial = 0;
            axi_write_item awaiting_w[$], awaiting_b[$];
            axi_w_burst bursts[$], current;
 000072     longint unsigned cycle = 0, epoch = 0, serial = 0;
 000072     int aw_count = 0, w_count = 0, b_count = 0, peak = 0;
 000072     int aw_first = 0, w_first = 0, same_edge = 0, b_stalled = 0, out_of_order = 0;
            int size_hits[8], length_hits[4];
            int cov_size, cov_length;
            covergroup observed_writes with function sample(int sample_size, int sample_length);
                cp_size : coverpoint sample_size {
~000657             bins supported[] = {[0 : $clog2(STRB_W)]};
                }
                cp_length : coverpoint sample_length {
 000576             bins single = {1};
 000081             bins short_burst = {[2 : 16]};
%000000             bins long_burst = {[17 : 255]};
%000000             bins maximum = {256};
                }
            endgroup
 000072     bit in_reset = 1;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
 000072         aw_ap = new("aw_ap", this);
 000072         write_ap = new("write_ap", this);
 000072         complete_ap = new("complete_ap", this);
 000072         observed_writes = new;
 000072         beat_ap = new("beat_ap", this);
            endfunction
        
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
%000000             `uvm_fatal("VIF", "missing")
~000072         if (!uvm_config_db#(axi_master_cfg)::get(this, "", "cfg", cfg))
%000000             `uvm_fatal("CONFIG", "missing")
 000072         current = new;
            endfunction
        
%000000     function bit idle();
%000000         return awaiting_w.size() == 0 && awaiting_b.size() == 0 && bursts.size() == 0 && current.data.size() == 0;
            endfunction
        
 000657     function void check_bytes(axi_write_item t, axi_w_burst w);
 000657         longint unsigned block_start, first, step;
 000657         bit [STRB_W - 1 : 0] legal;
~000657         if (w.data.size() != t.beats) begin
%000000             `uvm_error("W_LENGTH", "AWLEN and observed WLAST disagree")
%000000             return;
                end
 000657         step = 64'(1) << t.size;
 000657         block_start = (64'(t.addr) / step) * step;
 000767         for (int i = 0; i < int'(t.beats); i++) begin
 000767             legal = '0;
 000767             first = (i == 0) ? 64'(t.addr) : block_start;
 003068             for (longint unsigned a = block_start; a < block_start + step; a++)
~003068                 if (a >= first)
 003068                     legal[int'(a % STRB_W)] = 1;
~000767             if ((w.strb[i] & ~legal) != '0)
%000000                 `uvm_error("WSTRB", "byte outside legal address set")
 000767             block_start += step;
                end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 013272         forever begin
 013272             axi_write_item t, e;
 013272             axi_w_burst w;
 013272             axi_w_beat beat_event;
 013272             int idx;
 013272             @(vif.mon);
 013272             cycle++;
~012696             if (!vif.mon.ARESETn) begin
~000504                 if (!in_reset) begin
 000072                     epoch++;
 000072                     in_reset = 1;
                        end
%000000                 awaiting_w.delete();
%000000                 awaiting_b.delete();
%000000                 bursts.delete();
%000000                 current = new;
%000000                 continue;
                    end
 013272             in_reset = 0;
                    // Check B before processing this edge's AW/W; same-edge early B is illegal.
 010135             if (vif.mon.BVALID) begin
 002561                 idx = -1;
 004661                 foreach (awaiting_b[i])
 002561                     if (idx < 0 && awaiting_b[i].id == vif.mon.BID)
 002561                         idx = i;
%000000                 if (idx < 0)
%000000                     `uvm_error("B_NO_PENDING", "no AW for observed BVALID")
%000000                 else if (!awaiting_b[idx].w_done)
%000000                     `uvm_error("EARLY_B", "W not complete before BVALID")
 001962                 else if (vif.mon.BREADY) begin
 000599                     t = awaiting_b[idx];
~000591                     if (idx != 0)
%000008                         out_of_order++;
 000599                     t.resp = vif.mon.BRESP;
 000599                     t.b_cycle = cycle;
 000599                     e = axi_write_item::type_id::create("b_event");
 000599                     e.copy(t);
 000599                     complete_ap.write(e);
 000599                     awaiting_b.delete(idx);
 000599                     b_count++;
                        end
 001962                 if (!vif.mon.BREADY)
 001962                     b_stalled++;
                    end
 011979             if (vif.mon.AWVALID && vif.mon.AWREADY) begin
 000717                 t = axi_write_item::type_id::create("aw_record");
 000717                 t.addr = vif.mon.AWADDR;
 000717                 t.id = vif.mon.AWID;
 000717                 t.beats = int'(vif.mon.AWLEN) + 1;
 000717                 t.size = int'(vif.mon.AWSIZE);
 000717                 t.burst = vif.mon.AWBURST;
 000717                 t.lock = vif.mon.AWLOCK;
 000717                 t.cache = vif.mon.AWCACHE;
 000717                 t.prot = vif.mon.AWPROT;
 000717                 t.qos = vif.mon.AWQOS;
 000717                 t.uid = serial++;
 000717                 t.epoch = epoch;
 000717                 t.aw_cycle = cycle;
 000717                 t.aw_done = 1;
~000717                 if (t.burst != 1 || t.size > $clog2(STRB_W))
%000000                     `uvm_fatal("AW_PROFILE", "unsupported observed profile")
~000717                 if (((64'(t.addr) / (64'(1) << t.size) * (64'(1) << t.size) + 64'(t.beats) * (64'(1) << t.size) - 1) >> 12) != (64'(t.addr) >> 12))
%000000                     `uvm_error("BOUNDARY", "observed crossing burst")
 000717                 awaiting_w.push_back(t);
 000717                 awaiting_b.push_back(t);
 000717                 aw_count++;
 000717                 e = axi_write_item::type_id::create("aw_event");
 000717                 e.copy(t);
 000717                 aw_ap.write(e);
                    end
 011908             if (vif.mon.WVALID && vif.mon.WREADY) begin
 000788                 beat_event = axi_w_beat::type_id::create("beat_event");
 000788                 beat_event.data = vif.mon.WDATA;
 000788                 beat_event.strb = vif.mon.WSTRB;
 000788                 beat_event.last = vif.mon.WLAST;
 000788                 beat_event.cycle = cycle;
 000788                 beat_event.epoch = epoch;
 000788                 beat_event.burst_seq = w_serial;
 000788                 beat_event.beat_index = current.data.size();
 000788                 beat_ap.write(beat_event);
 000657                 if (vif.mon.WLAST)
 000657                     w_serial++;
 000668                 if (current.data.size() == 0)
 000668                     current.first_cycle = cycle;
 000788                 current.data.push_back(vif.mon.WDATA);
 000788                 current.strb.push_back(vif.mon.WSTRB);
 000788                 w_count++;
~000788                 if (current.data.size() > 256)
%000000                     `uvm_fatal("W_LENGTH", "more than 256 beats without WLAST")
~000788                 if (awaiting_w.size() > bursts.size()) begin
 000788                     t = awaiting_w[bursts.size()];
~000788                     if ((current.data.size() == t.beats) != vif.mon.WLAST)
%000000                         `uvm_error("WLAST", "wrong WLAST position")
                        end
 000657                 if (vif.mon.WLAST) begin
 000657                     current.last_cycle = cycle;
 000657                     bursts.push_back(current);
 000657                     current = new;
                        end
                    end
 000657             while (awaiting_w.size() > 0 && bursts.size() > 0) begin
 000657                 t = awaiting_w.pop_front();
 000657                 w = bursts.pop_front();
 000657                 check_bytes(t, w);
 000657                 t.data = new[w.data.size()];
 000657                 t.strb = new[w.strb.size()];
~000767                 foreach (t.data[i]) begin
 000767                     t.data[i] = w.data[i];
 000767                     t.strb[i] = w.strb[i];
                        end
 000657                 t.w_done = (w.data.size() == t.beats);
 000657                 t.w_cycle = w.last_cycle;
 000657                 cov_size = int'(t.size);
 000657                 cov_length = int'(t.beats);
 000657                 observed_writes.sample(cov_size, cov_length);
 000657                 size_hits[t.size]++;
 000576                 if (t.beats == 1)
 000576                     length_hits[0]++;
 000081                 else if (t.beats <= 16)
 000081                     length_hits[1]++;
%000000                 else if (t.beats < 256)
%000000                     length_hits[2]++;
                        else
%000000                     length_hits[3]++;
%000000                 if (w.first_cycle < t.aw_cycle)
%000000                     w_first++;
~000657                 else if (w.first_cycle > t.aw_cycle)
 000657                     aw_first++;
                        else
%000000                     same_edge++;
 000657                 e = axi_write_item::type_id::create("w_event");
 000657                 e.copy(t);
 000657                 write_ap.write(e);
                    end
 012552             if (awaiting_b.size() > peak)
 000144                 peak = awaiting_b.size();
~012696             if (awaiting_b.size() > cfg.max_outstanding)
%000000                 `uvm_error("CAPACITY", "observed too many AW outstanding")
~012696             if (awaiting_w.size() + bursts.size() > cfg.monitor_limit)
%000000                 `uvm_fatal("MON_LIMIT", "unpaired queue limit")
                end
            endtask
        endclass
        
