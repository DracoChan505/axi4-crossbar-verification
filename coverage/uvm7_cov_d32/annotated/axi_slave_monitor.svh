//      // verilator_coverage annotation
        class axi_slave_monitor extends uvm_monitor;
~000072     `uvm_component_utils(axi_slave_monitor)
            virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
            axi_slave_cfg cfg;
            uvm_analysis_port#(axi_slave_observation) events;
            protected axi_slave_observation awaiting_w[$];
            protected axi_slave_observation awaiting_b[$];
            protected axi_slave_observed_burst bursts[$];
            protected axi_slave_observed_burst current;
 000072     protected longint unsigned cycle = 0;
 000072     protected longint unsigned epoch = 0;
 000072     protected longint unsigned next_serial = 0;
 000072     protected bit in_reset = 1;
 000072     protected bit aw_held = 0;
 000072     protected bit w_held = 0;
 000072     protected bit b_held = 0;
            protected logic [ADDR_W+ID_W+25-1:0] held_aw;
            protected logic [DATA_W+STRB_W:0] held_w;
            protected logic [ID_W+1:0] held_b;
 000072     int aw_count = 0;
 000072     int write_count = 0;
 000072     int b_count = 0;
 000072     int beat_count = 0;
 000072     int cancelled = 0;
 000072     int peak = 0;
 000072     int reordered = 0;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
 000072         events = new("events", this);
 000072         current = new;
            endfunction
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif) ||
%000000             !uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg)) begin
%000000             `uvm_fatal("SM_CONFIG", "Monitor requires interface and configuration")
                end
 000072         cfg.validate();
            endfunction
%000000     function bit idle();
%000000         return awaiting_w.size() == 0 && awaiting_b.size() == 0 && bursts.size() == 0 && current.data.size() == 0;
            endfunction
 000610     function void check_burst(axi_slave_observation item, axi_slave_observed_burst burst);
 000610         longint unsigned block_address;
 000610         longint unsigned byte_address;
 000610         bit [STRB_W-1:0] legal;
~000610         if (burst.data.size() != int'(item.len) + 1) begin
%000000             `uvm_error("SM_W_LENGTH", "Observed WLAST/burst length disagrees with AWLEN")
                end
~000663         foreach (burst.data[beat]) begin
 000663             block_address = ((64'(item.address) >> item.size) + 64'(beat)) << item.size;
 000663             legal = '0;
 002652             for (int offset = 0; offset < (1 << item.size); offset++) begin
 002652                 byte_address = block_address + 64'(offset);
~002652                 if (byte_address >= 64'(item.address)) begin
 002652                     legal[int'(byte_address % STRB_W)] = 1;
                        end
                    end
~000663             if ((burst.strb[beat] & ~legal) != '0) begin
%000000                 `uvm_error("SM_WSTRB", "Byte enable outside this transfer")
                    end
                end
            endfunction
%000000     task run_phase(uvm_phase phase);
%000000         axi_slave_observation item;
%000000         axi_slave_observation event_copy;
%000000         axi_slave_observed_burst burst;
%000000         logic [ADDR_W+ID_W+25-1:0] aw_payload;
%000000         logic [DATA_W+STRB_W:0] w_payload;
%000000         logic [ID_W+1:0] b_payload;
%000000         longint unsigned final_address;
%000000         int match_index;
 013272         forever begin
 013272             @(vif.mon);
 013272             cycle++;
~012696             if (!vif.mon.ARESETn) begin
~000504                 if (!in_reset) begin
 000072                     epoch++;
 000072                     item = new;
 000072                     item.epoch = epoch;
 000072                     item.cancelled_aw = awaiting_b.size();
 000072                     cancelled += awaiting_b.size();
 000072                     events.write(item.snapshot(SLAVE_RESET, cycle));
                        end
%000000                 in_reset = 1;
%000000                 awaiting_w.delete();
%000000                 awaiting_b.delete();
%000000                 bursts.delete();
%000000                 current = new;
%000000                 aw_held = 0;
%000000                 w_held = 0;
%000000                 b_held = 0;
%000000                 continue;
                    end
 013272             in_reset = 0;
 013272             aw_payload = {vif.mon.AWADDR, vif.mon.AWID, vif.mon.AWLEN, vif.mon.AWSIZE,
 013272                           vif.mon.AWBURST, vif.mon.AWLOCK, vif.mon.AWCACHE, vif.mon.AWPROT, vif.mon.AWQOS};
 013272             w_payload = {vif.mon.WDATA, vif.mon.WSTRB, vif.mon.WLAST};
 013272             b_payload = {vif.mon.BID, vif.mon.BRESP};
~012696             if (aw_held && (!vif.mon.AWVALID || aw_payload !== held_aw)) begin
%000000                 `uvm_error("SM_AW_STABILITY", "AW changed before handshake")
                    end
~012696             if (w_held && (!vif.mon.WVALID || w_payload !== held_w)) begin
%000000                 `uvm_error("SM_W_STABILITY", "W changed before handshake")
                    end
~012696             if (b_held && (!vif.mon.BVALID || b_payload !== held_b)) begin
%000000                 `uvm_error("SM_B_STABILITY", "B changed before handshake")
                    end
 013272             aw_held = vif.mon.AWVALID && !vif.mon.AWREADY;
 013272             w_held = vif.mon.WVALID && !vif.mon.WREADY;
 013272             b_held = vif.mon.BVALID && !vif.mon.BREADY;
 013272             held_aw = aw_payload;
 013272             held_w = w_payload;
 013272             held_b = b_payload;
                    // B must refer to AW and final W from earlier sampling edges.
 012077             if (vif.mon.BVALID) begin
 000619                 match_index = -1;
 000995                 foreach (awaiting_b[i]) begin
 000619                     if (match_index < 0 && awaiting_b[i].id == vif.mon.BID) begin
 000619                         match_index = i;
                            end
                        end
~000619                 if (match_index < 0) begin
%000000                     `uvm_error("SM_ORPHAN_B", "No accepted AW matches BID")
                        end
 000619                 else begin
 000619                     item = awaiting_b[match_index];
~000619                     if (!item.write_done || item.aw_cycle >= cycle || item.w_cycle >= cycle) begin
%000000                         `uvm_error("SM_EARLY_B", "Response precedes AW/final W completion")
                            end
 000605                     if (vif.mon.BREADY) begin
 000605                         item.response = vif.mon.BRESP;
 000605                         item.b_cycle = cycle;
 000605                         event_copy = item.snapshot(SLAVE_B, cycle);
 000605                         events.write(event_copy);
 000605                         awaiting_b.delete(match_index);
 000605                         b_count++;
 000581                         if (match_index != 0) begin
 000024                             reordered++;
                                end
                            end
                        end
                    end
 012048             if (vif.mon.AWVALID && vif.mon.AWREADY) begin
 000648                 item = new;
 000648                 item.epoch = epoch;
 000648                 item.serial = next_serial++;
 000648                 item.aw_cycle = cycle;
 000648                 item.address = vif.mon.AWADDR;
 000648                 item.id = vif.mon.AWID;
 000648                 item.len = vif.mon.AWLEN;
 000648                 item.size = vif.mon.AWSIZE;
 000648                 item.attr = {vif.mon.AWSIZE, vif.mon.AWBURST, vif.mon.AWLOCK,
 000648                              vif.mon.AWCACHE, vif.mon.AWPROT, vif.mon.AWQOS};
~000648                 if (vif.mon.AWBURST != 1 || vif.mon.AWLOCK || int'(item.size) > $clog2(STRB_W)) begin
%000000                     `uvm_error("SM_AW_PROFILE", "Expected supported INCR non-exclusive profile")
                        end
 000648                 final_address = ((64'(item.address) >> item.size) + 64'(item.len) + 1) << item.size;
 000648                 final_address--;
~000648                 if ((final_address >> 12) != (64'(item.address) >> 12) || (final_address >> ADDR_W) != 0) begin
%000000                     `uvm_error("SM_BOUNDARY", "Burst crosses 4KB or address width")
                        end
 000648                 awaiting_w.push_back(item);
 000648                 awaiting_b.push_back(item);
 000648                 events.write(item.snapshot(SLAVE_AW, cycle));
 000648                 aw_count++;
 000460                 if (awaiting_b.size() > peak) begin
 000188                     peak = awaiting_b.size();
                        end
                    end
 012010             if (vif.mon.WVALID && vif.mon.WREADY) begin
 000686                 current.data.push_back(vif.mon.WDATA);
 000686                 current.strb.push_back(vif.mon.WSTRB);
 000686                 beat_count++;
~000686                 if (current.data.size() > 256) begin
%000000                     `uvm_fatal("SM_LIMIT", "W burst exceeds 256 beats without WLAST")
                        end
 000610                 if (vif.mon.WLAST) begin
 000610                     current.last_cycle = cycle;
 000610                     bursts.push_back(current);
 000610                     current = new;
                        end
                    end
 000610             while (awaiting_w.size() != 0 && bursts.size() != 0) begin
 000610                 item = awaiting_w.pop_front();
 000610                 burst = bursts.pop_front();
 000610                 check_burst(item, burst);
 000610                 item.data = burst.data;
 000610                 item.strb = burst.strb;
 000610                 item.w_cycle = burst.last_cycle;
 000610                 item.write_done = 1;
 000610                 events.write(item.snapshot(SLAVE_WRITE, cycle));
 000610                 write_count++;
                    end
~012696             if (awaiting_b.size() > cfg.monitor_limit || bursts.size() > cfg.monitor_limit) begin
%000000                 `uvm_fatal("SM_LIMIT", "Unmatched observations exceed configured bound")
                    end
                end
            endtask
        endclass
        
