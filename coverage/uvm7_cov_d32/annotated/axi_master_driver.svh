//      // verilator_coverage annotation
        class axi_master_driver extends uvm_driver#(axi_write_item);
~000072     `uvm_component_utils(axi_master_driver)
            virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
            axi_master_cfg cfg;
            axi_write_item pending[$], active_q[$], awq[$], wq[$];
 000072     longint unsigned cycle = 0, epoch = 0, next_uid = 0;
 000072     int outstanding = 0, reserved = 0, max_seen = 0, pending_peak = 0;
 000072     int accepted = 0, completed = 0, cancelled = 0;
 000072     bit in_reset = 1, aw_on = 0, w_on = 0;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
            endfunction
        
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
%000000             `uvm_fatal("VIF", "missing")
~000072         if (!uvm_config_db#(axi_master_cfg)::get(this, "", "cfg", cfg))
%000000             `uvm_fatal("CONFIG", "missing")
 000072         cfg.validate();
            endfunction
        
 000576     function void clear_state();
 000576         cancelled += pending.size() + active_q.size();
 000576         pending.delete();
 000576         active_q.delete();
 000576         awq.delete();
 000576         wq.delete();
 000576         outstanding = 0;
 000576         reserved = 0;
 000576         aw_on = 0;
 000576         w_on = 0;
            endfunction
        
%000000     function bit idle();
%000000         return pending.size() == 0 && active_q.size() == 0;
            endfunction
        
 000648     task drive_idle();
 000648         vif.AWVALID <= 0;
 000648         vif.WVALID <= 0;
 000648         vif.BREADY <= 0;
            endtask
        
%000000     task run_phase(uvm_phase phase);
                // Asynchronous deassertion of valid, while accounting remains edge-based.
%000000         fork
~000072             forever begin
 000072                 @(negedge vif.ARESETn);
 000072                 drive_idle();
                    end
~013272             forever begin
 013272                 axi_write_item t, c, r;
 013272                 int idx;
 013272                 @(vif.mon);
 013272                 cycle++;
~012696                 if (!vif.mon.ARESETn) begin
~000504                     if (!in_reset) begin
 000072                         epoch++;
 000072                         in_reset = 1;
                            end
%000000                     clear_state();
%000000                     drive_idle();
%000000                     continue;
                        end
 013272                 in_reset = 0;
                        // Responses are interpreted against PRE-edge AW/W completion state.
 010135                 if (vif.mon.BVALID) begin
 002561                     idx = -1;
 004792                     foreach (active_q[i])
 002561                         if (idx < 0 && active_q[i].aw_done && active_q[i].id == vif.mon.BID)
 002561                             idx = i;
~002561                     if (idx < 0)
%000000                         `uvm_fatal("B_NO_PENDING", "response has no accepted AW")
 002561                     t = active_q[idx];
~002561                     if (!t.w_done)
%000000                         `uvm_fatal("EARLY_B", "response precedes W completion")
 001962                     if (vif.mon.BREADY) begin
 000599                         r = axi_write_item::type_id::create("response");
 000599                         r.copy(t);
 000599                         r.set_id_info(t);
 000599                         r.resp = vif.mon.BRESP;
 000599                         r.b_cycle = cycle;
 000599                         seq_item_port.put_response(r);
 000599                         active_q.delete(idx);
 000599                         outstanding--;
 000599                         completed++;
~000599                         if (cfg.trace)
%000000                             `uvm_info("B_DONE", $sformatf("epoch=%0d uid=%0d cycle=%0d id=%0d O=%0d R=%0d", epoch, t.uid, cycle, t.id, outstanding, reserved), UVM_LOW)
                            end
                        end
 011979                 if (aw_on && vif.mon.AWVALID && vif.mon.AWREADY) begin
 000717                     t = awq.pop_front();
 000717                     t.aw_done = 1;
 000717                     t.aw_cycle = cycle;
 000717                     aw_on = 0;
 000717                     outstanding++;
 000717                     reserved--;
~000717                     if (cfg.trace)
%000000                         `uvm_info("AW_ACCEPT", $sformatf("epoch=%0d uid=%0d cycle=%0d id=%0d O=%0d R=%0d", epoch, t.uid, cycle, t.id, outstanding, reserved), UVM_LOW)
                        end
 011908                 if (w_on && vif.mon.WVALID && vif.mon.WREADY) begin
 000788                     t = wq[0];
 000788                     t.beat_index++;
 000788                     w_on = 0;
 000657                     if (t.beat_index == int'(t.beats)) begin
 000657                         t.w_done = 1;
 000657                         t.w_cycle = cycle;
~000657                         if (cfg.trace)
%000000                             `uvm_info("W_COMPLETE", $sformatf("epoch=%0d uid=%0d cycle=%0d id=%0d", epoch, t.uid, cycle, t.id), UVM_LOW)
 000657                         t = wq.pop_front();
                            end
                            else
 000131                         t.w_wait = int'(t.w_gap);
                        end
                        // New tasks are reserved AFTER sampled events; first handshake is next edge.
 011953                 if (pending.size() > 0 && active_q.size() < cfg.max_outstanding) begin
 000743                     t = pending.pop_front();
 000743                     active_q.push_back(t);
 000743                     awq.push_back(t);
 000743                     wq.push_back(t);
 000743                     reserved++;
                        end
 008280                 if (pending.size() < cfg.pending_depth) begin
 008280                     seq_item_port.try_next_item(t);
 007407                     if (t != null) begin
 000873                         string reason = t.invalid_reason();
~000873                         if (reason != "")
%000000                             `uvm_fatal("ITEM_INVALID", reason)
 000873                         c = axi_write_item::type_id::create("owned");
 000873                         c.copy(t);
 000873                         c.set_id_info(t);
 000873                         c.uid = next_uid++;
 000873                         c.epoch = epoch;
 000873                         c.aw_done = 0;
 000873                         c.w_done = 0;
 000873                         c.beat_index = 0;
 000873                         c.aw_wait = int'(c.aw_delay);
 000873                         c.w_wait = int'(c.w_delay);
 000873                         pending.push_back(c);
 000873                         accepted++;
 000873                         seq_item_port.item_done();
                            end
                        end
 011967                 if (!aw_on) begin
 011967                     vif.AWVALID <= 0;
 011139                     if (awq.size() > 0) begin
 000828                         t = awq[0];
 000729                         if (t.aw_wait > 0)
 000099                             t.aw_wait--;
 000729                         else begin
 000729                             vif.AWADDR <= t.addr;
 000729                             vif.AWID <= t.id;
 000729                             vif.AWLEN <= 8'(t.beats - 1);
 000729                             vif.AWSIZE <= 3'(t.size);
 000729                             vif.AWBURST <= t.burst;
 000729                             vif.AWLOCK <= t.lock;
 000729                             vif.AWCACHE <= t.cache;
 000729                             vif.AWPROT <= t.prot;
 000729                             vif.AWQOS <= t.qos;
 000729                             vif.AWVALID <= 1;
 000729                             aw_on = 1;
                                end
                            end
                        end
 010176                 if (!w_on) begin
 010176                     vif.WVALID <= 0;
 008953                     if (wq.size() > 0) begin
 001223                         t = wq[0];
 000827                         if (t.w_wait > 0)
 000396                             t.w_wait--;
 000827                         else begin
 000827                             vif.WDATA <= t.data[t.beat_index];
 000827                             vif.WSTRB <= t.strb[t.beat_index];
 000827                             vif.WLAST <= (t.beat_index == int'(t.beats) - 1);
 000827                             vif.WVALID <= 1;
 000827                             w_on = 1;
                                end
                            end
                        end
 013272                 vif.BREADY <= (cfg.b_stall_period == 0 || (cycle % 64'(cfg.b_stall_period)) >= 64'(cfg.b_stall_cycles));
~012696                 if (outstanding < 0 || reserved < 0 || outstanding + reserved != active_q.size() || active_q.size() > cfg.max_outstanding)
%000000                     `uvm_fatal("CAPACITY", "inconsistent O/R/active")
 012552                 if (outstanding > max_seen)
 000144                     max_seen = outstanding;
 012552                 if (pending.size() > pending_peak)
 000144                     pending_peak = pending.size();
                    end
                join
            endtask
        endclass
        
