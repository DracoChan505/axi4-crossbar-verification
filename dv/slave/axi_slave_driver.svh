// AW-gated W acceptance, configurable bounded stalls and ID-safe B scheduling.
class axi_slave_driver extends uvm_component;
    `uvm_component_utils(axi_slave_driver)

    virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
    axi_slave_cfg cfg;
    axi_slave_memory memory;

    protected axi_slave_record active_q[$];
    protected axi_slave_record write_q[$];
    protected axi_slave_record returning;
    protected longint unsigned cycle = 0;
    protected longint unsigned epoch = 0;
    protected longint unsigned next_seq = 0;
    protected bit in_reset = 1;
    protected int unsigned aw_rng;
    protected int unsigned w_rng;
    protected int unsigned b_rng;
    protected int unsigned aw_stall_left = 0;
    protected int unsigned w_stall_left = 0;
    protected longint unsigned policy_cycle = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif)) begin
            `uvm_fatal("VIF", "Slave interface missing")
        end
        if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("SLAVE_CONFIG", "Slave configuration missing")
        end
        cfg.validate();
        memory = axi_slave_memory::type_id::create("memory");
        memory.cfg = cfg;
        reset_policies();
    endfunction

    function bit idle();
        return active_q.size() == 0 && write_q.size() == 0 && returning == null;
    endfunction

    task drive_reset();
        vif.AWREADY <= 0;
        vif.WREADY <= 0;
        vif.BVALID <= 0;
        vif.BID <= '0;
        vif.BRESP <= '0;
    endtask

    function void reset_control();
        active_q.delete();
        write_q.delete();
        returning = null;
        memory.set_busy(0);
        reset_policies();
    endfunction

    function void accept_address();
        axi_slave_record transaction;
        longint unsigned step_bytes;
        longint unsigned aligned_start;
        longint unsigned last_address;
        int unsigned delay_draw;

        if (active_q.size() >= cfg.max_outstanding) begin
            `uvm_fatal("SLAVE_CAPACITY", "Accepted an AW without a free slot")
        end
        transaction = new;
        transaction.epoch = epoch;
        transaction.aw_seq = next_seq++;
        transaction.aw_cycle = cycle;
        transaction.response_delay = 64'(cfg.b_delay_cycles);
        if (cfg.b_extra_delay_by_seq.exists(transaction.aw_seq)) begin
            transaction.response_delay += 64'(cfg.b_extra_delay_by_seq[transaction.aw_seq]);
        end
        if (cfg.b_random_delay_max != 0) begin
            delay_draw = next_random(b_rng) % (cfg.b_random_delay_max + 32'd1);
            transaction.response_delay += 64'(delay_draw);
        end
        transaction.address = vif.mon.AWADDR;
        transaction.id = vif.mon.AWID;
        transaction.len = vif.mon.AWLEN;
        transaction.size = vif.mon.AWSIZE;
        transaction.burst = vif.mon.AWBURST;
        transaction.lock = vif.mon.AWLOCK;
        transaction.cache = vif.mon.AWCACHE;
        transaction.prot = vif.mon.AWPROT;
        transaction.qos = vif.mon.AWQOS;
        transaction.beats = int'(transaction.len) + 1;

        if (transaction.burst != 2'b01 || transaction.lock ||
            int'(transaction.size) > $clog2(STRB_W)) begin
            `uvm_fatal("SLAVE_AW_PROFILE", "Expected legal INCR non-exclusive request")
        end
        step_bytes = 64'd1 << transaction.size;
        aligned_start = (64'(transaction.address) / step_bytes) * step_bytes;
        last_address = aligned_start + step_bytes * transaction.beats - 1;
        if ((last_address >> ADDR_W) != 0 ||
            (last_address >> 12) != (64'(transaction.address) >> 12)) begin
            `uvm_fatal("SLAVE_BOUNDARY", "Address overflow or 4KB crossing")
        end

        transaction.reject_write = !cfg.contains(64'(transaction.address)) ||
                                   !cfg.contains(last_address);
        if (cfg.reject_enable &&
            64'(transaction.address) >= cfg.reject_first &&
            64'(transaction.address) <= cfg.reject_last) begin
            transaction.reject_write = 1;
        end
        active_q.push_back(transaction);
        write_q.push_back(transaction);
    endfunction

    function void accept_data();
        axi_slave_record transaction;
        axi_slave_record consumed;
        longint unsigned step_bytes;
        longint unsigned beat_start;
        longint unsigned first_byte;
        longint unsigned word_base;
        longint unsigned byte_address;
        bit [STRB_W-1:0] allowed;
        bit expected_last;

        if (write_q.size() == 0) begin
            `uvm_fatal("SLAVE_W_NO_AW", "Received W without an accepted AW")
        end
        transaction = write_q[0];
        step_bytes = 64'd1 << transaction.size;
        beat_start = (64'(transaction.address) / step_bytes) * step_bytes +
                     64'(transaction.received) * step_bytes;
        first_byte = transaction.received == 0 ? 64'(transaction.address) : beat_start;
        word_base = (beat_start / STRB_W) * STRB_W;
        allowed = '0;
        for (int lane = 0; lane < STRB_W; lane++) begin
            byte_address = word_base + 64'(lane);
            allowed[lane] = byte_address >= first_byte &&
                            byte_address < beat_start + step_bytes;
        end
        expected_last = transaction.received + 1 == transaction.beats;
        // Check the entire beat before making any memory side effects.
        if (vif.mon.WLAST != expected_last) begin
            `uvm_fatal("SLAVE_WLAST", "WLAST disagrees with AWLEN")
        end
        if ((vif.mon.WSTRB & ~allowed) != '0) begin
            `uvm_fatal("SLAVE_WSTRB", "Strobe selects bytes outside this transfer")
        end
        if (!transaction.reject_write) begin
            for (int lane = 0; lane < STRB_W; lane++) begin
                if (vif.mon.WSTRB[lane]) begin
                    memory.write_byte(word_base + 64'(lane), vif.mon.WDATA[8*lane +: 8]);
                end
            end
        end
        transaction.received++;
        if (expected_last) begin
            transaction.write_done = 1;
            transaction.w_done_cycle = cycle;
            consumed = write_q.pop_front();
        end
    endfunction

    // Separate streams keep changing AW stalls from changing the W policy.
    function int unsigned next_random(ref int unsigned state);
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        return state;
    endfunction

    function void reset_policies();
        aw_rng = cfg.seed ^ 32'h13579bdf;
        w_rng = cfg.seed ^ 32'h2468ace0;
        b_rng = cfg.seed ^ 32'ha5a5a5a5;
        if (aw_rng == 0) begin
            aw_rng = 1;
        end
        if (w_rng == 0) begin
            w_rng = 1;
        end
        if (b_rng == 0) begin
            b_rng = 1;
        end
        aw_stall_left = 0;
        w_stall_left = 0;
        policy_cycle = 0;
    endfunction

    function bit ready_gate(int unsigned period, int unsigned stalls,
                            int unsigned random_max, ref int unsigned remaining,
                            ref int unsigned rng);
        if (period != 0) begin
            return policy_cycle % 64'(period) >= 64'(stalls);
        end
        if (random_max != 0) begin
            if (remaining != 0) begin
                remaining--;
                return 0;
            end
            // Always grant one policy-open cycle before drawing another gap.
            remaining = next_random(rng) % (random_max + 1);
        end
        return 1;
    endfunction

    function axi_slave_record select_response();
        int eligible[$];
        int chosen;
        int unsigned draw;
        int unsigned candidate_count;
        int unsigned slot;
        bit earlier_same_id;
        if (active_q.size() == 0) begin
            return null;
        end
        foreach (active_q[i]) begin
            if (cfg.response_order == B_IN_ORDER && i != 0) begin
                break;
            end
            if (!active_q[i].write_done ||
                cycle - active_q[i].w_done_cycle < active_q[i].response_delay) begin
                continue;
            end
            earlier_same_id = 0;
            for (int j = 0; j < i; j++) begin
                if (active_q[j].id == active_q[i].id) begin
                    earlier_same_id = 1;
                end
            end
            if (!earlier_same_id) begin
                eligible.push_back(i);
            end
        end
        if (eligible.size() == 0) begin
            return null;
        end
        chosen = eligible[0];
        if (cfg.response_order == B_RANDOM_READY) begin
            draw = next_random(b_rng);
            candidate_count = int'(eligible.size());
            slot = draw % candidate_count;
            chosen = eligible[slot];
        end
        return active_q[chosen];
    endfunction

    task run_phase(uvm_phase phase);
        fork
            forever begin
                @(negedge vif.ARESETn);
                // Clocking outputs issued between edges wait for a clock event.
                // Use direct NBA assignments only for asynchronous assertion.
                vif.AWREADY <= 0;
                vif.WREADY <= 0;
                vif.BVALID <= 0;
                vif.BID <= '0;
                vif.BRESP <= '0;
            end
            forever begin
                int response_index;
                bit aw_gate;
                bit w_gate;
                @(vif.mon);
                cycle++;
                if (!vif.mon.ARESETn) begin
                    if (!in_reset) begin
                        epoch++;
                    end
                    in_reset = 1;
                    reset_control();
                    drive_reset();
                    continue;
                end
                in_reset = 0;

                // Retire a response that was already valid before this edge.
                if (vif.mon.BVALID && vif.mon.BREADY) begin
                    if (returning == null || active_q.size() == 0) begin
                        `uvm_fatal("SLAVE_B_STATE", "Response handshake without a record")
                    end
                    response_index = -1;
                    foreach (active_q[i]) begin
                        if (active_q[i] == returning) begin
                            response_index = i;
                        end
                    end
                    if (response_index < 0) begin
                        `uvm_fatal("SLAVE_B_STATE", "Locked response record missing")
                    end
                    active_q.delete(response_index);
                    returning = null;
                end
                // W always uses an AW accepted on a previous edge.
                if (vif.mon.WVALID && vif.mon.WREADY) begin
                    accept_data();
                end
                if (vif.mon.AWVALID && vif.mon.AWREADY) begin
                    accept_address();
                end

                // The response selected here is sampled no earlier than next edge.
                if (returning == null) begin
                    returning = select_response();
                end
                if (returning != null) begin
                    vif.BVALID <= 1;
                    vif.BID <= returning.id;
                    vif.BRESP <= returning.reject_write ? 2'b10 : 2'b00;
                end
                else begin
                    vif.BVALID <= 0;
                end
                aw_gate = ready_gate(cfg.aw_stall_period, cfg.aw_stall_cycles,
                                     cfg.aw_random_stall_max, aw_stall_left, aw_rng);
                w_gate = ready_gate(cfg.w_stall_period, cfg.w_stall_cycles,
                                    cfg.w_random_stall_max, w_stall_left, w_rng);
                policy_cycle++;
                vif.AWREADY <= active_q.size() < cfg.max_outstanding && aw_gate;
                vif.WREADY <= write_q.size() != 0 && w_gate;
                memory.set_busy(!idle());
            end
        join
    endtask
endclass
