//      // verilator_coverage annotation
        // AR driver and R receiver for the read master agent.
        class axi_master_read_driver extends uvm_driver#(axi_read_item);
~000072     `uvm_component_utils(axi_master_read_driver)
            virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;
            axi_master_read_cfg cfg;
            axi_read_item pending[$], active_q[$], arq[$], rq[$];
 000072     longint unsigned cycle = 0, epoch = 0, next_uid = 0;
 000072     int outstanding = 0, reserved = 0;
 000072     int accepted = 0, completed = 0, cancelled = 0;
 000072     bit in_reset = 1, ar_on = 0;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
            endfunction
        
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
%000000             `uvm_fatal("VIF", "Read master interface missing")
~000072         if (!uvm_config_db#(axi_master_read_cfg)::get(this, "", "cfg", cfg))
%000000             `uvm_fatal("CONFIG", "Read master config missing")
 000072         cfg.validate();
            endfunction
        
 000576     function void clear_state();
 000576         cancelled += pending.size() + active_q.size();
 000576         pending.delete(); active_q.delete(); arq.delete(); rq.delete();
 000576         outstanding = 0; reserved = 0; ar_on = 0;
            endfunction
        
%000000     function bit idle();
%000000         return pending.size() == 0 && active_q.size() == 0;
            endfunction
        
 000648     task drive_idle();
 000648         vif.ARVALID <= 0;
 000648         vif.RREADY  <= 0;
            endtask
        
%000000     task run_phase(uvm_phase phase);
%000000         fork
~000072             forever begin
 000072                 @(negedge vif.ARESETn);
 000072                 drive_idle();
                    end
~013272             forever begin
 013272                 axi_read_item t, c, r;
 013272                 int idx;
 013272                 @(vif.mon);
 013272                 cycle++;
~012696                 if (!vif.mon.ARESETn) begin
~000504                     if (!in_reset) begin epoch++; in_reset = 1; end
%000000                     clear_state(); drive_idle(); continue;
                        end
 013272                 in_reset = 0;
                        // Capture R beats. RLAST completes the transaction.
                        // No r_on gate: simply check RVALID && RREADY and rq has data.
 012062                 if (vif.mon.RVALID && vif.mon.RREADY && rq.size() > 0) begin
 000634                     t = rq[0];
 000602                     if (t.data.size() == 0) begin
 000602                         t.data = new[t.beats];
 000602                         t.rresp = new[t.beats];
                            end
 000634                     t.data[t.beat_index] = vif.mon.RDATA;
 000634                     t.rresp[t.beat_index] = vif.mon.RRESP;
 000634                     t.beat_index++;
 000595                     if (vif.mon.RLAST) begin
 000595                         t.r_done  = 1;
 000595                         t.r_cycle = cycle;
 000595                         t.resp    = vif.mon.RRESP;
 000595                         idx = -1;
 001118                         foreach (active_q[i])
 000595                             if (idx < 0 && active_q[i].ar_done &&
                                        active_q[i].id == vif.mon.RID)
 000595                                 idx = i;
~000595                         if (idx < 0)
%000000                             `uvm_fatal("R_NO_PENDING", "RLAST has no pending AR")
 000595                         r = axi_read_item::type_id::create("response");
 000595                         r.copy(active_q[idx]);
 000595                         r.set_id_info(active_q[idx]);
 000595                         r.resp    = vif.mon.RRESP;
 000595                         r.r_cycle = cycle;
 000595                         seq_item_port.put_response(r);
 000595                         active_q.delete(idx);
 000595                         outstanding--;
 000595                         completed++;
 000595                         void'(rq.pop_front());
                            end
                        end
                        // AR handshake
 011972                 if (ar_on && vif.mon.ARVALID && vif.mon.ARREADY) begin
 000724                     t = arq.pop_front();
 000724                     t.ar_done  = 1;
 000724                     t.ar_cycle = cycle;
 000724                     ar_on = 0;
 000724                     outstanding++;
 000724                     reserved--;
                        end
                        // Pull new items from sequencer
 010015                 if (pending.size() < cfg.pending_depth) begin
 010015                     seq_item_port.try_next_item(t);
 009039                     if (t != null) begin
 000976                         string reason = t.invalid_reason();
~000976                         if (reason != "")
%000000                             `uvm_fatal("ITEM_INVALID", reason)
 000976                         c = axi_read_item::type_id::create("owned");
 000976                         c.copy(t);
 000976                         c.set_id_info(t);
 000976                         c.uid       = next_uid++;
 000976                         c.epoch     = epoch;
 000976                         c.ar_done   = 0;
 000976                         c.r_done    = 0;
 000976                         c.beat_index = 0;
 000976                         c.ar_wait   = int'(c.ar_delay);
 000976                         pending.push_back(c);
 000976                         accepted++;
 000976                         seq_item_port.item_done();
                            end
                        end
                        // Promote pending → active
 011957                 if (pending.size() > 0 &&
 000739                     active_q.size() < cfg.max_outstanding) begin
 000739                     t = pending.pop_front();
 000739                     active_q.push_back(t);
 000739                     arq.push_back(t);
 000739                     rq.push_back(t);
 000739                     reserved++;
                        end
                        // Drive AR
 011972                 if (!ar_on) begin
 011972                     vif.ARVALID <= 0;
 011156                     if (arq.size() > 0) begin
 000816                         t = arq[0];
 000739                         if (t.ar_wait > 0)
 000077                             t.ar_wait--;
 000739                         else begin
 000739                             vif.ARADDR  <= t.addr;
 000739                             vif.ARID    <= t.id;
 000739                             vif.ARLEN   <= 8'(t.beats - 1);
 000739                             vif.ARSIZE  <= 3'(t.size);
 000739                             vif.ARBURST <= t.burst;
 000739                             vif.ARLOCK  <= t.lock;
 000739                             vif.ARCACHE <= t.cache;
 000739                             vif.ARPROT  <= t.prot;
 000739                             vif.ARQOS   <= t.qos;
 000739                             vif.ARVALID <= 1;
 000739                             ar_on = 1;
                                end
                            end
                        end
                        // Drive RREADY: always grant when stall policy allows, if we have outstanding ARs
 013272                 begin
 013272                     int period = cfg.r_stall_period;
 013272                     int stalls = cfg.r_stall_cycles;
 013272                     logic rready_val;
~013272                     rready_val = (period == 0) ||
 013272                                  (cycle % 64'(period)) >= 64'(stalls);
                            // Only assert RREADY if we have outstanding transactions to consume
 006493                     if (rq.size() > 0)
 006203                         vif.RREADY <= rready_val;
                            else
 006493                         vif.RREADY <= 0;
                        end
                    end
                join
            endtask
        endclass
        
