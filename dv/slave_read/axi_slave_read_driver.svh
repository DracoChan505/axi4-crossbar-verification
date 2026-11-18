`timescale 1ns/1ps
`include "axi_widths.svh"
// Slave-side read driver: accepts AR from crossbar, returns R data.
// Reuses axi_slave_cfg for base_addr/size/outstanding/stall settings.
// ID width is AXI_SLAVE_ID_W (expanded ID with source bits).
class axi_slave_read_driver extends uvm_component;
    `uvm_component_utils(axi_slave_read_driver)
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
    longint unsigned cycle = 0, epoch = 0, next_seq = 0;
    bit in_reset = 1;
    int unsigned ar_rng, r_rng;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
            `uvm_fatal("VIF", "Slave read interface missing")
        if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("SLAVE_READ_CFG", "Slave read config missing")
        cfg.validate();
        memory = axi_slave_memory::type_id::create("memory");
        memory.cfg = cfg;
        reset_state();
    endfunction

    function void reset_state();
        active_q.delete();
        returning_valid = 0;
        return_beat = 0;
        ar_rng = cfg.seed ^ 32'h13579bdf;
        r_rng  = cfg.seed ^ 32'h2468ace0;
        if (ar_rng == 0) ar_rng = 1;
        if (r_rng == 0)  r_rng = 1;
    endfunction

    function bit idle();
        return active_q.size() == 0 && !returning_valid;
    endfunction

    function int unsigned next_random(ref int unsigned state);
        state ^= state << 13; state ^= state >> 17; state ^= state << 5;
        return state;
    endfunction

    // Build an aligned read data word from memory for beat 'beat'.
    function bit [DATA_W-1:0] read_data(rd_record_t rec, int beat);
        longint unsigned step  = 64'(1) << rec.size;
        longint unsigned block = ((64'(rec.address) / step) + 64'(beat)) * step;
        longint unsigned base  = (block / STRB_W) * STRB_W;
        bit [DATA_W-1:0] d = '0;
        for (int lane = 0; lane < STRB_W; lane++)
            d[8*lane +: 8] = memory.peek_byte(base + 64'(lane));
        return d;
    endfunction

    task run_phase(uvm_phase phase);
        fork
            forever begin
                @(negedge vif.ARESETn);
                vif.ARREADY <= 0;
                vif.RVALID  <= 0;
                vif.RID     <= '0;
                vif.RDATA   <= '0;
                vif.RRESP   <= '0;
                vif.RLAST   <= 0;
            end
            forever begin
                int unsigned delay_draw;
                bit ar_gate;
                @(vif.mon);
                cycle++;
                if (!vif.mon.ARESETn) begin
                    if (!in_reset) begin epoch++; in_reset = 1; end
                    reset_state();
                    vif.ARREADY <= 0;
                    vif.RVALID  <= 0;
                    continue;
                end
                in_reset = 0;
                // Retire a completed R beat
                if (vif.mon.RVALID && vif.mon.RREADY && returning_valid) begin
                    return_beat++;
                    if (vif.mon.RLAST) begin
                        // remove from active_q
                        begin
                            int idx = -1;
                            foreach (active_q[i])
                                if (idx < 0 && active_q[i].id == returning.id)
                                    idx = i;
                            if (idx >= 0) active_q.delete(idx);
                        end
                        returning_valid = 0;
                        return_beat = 0;
                    end
                end
                // Accept AR
                if (vif.mon.ARVALID && vif.mon.ARREADY) begin
                    rd_record_t rec;
                    rec.id       = vif.mon.ARID;
                    rec.address  = vif.mon.ARADDR;
                    rec.beats    = int'(vif.mon.ARLEN) + 1;
                    rec.size     = int'(vif.mon.ARSIZE);
                    rec.write_done = 1;  // AR accepted = ready to respond
                    rec.aw_seq   = next_seq++;
                    rec.reject   = !cfg.contains(64'(rec.address));
                    if (cfg.reject_enable &&
                        64'(rec.address) >= cfg.reject_first &&
                        64'(rec.address) <= cfg.reject_last)
                        rec.reject = 1;
                    delay_draw = 0;
                    if (cfg.b_random_delay_max != 0) begin
                        delay_draw = next_random(r_rng) % (cfg.b_random_delay_max + 1);
                    end
                    rec.response_delay = 64'(cfg.b_delay_cycles) + 64'(delay_draw);
                    rec.w_done_cycle = cycle; // "ready" immediately after AR
                    active_q.push_back(rec);
                end
                // Select next burst to serve (oldest ready, same-ID order)
                if (!returning_valid && active_q.size() > 0) begin
                    foreach (active_q[i]) begin
                        if (!active_q[i].write_done) continue;
                        if (cycle - active_q[i].w_done_cycle < active_q[i].response_delay) continue;
                        // ensure no earlier same-ID is pending
                        begin
                            bit earlier = 0;
                            for (int j = 0; j < i; j++)
                                if (active_q[j].id[ID_W-1:axi_master_read_pkg::ID_W] ==
                                    active_q[i].id[ID_W-1:axi_master_read_pkg::ID_W] &&
                                    active_q[j].id[axi_master_read_pkg::ID_W-1:0] ==
                                    active_q[i].id[axi_master_read_pkg::ID_W-1:0])
                                    earlier = 1;
                            if (!earlier) begin
                                returning = active_q[i];
                                returning_valid = 1;
                                return_beat = 0;
                                break;
                            end
                        end
                    end
                end
                // Drive R
                if (returning_valid) begin
                    bit [1:0] rresp = returning.reject ? 2'b10 : 2'b00;
                    vif.RVALID <= 1;
                    vif.RID    <= returning.id;
                    vif.RDATA  <= returning.reject ? '0 : read_data(returning, return_beat);
                    vif.RRESP  <= rresp;
                    vif.RLAST  <= (return_beat == returning.beats - 1);
                end else begin
                    vif.RVALID <= 0;
                    vif.RID    <= '0;
                    vif.RDATA  <= '0;
                    vif.RRESP  <= '0;
                    vif.RLAST  <= 0;
                end
                // Drive ARREADY
                ar_gate = 1;
                if (cfg.aw_random_stall_max != 0) begin
                    bit unused = (next_random(ar_rng) % (cfg.aw_random_stall_max + 1)) != 0;
                    ar_gate = unused;
                end
                vif.ARREADY <= (active_q.size() < cfg.max_outstanding) && ar_gate;
                memory.set_busy(!idle());
            end
        join
    endtask
endclass
