class axi_master_driver extends uvm_driver#(axi_write_item);
    `uvm_component_utils(axi_master_driver)
    virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
    axi_master_cfg cfg;
    axi_write_item pending[$], active_q[$], awq[$], wq[$];
    longint unsigned cycle = 0, epoch = 0, next_uid = 0;
    int outstanding = 0, reserved = 0, max_seen = 0, pending_peak = 0;
    int accepted = 0, completed = 0, cancelled = 0;
    bit in_reset = 1, aw_on = 0, w_on = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
            `uvm_fatal("VIF", "missing")
        if (!uvm_config_db#(axi_master_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("CONFIG", "missing")
        cfg.validate();
    endfunction

    function void clear_state();
        cancelled += pending.size() + active_q.size();
        pending.delete();
        active_q.delete();
        awq.delete();
        wq.delete();
        outstanding = 0;
        reserved = 0;
        aw_on = 0;
        w_on = 0;
    endfunction

    function bit idle();
        return pending.size() == 0 && active_q.size() == 0;
    endfunction

    task drive_idle();
        vif.AWVALID <= 0;
        vif.WVALID <= 0;
        vif.BREADY <= 0;
    endtask

    task run_phase(uvm_phase phase);
        // Asynchronous deassertion of valid, while accounting remains edge-based.
        fork
            forever begin
                @(negedge vif.ARESETn);
                drive_idle();
            end
            forever begin
                axi_write_item t, c, r;
                int idx;
                @(vif.mon);
                cycle++;
                if (!vif.mon.ARESETn) begin
                    if (!in_reset) begin
                        epoch++;
                        in_reset = 1;
                    end
                    clear_state();
                    drive_idle();
                    continue;
                end
                in_reset = 0;
                // Responses are interpreted against PRE-edge AW/W completion state.
                if (vif.mon.BVALID) begin
                    idx = -1;
                    foreach (active_q[i])
                        if (idx < 0 && active_q[i].aw_done && active_q[i].id == vif.mon.BID)
                            idx = i;
                    if (idx < 0)
                        `uvm_fatal("B_NO_PENDING", "response has no accepted AW")
                    t = active_q[idx];
                    if (!t.w_done)
                        `uvm_fatal("EARLY_B", "response precedes W completion")
                    if (vif.mon.BREADY) begin
                        r = axi_write_item::type_id::create("response");
                        r.copy(t);
                        r.set_id_info(t);
                        r.resp = vif.mon.BRESP;
                        r.b_cycle = cycle;
                        seq_item_port.put_response(r);
                        active_q.delete(idx);
                        outstanding--;
                        completed++;
                        if (cfg.trace)
                            `uvm_info("B_DONE", $sformatf("epoch=%0d uid=%0d cycle=%0d id=%0d O=%0d R=%0d", epoch, t.uid, cycle, t.id, outstanding, reserved), UVM_LOW)
                    end
                end
                if (aw_on && vif.mon.AWVALID && vif.mon.AWREADY) begin
                    t = awq.pop_front();
                    t.aw_done = 1;
                    t.aw_cycle = cycle;
                    aw_on = 0;
                    outstanding++;
                    reserved--;
                    if (cfg.trace)
                        `uvm_info("AW_ACCEPT", $sformatf("epoch=%0d uid=%0d cycle=%0d id=%0d O=%0d R=%0d", epoch, t.uid, cycle, t.id, outstanding, reserved), UVM_LOW)
                end
                if (w_on && vif.mon.WVALID && vif.mon.WREADY) begin
                    t = wq[0];
                    t.beat_index++;
                    w_on = 0;
                    if (t.beat_index == int'(t.beats)) begin
                        t.w_done = 1;
                        t.w_cycle = cycle;
                        if (cfg.trace)
                            `uvm_info("W_COMPLETE", $sformatf("epoch=%0d uid=%0d cycle=%0d id=%0d", epoch, t.uid, cycle, t.id), UVM_LOW)
                        t = wq.pop_front();
                    end
                    else
                        t.w_wait = int'(t.w_gap);
                end
                // New tasks are reserved AFTER sampled events; first handshake is next edge.
                if (pending.size() > 0 && active_q.size() < cfg.max_outstanding) begin
                    t = pending.pop_front();
                    active_q.push_back(t);
                    awq.push_back(t);
                    wq.push_back(t);
                    reserved++;
                end
                if (pending.size() < cfg.pending_depth) begin
                    seq_item_port.try_next_item(t);
                    if (t != null) begin
                        string reason = t.invalid_reason();
                        if (reason != "")
                            `uvm_fatal("ITEM_INVALID", reason)
                        c = axi_write_item::type_id::create("owned");
                        c.copy(t);
                        c.set_id_info(t);
                        c.uid = next_uid++;
                        c.epoch = epoch;
                        c.aw_done = 0;
                        c.w_done = 0;
                        c.beat_index = 0;
                        c.aw_wait = int'(c.aw_delay);
                        c.w_wait = int'(c.w_delay);
                        pending.push_back(c);
                        accepted++;
                        seq_item_port.item_done();
                    end
                end
                if (!aw_on) begin
                    vif.AWVALID <= 0;
                    if (awq.size() > 0) begin
                        t = awq[0];
                        if (t.aw_wait > 0)
                            t.aw_wait--;
                        else begin
                            vif.AWADDR <= t.addr;
                            vif.AWID <= t.id;
                            vif.AWLEN <= 8'(t.beats - 1);
                            vif.AWSIZE <= 3'(t.size);
                            vif.AWBURST <= t.burst;
                            vif.AWLOCK <= t.lock;
                            vif.AWCACHE <= t.cache;
                            vif.AWPROT <= t.prot;
                            vif.AWQOS <= t.qos;
                            vif.AWVALID <= 1;
                            aw_on = 1;
                        end
                    end
                end
                if (!w_on) begin
                    vif.WVALID <= 0;
                    if (wq.size() > 0) begin
                        t = wq[0];
                        if (t.w_wait > 0)
                            t.w_wait--;
                        else begin
                            vif.WDATA <= t.data[t.beat_index];
                            vif.WSTRB <= t.strb[t.beat_index];
                            vif.WLAST <= (t.beat_index == int'(t.beats) - 1);
                            vif.WVALID <= 1;
                            w_on = 1;
                        end
                    end
                end
                vif.BREADY <= (cfg.b_stall_period == 0 || (cycle % 64'(cfg.b_stall_period)) >= 64'(cfg.b_stall_cycles));
                if (outstanding < 0 || reserved < 0 || outstanding + reserved != active_q.size() || active_q.size() > cfg.max_outstanding)
                    `uvm_fatal("CAPACITY", "inconsistent O/R/active")
                if (outstanding > max_seen)
                    max_seen = outstanding;
                if (pending.size() > pending_peak)
                    pending_peak = pending.size();
            end
        join
    endtask
endclass
