//      // verilator_coverage annotation
        `timescale 1ns/1ps
        `include "axi_widths.svh"
        // Slave-side read driver: accepts AR from crossbar, returns R data.
        // Reuses axi_slave_cfg for base_addr/size/outstanding/stall settings.
        // ID width is AXI_SLAVE_ID_W (expanded ID with source bits).
        class axi_slave_read_driver extends uvm_component;
~000072     `uvm_component_utils(axi_slave_read_driver)
            virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;
            axi_slave_cfg cfg;
            axi_slave_memory memory;
        
            typedef struct {
                bit [ID_W-1:0]   id;
                bit [ADDR_W-1:0] address;
                int              beats;
                int              size;
                bit              reject;
                longint unsigned response_delay;
                longint unsigned aw_seq;
                longint unsigned w_done_cycle;
                bit              write_done;  // for read: becomes "ar_done" immediately
            } rd_record_t;
        
            rd_record_t active_q[$];
            rd_record_t returning;
            int         return_beat;
            bit         returning_valid;
 000072     longint unsigned cycle = 0, epoch = 0, next_seq = 0;
 000072     bit in_reset = 1;
            int unsigned ar_rng, r_rng;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
            endfunction
        
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
%000000             `uvm_fatal("VIF", "Slave read interface missing")
~000072         if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg))
%000000             `uvm_fatal("SLAVE_READ_CFG", "Slave read config missing")
 000072         cfg.validate();
 000072         memory = axi_slave_memory::type_id::create("memory");
 000072         memory.cfg = cfg;
 000072         reset_state();
            endfunction
        
 000648     function void reset_state();
 000648         active_q.delete();
 000648         returning_valid = 0;
 000648         return_beat = 0;
 000648         ar_rng = cfg.seed ^ 32'h13579bdf;
 000648         r_rng  = cfg.seed ^ 32'h2468ace0;
~000648         if (ar_rng == 0) ar_rng = 1;
~000648         if (r_rng == 0)  r_rng = 1;
            endfunction
        
 012696     function bit idle();
 012696         return active_q.size() == 0 && !returning_valid;
            endfunction
        
 013359     function int unsigned next_random(ref int unsigned state);
 013359         state ^= state << 13; state ^= state >> 17; state ^= state << 5;
 013359         return state;
            endfunction
        
            // Build an aligned read data word from memory for beat 'beat'.
 001042     function bit [DATA_W-1:0] read_data(rd_record_t rec, int beat);
 001042         longint unsigned step  = 64'(1) << rec.size;
 001042         longint unsigned block = ((64'(rec.address) / step) + 64'(beat)) * step;
 001042         longint unsigned base  = (block / STRB_W) * STRB_W;
 001042         bit [DATA_W-1:0] d = '0;
 004168         for (int lane = 0; lane < STRB_W; lane++)
 004168             d[8*lane +: 8] = memory.peek_byte(base + 64'(lane));
 001042         return d;
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000         fork
~000072             forever begin
 000072                 @(negedge vif.ARESETn);
 000072                 vif.ARREADY <= 0;
 000072                 vif.RVALID  <= 0;
 000072                 vif.RID     <= '0;
 000072                 vif.RDATA   <= '0;
 000072                 vif.RRESP   <= '0;
 000072                 vif.RLAST   <= 0;
                    end
~013272             forever begin
 013272                 int unsigned delay_draw;
 013272                 bit ar_gate;
 013272                 @(vif.mon);
 013272                 cycle++;
~012696                 if (!vif.mon.ARESETn) begin
~000504                     if (!in_reset) begin epoch++; in_reset = 1; end
%000000                     reset_state();
%000000                     vif.ARREADY <= 0;
%000000                     vif.RVALID  <= 0;
%000000                     continue;
                        end
 013272                 in_reset = 0;
                        // Retire a completed R beat
 012006                 if (vif.mon.RVALID && vif.mon.RREADY && returning_valid) begin
 000690                     return_beat++;
 000613                     if (vif.mon.RLAST) begin
                                // remove from active_q
 000613                         begin
 000613                             int idx = -1;
 000860                             foreach (active_q[i])
 000840                                 if (idx < 0 && active_q[i].id == returning.id)
 000613                                     idx = i;
~000613                             if (idx >= 0) active_q.delete(idx);
                                end
 000613                         returning_valid = 0;
 000613                         return_beat = 0;
                            end
                        end
                        // Accept AR
 012033                 if (vif.mon.ARVALID && vif.mon.ARREADY) begin
 000663                     rd_record_t rec;
 000663                     rec.id       = vif.mon.ARID;
 000663                     rec.address  = vif.mon.ARADDR;
 000663                     rec.beats    = int'(vif.mon.ARLEN) + 1;
 000663                     rec.size     = int'(vif.mon.ARSIZE);
 000663                     rec.write_done = 1;  // AR accepted = ready to respond
 000663                     rec.aw_seq   = next_seq++;
 000663                     rec.reject   = !cfg.contains(64'(rec.address));
~000663                     if (cfg.reject_enable &&
                                64'(rec.address) >= cfg.reject_first &&
                                64'(rec.address) <= cfg.reject_last)
%000000                         rec.reject = 1;
 000663                     delay_draw = 0;
~000663                     if (cfg.b_random_delay_max != 0) begin
 000663                         delay_draw = next_random(r_rng) % (cfg.b_random_delay_max + 1);
                            end
 000663                     rec.response_delay = 64'(cfg.b_delay_cycles) + 64'(delay_draw);
 000663                     rec.w_done_cycle = cycle; // "ready" immediately after AR
 000663                     active_q.push_back(rec);
                        end
                        // Select next burst to serve (oldest ready, same-ID order)
 010860                 if (!returning_valid && active_q.size() > 0) begin
 001836                     foreach (active_q[i]) begin
~002070                         if (!active_q[i].write_done) continue;
~000632                         if (cycle - active_q[i].w_done_cycle < active_q[i].response_delay) continue;
                                // ensure no earlier same-ID is pending
 001438                         begin
 001438                             bit earlier = 0;
 001438                             for (int j = 0; j < i; j++)
~000020                                 if (active_q[j].id[ID_W-1:axi_master_read_pkg::ID_W] ==
~000020                                     active_q[i].id[ID_W-1:axi_master_read_pkg::ID_W] &&
                                            active_q[j].id[axi_master_read_pkg::ID_W-1:0] ==
                                            active_q[i].id[axi_master_read_pkg::ID_W-1:0])
%000000                                     earlier = 1;
%000000                             if (!earlier) begin
%000000                                 returning = active_q[i];
%000000                                 returning_valid = 1;
%000000                                 return_beat = 0;
%000000                                 break;
                                    end
                                end
                            end
                        end
                        // Drive R
 011654                 if (returning_valid) begin
~001042                     bit [1:0] rresp = returning.reject ? 2'b10 : 2'b00;
 001042                     vif.RVALID <= 1;
 001042                     vif.RID    <= returning.id;
~001042                     vif.RDATA  <= returning.reject ? '0 : read_data(returning, return_beat);
 001042                     vif.RRESP  <= rresp;
 001042                     vif.RLAST  <= (return_beat == returning.beats - 1);
 011654                 end else begin
 011654                     vif.RVALID <= 0;
 011654                     vif.RID    <= '0;
 011654                     vif.RDATA  <= '0;
 011654                     vif.RRESP  <= '0;
 011654                     vif.RLAST  <= 0;
                        end
                        // Drive ARREADY
 013272                 ar_gate = 1;
~012696                 if (cfg.aw_random_stall_max != 0) begin
 012696                     bit unused = (next_random(ar_rng) % (cfg.aw_random_stall_max + 1)) != 0;
 012696                     ar_gate = unused;
                        end
 013272                 vif.ARREADY <= (active_q.size() < cfg.max_outstanding) && ar_gate;
 013272                 memory.set_busy(!idle());
                    end
                join
            endtask
        endclass
        
