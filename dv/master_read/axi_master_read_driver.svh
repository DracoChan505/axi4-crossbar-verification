// AR driver and R receiver for the read master agent.
class axi_master_read_driver extends uvm_driver#(axi_read_item);
    `uvm_component_utils(axi_master_read_driver)
    virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;
    axi_master_read_cfg cfg;
    axi_read_item pending[$], active_q[$], arq[$], rq[$];
    longint unsigned cycle = 0, epoch = 0, next_uid = 0;
    int outstanding = 0, reserved = 0;
    int accepted = 0, completed = 0, cancelled = 0;
    bit in_reset = 1, ar_on = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
            `uvm_fatal("VIF", "Read master interface missing")
        if (!uvm_config_db#(axi_master_read_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("CONFIG", "Read master config missing")
        cfg.validate();
    endfunction

    function void clear_state();
        cancelled += pending.size() + active_q.size();
        pending.delete(); active_q.delete(); arq.delete(); rq.delete();
        outstanding = 0; reserved = 0; ar_on = 0;
    endfunction

    function bit idle();
        return pending.size() == 0 && active_q.size() == 0;
    endfunction

    task drive_idle();
        vif.ARVALID <= 0;
        vif.RREADY  <= 0;
    endtask

    task run_phase(uvm_phase phase);
        fork
            forever begin
                @(negedge vif.ARESETn);
                drive_idle();
            end
            forever begin
                axi_read_item t, c, r;
                int idx;
                @(vif.mon);
                cycle++;
                if (!vif.mon.ARESETn) begin
                    if (!in_reset) begin epoch++; in_reset = 1; end
                    clear_state(); drive_idle(); continue;
                end
                in_reset = 0;
                // Capture R beats. RLAST completes the transaction.
                // No r_on gate: simply check RVALID && RREADY and rq has data.
                if (vif.mon.RVALID && vif.mon.RREADY && rq.size() > 0) begin
                    t = rq[0];
                    if (t.data.size() == 0) begin
                        t.data = new[t.beats];
                        t.rresp = new[t.beats];
                    end
                    t.data[t.beat_index] = vif.mon.RDATA;
                    t.rresp[t.beat_index] = vif.mon.RRESP;
                    t.beat_index++;
                    if (vif.mon.RLAST) begin
                        t.r_done  = 1;
                        t.r_cycle = cycle;
                        t.resp    = vif.mon.RRESP;
                        idx = -1;
                        foreach (active_q[i])
                            if (idx < 0 && active_q[i].ar_done &&
                                active_q[i].id == vif.mon.RID)
                                idx = i;
                        if (idx < 0)
                            `uvm_fatal("R_NO_PENDING", "RLAST has no pending AR")
                        r = axi_read_item::type_id::create("response");
                        r.copy(active_q[idx]);
                        r.set_id_info(active_q[idx]);
                        r.resp    = vif.mon.RRESP;
                        r.r_cycle = cycle;
                        seq_item_port.put_response(r);
                        active_q.delete(idx);
                        outstanding--;
                        completed++;
                        void'(rq.pop_front());
                    end
                end
                // AR handshake
                if (ar_on && vif.mon.ARVALID && vif.mon.ARREADY) begin
                    t = arq.pop_front();
                    t.ar_done  = 1;
                    t.ar_cycle = cycle;
                    ar_on = 0;
                    outstanding++;
                    reserved--;
                end
                // Pull new items from sequencer
                if (pending.size() < cfg.pending_depth) begin
                    seq_item_port.try_next_item(t);
                    if (t != null) begin
                        string reason = t.invalid_reason();
                        if (reason != "")
                            `uvm_fatal("ITEM_INVALID", reason)
                        c = axi_read_item::type_id::create("owned");
                        c.copy(t);
                        c.set_id_info(t);
                        c.uid       = next_uid++;
                        c.epoch     = epoch;
                        c.ar_done   = 0;
                        c.r_done    = 0;
                        c.beat_index = 0;
                        c.ar_wait   = int'(c.ar_delay);
                        pending.push_back(c);
                        accepted++;
                        seq_item_port.item_done();
                    end
                end
                // Promote pending → active
                if (pending.size() > 0 &&
                    active_q.size() < cfg.max_outstanding) begin
                    t = pending.pop_front();
                    active_q.push_back(t);
                    arq.push_back(t);
                    rq.push_back(t);
                    reserved++;
                end
                // Drive AR
                if (!ar_on) begin
                    vif.ARVALID <= 0;
                    if (arq.size() > 0) begin
                        t = arq[0];
                        if (t.ar_wait > 0)
                            t.ar_wait--;
                        else begin
                            vif.ARADDR  <= t.addr;
                            vif.ARID    <= t.id;
                            vif.ARLEN   <= 8'(t.beats - 1);
                            vif.ARSIZE  <= 3'(t.size);
                            vif.ARBURST <= t.burst;
                            vif.ARLOCK  <= t.lock;
                            vif.ARCACHE <= t.cache;
                            vif.ARPROT  <= t.prot;
                            vif.ARQOS   <= t.qos;
                            vif.ARVALID <= 1;
                            ar_on = 1;
                        end
                    end
                end
                // Drive RREADY: always grant when stall policy allows, if we have outstanding ARs
                begin
                    int period = cfg.r_stall_period;
                    int stalls = cfg.r_stall_cycles;
                    logic rready_val;
                    rready_val = (period == 0) ||
                                 (cycle % 64'(period)) >= 64'(stalls);
                    // Only assert RREADY if we have outstanding transactions to consume
                    if (rq.size() > 0)
                        vif.RREADY <= rready_val;
                    else
                        vif.RREADY <= 0;
                end
            end
        join
    endtask
endclass
