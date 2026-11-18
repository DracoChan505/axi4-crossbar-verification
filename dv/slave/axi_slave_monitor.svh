class axi_slave_monitor extends uvm_monitor;
    `uvm_component_utils(axi_slave_monitor)
    virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
    axi_slave_cfg cfg;
    uvm_analysis_port#(axi_slave_observation) events;
    protected axi_slave_observation awaiting_w[$];
    protected axi_slave_observation awaiting_b[$];
    protected axi_slave_observed_burst bursts[$];
    protected axi_slave_observed_burst current;
    protected longint unsigned cycle = 0;
    protected longint unsigned epoch = 0;
    protected longint unsigned next_serial = 0;
    protected bit in_reset = 1;
    protected bit aw_held = 0;
    protected bit w_held = 0;
    protected bit b_held = 0;
    protected logic [ADDR_W+ID_W+25-1:0] held_aw;
    protected logic [DATA_W+STRB_W:0] held_w;
    protected logic [ID_W+1:0] held_b;
    int aw_count = 0;
    int write_count = 0;
    int b_count = 0;
    int beat_count = 0;
    int cancelled = 0;
    int peak = 0;
    int reordered = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        events = new("events", this);
        current = new;
    endfunction
    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif) ||
            !uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("SM_CONFIG", "Monitor requires interface and configuration")
        end
        cfg.validate();
    endfunction
    function bit idle();
        return awaiting_w.size() == 0 && awaiting_b.size() == 0 && bursts.size() == 0 && current.data.size() == 0;
    endfunction
    function void check_burst(axi_slave_observation item, axi_slave_observed_burst burst);
        longint unsigned block_address;
        longint unsigned byte_address;
        bit [STRB_W-1:0] legal;
        if (burst.data.size() != int'(item.len) + 1) begin
            `uvm_error("SM_W_LENGTH", "Observed WLAST/burst length disagrees with AWLEN")
        end
        foreach (burst.data[beat]) begin
            block_address = ((64'(item.address) >> item.size) + 64'(beat)) << item.size;
            legal = '0;
            for (int offset = 0; offset < (1 << item.size); offset++) begin
                byte_address = block_address + 64'(offset);
                if (byte_address >= 64'(item.address)) begin
                    legal[int'(byte_address % STRB_W)] = 1;
                end
            end
            if ((burst.strb[beat] & ~legal) != '0) begin
                `uvm_error("SM_WSTRB", "Byte enable outside this transfer")
            end
        end
    endfunction
    task run_phase(uvm_phase phase);
        axi_slave_observation item;
        axi_slave_observation event_copy;
        axi_slave_observed_burst burst;
        logic [ADDR_W+ID_W+25-1:0] aw_payload;
        logic [DATA_W+STRB_W:0] w_payload;
        logic [ID_W+1:0] b_payload;
        longint unsigned final_address;
        int match_index;
        forever begin
            @(vif.mon);
            cycle++;
            if (!vif.mon.ARESETn) begin
                if (!in_reset) begin
                    epoch++;
                    item = new;
                    item.epoch = epoch;
                    item.cancelled_aw = awaiting_b.size();
                    cancelled += awaiting_b.size();
                    events.write(item.snapshot(SLAVE_RESET, cycle));
                end
                in_reset = 1;
                awaiting_w.delete();
                awaiting_b.delete();
                bursts.delete();
                current = new;
                aw_held = 0;
                w_held = 0;
                b_held = 0;
                continue;
            end
            in_reset = 0;
            aw_payload = {vif.mon.AWADDR, vif.mon.AWID, vif.mon.AWLEN, vif.mon.AWSIZE,
                          vif.mon.AWBURST, vif.mon.AWLOCK, vif.mon.AWCACHE, vif.mon.AWPROT, vif.mon.AWQOS};
            w_payload = {vif.mon.WDATA, vif.mon.WSTRB, vif.mon.WLAST};
            b_payload = {vif.mon.BID, vif.mon.BRESP};
            if (aw_held && (!vif.mon.AWVALID || aw_payload !== held_aw)) begin
                `uvm_error("SM_AW_STABILITY", "AW changed before handshake")
            end
            if (w_held && (!vif.mon.WVALID || w_payload !== held_w)) begin
                `uvm_error("SM_W_STABILITY", "W changed before handshake")
            end
            if (b_held && (!vif.mon.BVALID || b_payload !== held_b)) begin
                `uvm_error("SM_B_STABILITY", "B changed before handshake")
            end
            aw_held = vif.mon.AWVALID && !vif.mon.AWREADY;
            w_held = vif.mon.WVALID && !vif.mon.WREADY;
            b_held = vif.mon.BVALID && !vif.mon.BREADY;
            held_aw = aw_payload;
            held_w = w_payload;
            held_b = b_payload;
            // B must refer to AW and final W from earlier sampling edges.
            if (vif.mon.BVALID) begin
                match_index = -1;
                foreach (awaiting_b[i]) begin
                    if (match_index < 0 && awaiting_b[i].id == vif.mon.BID) begin
                        match_index = i;
                    end
                end
                if (match_index < 0) begin
                    `uvm_error("SM_ORPHAN_B", "No accepted AW matches BID")
                end
                else begin
                    item = awaiting_b[match_index];
                    if (!item.write_done || item.aw_cycle >= cycle || item.w_cycle >= cycle) begin
                        `uvm_error("SM_EARLY_B", "Response precedes AW/final W completion")
                    end
                    if (vif.mon.BREADY) begin
                        item.response = vif.mon.BRESP;
                        item.b_cycle = cycle;
                        event_copy = item.snapshot(SLAVE_B, cycle);
                        events.write(event_copy);
                        awaiting_b.delete(match_index);
                        b_count++;
                        if (match_index != 0) begin
                            reordered++;
                        end
                    end
                end
            end
            if (vif.mon.AWVALID && vif.mon.AWREADY) begin
                item = new;
                item.epoch = epoch;
                item.serial = next_serial++;
                item.aw_cycle = cycle;
                item.address = vif.mon.AWADDR;
                item.id = vif.mon.AWID;
                item.len = vif.mon.AWLEN;
                item.size = vif.mon.AWSIZE;
                item.attr = {vif.mon.AWSIZE, vif.mon.AWBURST, vif.mon.AWLOCK,
                             vif.mon.AWCACHE, vif.mon.AWPROT, vif.mon.AWQOS};
                if (vif.mon.AWBURST != 1 || vif.mon.AWLOCK || int'(item.size) > $clog2(STRB_W)) begin
                    `uvm_error("SM_AW_PROFILE", "Expected supported INCR non-exclusive profile")
                end
                final_address = ((64'(item.address) >> item.size) + 64'(item.len) + 1) << item.size;
                final_address--;
                if ((final_address >> 12) != (64'(item.address) >> 12) || (final_address >> ADDR_W) != 0) begin
                    `uvm_error("SM_BOUNDARY", "Burst crosses 4KB or address width")
                end
                awaiting_w.push_back(item);
                awaiting_b.push_back(item);
                events.write(item.snapshot(SLAVE_AW, cycle));
                aw_count++;
                if (awaiting_b.size() > peak) begin
                    peak = awaiting_b.size();
                end
            end
            if (vif.mon.WVALID && vif.mon.WREADY) begin
                current.data.push_back(vif.mon.WDATA);
                current.strb.push_back(vif.mon.WSTRB);
                beat_count++;
                if (current.data.size() > 256) begin
                    `uvm_fatal("SM_LIMIT", "W burst exceeds 256 beats without WLAST")
                end
                if (vif.mon.WLAST) begin
                    current.last_cycle = cycle;
                    bursts.push_back(current);
                    current = new;
                end
            end
            while (awaiting_w.size() != 0 && bursts.size() != 0) begin
                item = awaiting_w.pop_front();
                burst = bursts.pop_front();
                check_burst(item, burst);
                item.data = burst.data;
                item.strb = burst.strb;
                item.w_cycle = burst.last_cycle;
                item.write_done = 1;
                events.write(item.snapshot(SLAVE_WRITE, cycle));
                write_count++;
            end
            if (awaiting_b.size() > cfg.monitor_limit || bursts.size() > cfg.monitor_limit) begin
                `uvm_fatal("SM_LIMIT", "Unmatched observations exceed configured bound")
            end
        end
    endtask
endclass
