//      // verilator_coverage annotation
        // AW-gated W acceptance, configurable bounded stalls and ID-safe B scheduling.
        class axi_slave_driver extends uvm_component;
~000072     `uvm_component_utils(axi_slave_driver)
        
            virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
            axi_slave_cfg cfg;
            axi_slave_memory memory;
        
            protected axi_slave_record active_q[$];
            protected axi_slave_record write_q[$];
            protected axi_slave_record returning;
 000072     protected longint unsigned cycle = 0;
 000072     protected longint unsigned epoch = 0;
 000072     protected longint unsigned next_seq = 0;
 000072     protected bit in_reset = 1;
            protected int unsigned aw_rng;
            protected int unsigned w_rng;
            protected int unsigned b_rng;
 000072     protected int unsigned aw_stall_left = 0;
 000072     protected int unsigned w_stall_left = 0;
 000072     protected longint unsigned policy_cycle = 0;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
            endfunction
        
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif)) begin
%000000             `uvm_fatal("VIF", "Slave interface missing")
                end
~000072         if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg)) begin
%000000             `uvm_fatal("SLAVE_CONFIG", "Slave configuration missing")
                end
 000072         cfg.validate();
 000072         memory = axi_slave_memory::type_id::create("memory");
 000072         memory.cfg = cfg;
 000072         reset_policies();
            endfunction
        
 012696     function bit idle();
 012696         return active_q.size() == 0 && write_q.size() == 0 && returning == null;
            endfunction
        
 000576     task drive_reset();
 000576         vif.AWREADY <= 0;
 000576         vif.WREADY <= 0;
 000576         vif.BVALID <= 0;
 000576         vif.BID <= '0;
 000576         vif.BRESP <= '0;
            endtask
        
 000576     function void reset_control();
 000576         active_q.delete();
 000576         write_q.delete();
 000576         returning = null;
 000576         memory.set_busy(0);
 000576         reset_policies();
            endfunction
        
 000648     function void accept_address();
 000648         axi_slave_record transaction;
 000648         longint unsigned step_bytes;
 000648         longint unsigned aligned_start;
 000648         longint unsigned last_address;
 000648         int unsigned delay_draw;
        
~000648         if (active_q.size() >= cfg.max_outstanding) begin
%000000             `uvm_fatal("SLAVE_CAPACITY", "Accepted an AW without a free slot")
                end
 000648         transaction = new;
 000648         transaction.epoch = epoch;
 000648         transaction.aw_seq = next_seq++;
 000648         transaction.aw_cycle = cycle;
 000648         transaction.response_delay = 64'(cfg.b_delay_cycles);
~000648         if (cfg.b_extra_delay_by_seq.exists(transaction.aw_seq)) begin
%000000             transaction.response_delay += 64'(cfg.b_extra_delay_by_seq[transaction.aw_seq]);
                end
~000648         if (cfg.b_random_delay_max != 0) begin
 000648             delay_draw = next_random(b_rng) % (cfg.b_random_delay_max + 32'd1);
 000648             transaction.response_delay += 64'(delay_draw);
                end
 000648         transaction.address = vif.mon.AWADDR;
 000648         transaction.id = vif.mon.AWID;
 000648         transaction.len = vif.mon.AWLEN;
 000648         transaction.size = vif.mon.AWSIZE;
 000648         transaction.burst = vif.mon.AWBURST;
 000648         transaction.lock = vif.mon.AWLOCK;
 000648         transaction.cache = vif.mon.AWCACHE;
 000648         transaction.prot = vif.mon.AWPROT;
 000648         transaction.qos = vif.mon.AWQOS;
 000648         transaction.beats = int'(transaction.len) + 1;
        
~000648         if (transaction.burst != 2'b01 || transaction.lock ||
%000000             int'(transaction.size) > $clog2(STRB_W)) begin
%000000             `uvm_fatal("SLAVE_AW_PROFILE", "Expected legal INCR non-exclusive request")
                end
 000648         step_bytes = 64'd1 << transaction.size;
 000648         aligned_start = (64'(transaction.address) / step_bytes) * step_bytes;
 000648         last_address = aligned_start + step_bytes * transaction.beats - 1;
~000648         if ((last_address >> ADDR_W) != 0 ||
%000000             (last_address >> 12) != (64'(transaction.address) >> 12)) begin
%000000             `uvm_fatal("SLAVE_BOUNDARY", "Address overflow or 4KB crossing")
                end
        
 000648         transaction.reject_write = !cfg.contains(64'(transaction.address)) ||
                                           !cfg.contains(last_address);
~000648         if (cfg.reject_enable &&
                    64'(transaction.address) >= cfg.reject_first &&
%000000             64'(transaction.address) <= cfg.reject_last) begin
%000000             transaction.reject_write = 1;
                end
 000648         active_q.push_back(transaction);
 000648         write_q.push_back(transaction);
            endfunction
        
 000686     function void accept_data();
 000686         axi_slave_record transaction;
 000686         axi_slave_record consumed;
 000686         longint unsigned step_bytes;
 000686         longint unsigned beat_start;
 000686         longint unsigned first_byte;
 000686         longint unsigned word_base;
 000686         longint unsigned byte_address;
 000686         bit [STRB_W-1:0] allowed;
 000686         bit expected_last;
        
~000686         if (write_q.size() == 0) begin
%000000             `uvm_fatal("SLAVE_W_NO_AW", "Received W without an accepted AW")
                end
 000686         transaction = write_q[0];
 000686         step_bytes = 64'd1 << transaction.size;
 000686         beat_start = (64'(transaction.address) / step_bytes) * step_bytes +
 000686                      64'(transaction.received) * step_bytes;
 000686         first_byte = transaction.received == 0 ? 64'(transaction.address) : beat_start;
 000686         word_base = (beat_start / STRB_W) * STRB_W;
 000686         allowed = '0;
 002744         for (int lane = 0; lane < STRB_W; lane++) begin
 002744             byte_address = word_base + 64'(lane);
~002744             allowed[lane] = byte_address >= first_byte &&
 002744                             byte_address < beat_start + step_bytes;
                end
 000686         expected_last = transaction.received + 1 == transaction.beats;
                // Check the entire beat before making any memory side effects.
~000686         if (vif.mon.WLAST != expected_last) begin
%000000             `uvm_fatal("SLAVE_WLAST", "WLAST disagrees with AWLEN")
                end
~000686         if ((vif.mon.WSTRB & ~allowed) != '0) begin
%000000             `uvm_fatal("SLAVE_WSTRB", "Strobe selects bytes outside this transfer")
                end
~000686         if (!transaction.reject_write) begin
 002744             for (int lane = 0; lane < STRB_W; lane++) begin
 002578                 if (vif.mon.WSTRB[lane]) begin
 002578                     memory.write_byte(word_base + 64'(lane), vif.mon.WDATA[8*lane +: 8]);
                        end
                    end
                end
 000686         transaction.received++;
 000610         if (expected_last) begin
 000610             transaction.write_done = 1;
 000610             transaction.w_done_cycle = cycle;
 000610             consumed = write_q.pop_front();
                end
            endfunction
        
            // Separate streams keep changing AW stalls from changing the W policy.
 010730     function int unsigned next_random(ref int unsigned state);
 010730         state ^= state << 13;
 010730         state ^= state >> 17;
 010730         state ^= state << 5;
 010730         return state;
            endfunction
        
 000648     function void reset_policies();
 000648         aw_rng = cfg.seed ^ 32'h13579bdf;
 000648         w_rng = cfg.seed ^ 32'h2468ace0;
 000648         b_rng = cfg.seed ^ 32'ha5a5a5a5;
~000648         if (aw_rng == 0) begin
%000000             aw_rng = 1;
                end
~000648         if (w_rng == 0) begin
%000000             w_rng = 1;
                end
~000648         if (b_rng == 0) begin
%000000             b_rng = 1;
                end
 000648         aw_stall_left = 0;
 000648         w_stall_left = 0;
 000648         policy_cycle = 0;
            endfunction
        
 025392     function bit ready_gate(int unsigned period, int unsigned stalls,
                                    int unsigned random_max, ref int unsigned remaining,
                                    ref int unsigned rng);
~025392         if (period != 0) begin
%000000             return policy_cycle % 64'(period) >= 64'(stalls);
                end
~009475         if (random_max != 0) begin
~009475             if (remaining != 0) begin
%000000                 remaining--;
%000000                 return 0;
                    end
                    // Always grant one policy-open cycle before drawing another gap.
 009475             remaining = next_random(rng) % (random_max + 1);
                end
 025392         return 1;
            endfunction
        
 012682     function axi_slave_record select_response();
 012682         int eligible[$];
 012682         int chosen;
 012682         int unsigned draw;
 012682         int unsigned candidate_count;
 012682         int unsigned slot;
 012682         bit earlier_same_id;
~003382         if (active_q.size() == 0) begin
%000000             return null;
                end
 012682         foreach (active_q[i]) begin
~004748             if (cfg.response_order == B_IN_ORDER && i != 0) begin
%000000                 break;
                    end
~000628             if (!active_q[i].write_done ||
%000000                 cycle - active_q[i].w_done_cycle < active_q[i].response_delay) begin
%000000                 continue;
                    end
 004748             earlier_same_id = 0;
 004748             for (int j = 0; j < i; j++) begin
~000033                 if (active_q[j].id == active_q[i].id) begin
%000000                     earlier_same_id = 1;
                        end
                    end
~000628             if (!earlier_same_id) begin
 000628                 eligible.push_back(i);
                    end
                end
~000607         if (eligible.size() == 0) begin
%000000             return null;
                end
 012682         chosen = eligible[0];
~000607         if (cfg.response_order == B_RANDOM_READY) begin
 000607             draw = next_random(b_rng);
 000607             candidate_count = int'(eligible.size());
 000607             slot = draw % candidate_count;
 000607             chosen = eligible[slot];
                end
 012682         return active_q[chosen];
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000         fork
~000072             forever begin
 000072                 @(negedge vif.ARESETn);
                        // Clocking outputs issued between edges wait for a clock event.
                        // Use direct NBA assignments only for asynchronous assertion.
 000072                 vif.AWREADY <= 0;
 000072                 vif.WREADY <= 0;
 000072                 vif.BVALID <= 0;
 000072                 vif.BID <= '0;
 000072                 vif.BRESP <= '0;
                    end
~013272             forever begin
 013272                 int response_index;
 013272                 bit aw_gate;
 013272                 bit w_gate;
 013272                 @(vif.mon);
 013272                 cycle++;
~012696                 if (!vif.mon.ARESETn) begin
~000504                     if (!in_reset) begin
 000072                         epoch++;
                            end
%000000                     in_reset = 1;
%000000                     reset_control();
%000000                     drive_reset();
%000000                     continue;
                        end
 013272                 in_reset = 0;
        
                        // Retire a response that was already valid before this edge.
 012091                 if (vif.mon.BVALID && vif.mon.BREADY) begin
~000605                     if (returning == null || active_q.size() == 0) begin
%000000                         `uvm_fatal("SLAVE_B_STATE", "Response handshake without a record")
                            end
 000605                     response_index = -1;
 000977                     foreach (active_q[i]) begin
 000605                         if (active_q[i] == returning) begin
 000605                             response_index = i;
                                end
                            end
~000605                     if (response_index < 0) begin
%000000                         `uvm_fatal("SLAVE_B_STATE", "Locked response record missing")
                            end
 000605                     active_q.delete(response_index);
 000605                     returning = null;
                        end
                        // W always uses an AW accepted on a previous edge.
 012010                 if (vif.mon.WVALID && vif.mon.WREADY) begin
 000686                     accept_data();
                        end
 012048                 if (vif.mon.AWVALID && vif.mon.AWREADY) begin
 000648                     accept_address();
                        end
        
                        // The response selected here is sampled no earlier than next edge.
 012682                 if (returning == null) begin
 012682                     returning = select_response();
                        end
 012075                 if (returning != null) begin
 000621                     vif.BVALID <= 1;
 000621                     vif.BID <= returning.id;
 000621                     vif.BRESP <= returning.reject_write ? 2'b10 : 2'b00;
                        end
 012075                 else begin
 012075                     vif.BVALID <= 0;
                        end
 013272                 aw_gate = ready_gate(cfg.aw_stall_period, cfg.aw_stall_cycles,
 013272                                      cfg.aw_random_stall_max, aw_stall_left, aw_rng);
 013272                 w_gate = ready_gate(cfg.w_stall_period, cfg.w_stall_cycles,
 013272                                     cfg.w_random_stall_max, w_stall_left, w_rng);
 013272                 policy_cycle++;
 013272                 vif.AWREADY <= active_q.size() < cfg.max_outstanding && aw_gate;
 013272                 vif.WREADY <= write_q.size() != 0 && w_gate;
 013272                 memory.set_busy(!idle());
                    end
                join
            endtask
        endclass
        
