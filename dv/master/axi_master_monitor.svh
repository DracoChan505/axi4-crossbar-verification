class axi_w_burst;
    bit [DATA_W - 1 : 0] data[$];
    bit [STRB_W - 1 : 0] strb[$];
    longint unsigned first_cycle, last_cycle;
endclass

class axi_w_beat extends uvm_object;
    bit [DATA_W - 1 : 0] data;
    bit [STRB_W - 1 : 0] strb;
    bit last;
    longint unsigned cycle, epoch, burst_seq;
    int beat_index;
    `uvm_object_utils(axi_w_beat)

    function new(string name = "axi_w_beat");
        super.new(name);
    endfunction
endclass

class axi_master_monitor extends uvm_monitor;
    `uvm_component_utils(axi_master_monitor)
    virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
    axi_master_cfg cfg;
    uvm_analysis_port#(axi_write_item) aw_ap, write_ap, complete_ap;
    uvm_analysis_port#(axi_w_beat) beat_ap;
    longint unsigned w_serial = 0;
    axi_write_item awaiting_w[$], awaiting_b[$];
    axi_w_burst bursts[$], current;
    longint unsigned cycle = 0, epoch = 0, serial = 0;
    int aw_count = 0, w_count = 0, b_count = 0, peak = 0;
    int aw_first = 0, w_first = 0, same_edge = 0, b_stalled = 0, out_of_order = 0;
    int size_hits[8], length_hits[4];
    int cov_size, cov_length;
    covergroup observed_writes with function sample(int sample_size, int sample_length);
        cp_size : coverpoint sample_size {
            bins supported[] = {[0 : $clog2(STRB_W)]};
        }
        cp_length : coverpoint sample_length {
            bins single = {1};
            bins short_burst = {[2 : 16]};
            bins long_burst = {[17 : 255]};
            bins maximum = {256};
        }
    endgroup
    bit in_reset = 1;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        aw_ap = new("aw_ap", this);
        write_ap = new("write_ap", this);
        complete_ap = new("complete_ap", this);
        observed_writes = new;
        beat_ap = new("beat_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
            `uvm_fatal("VIF", "missing")
        if (!uvm_config_db#(axi_master_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("CONFIG", "missing")
        current = new;
    endfunction

    function bit idle();
        return awaiting_w.size() == 0 && awaiting_b.size() == 0 && bursts.size() == 0 && current.data.size() == 0;
    endfunction

    function void check_bytes(axi_write_item t, axi_w_burst w);
        longint unsigned block_start, first, step;
        bit [STRB_W - 1 : 0] legal;
        if (w.data.size() != t.beats) begin
            `uvm_error("W_LENGTH", "AWLEN and observed WLAST disagree")
            return;
        end
        step = 64'(1) << t.size;
        block_start = (64'(t.addr) / step) * step;
        for (int i = 0; i < int'(t.beats); i++) begin
            legal = '0;
            first = (i == 0) ? 64'(t.addr) : block_start;
            for (longint unsigned a = block_start; a < block_start + step; a++)
                if (a >= first)
                    legal[int'(a % STRB_W)] = 1;
            if ((w.strb[i] & ~legal) != '0)
                `uvm_error("WSTRB", "byte outside legal address set")
            block_start += step;
        end
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            axi_write_item t, e;
            axi_w_burst w;
            axi_w_beat beat_event;
            int idx;
            @(vif.mon);
            cycle++;
            if (!vif.mon.ARESETn) begin
                if (!in_reset) begin
                    epoch++;
                    in_reset = 1;
                end
                awaiting_w.delete();
                awaiting_b.delete();
                bursts.delete();
                current = new;
                continue;
            end
            in_reset = 0;
            // Check B before processing this edge's AW/W; same-edge early B is illegal.
            if (vif.mon.BVALID) begin
                idx = -1;
                foreach (awaiting_b[i])
                    if (idx < 0 && awaiting_b[i].id == vif.mon.BID)
                        idx = i;
                if (idx < 0)
                    `uvm_error("B_NO_PENDING", "no AW for observed BVALID")
                else if (!awaiting_b[idx].w_done)
                    `uvm_error("EARLY_B", "W not complete before BVALID")
                else if (vif.mon.BREADY) begin
                    t = awaiting_b[idx];
                    if (idx != 0)
                        out_of_order++;
                    t.resp = vif.mon.BRESP;
                    t.b_cycle = cycle;
                    e = axi_write_item::type_id::create("b_event");
                    e.copy(t);
                    complete_ap.write(e);
                    awaiting_b.delete(idx);
                    b_count++;
                end
                if (!vif.mon.BREADY)
                    b_stalled++;
            end
            if (vif.mon.AWVALID && vif.mon.AWREADY) begin
                t = axi_write_item::type_id::create("aw_record");
                t.addr = vif.mon.AWADDR;
                t.id = vif.mon.AWID;
                t.beats = int'(vif.mon.AWLEN) + 1;
                t.size = int'(vif.mon.AWSIZE);
                t.burst = vif.mon.AWBURST;
                t.lock = vif.mon.AWLOCK;
                t.cache = vif.mon.AWCACHE;
                t.prot = vif.mon.AWPROT;
                t.qos = vif.mon.AWQOS;
                t.uid = serial++;
                t.epoch = epoch;
                t.aw_cycle = cycle;
                t.aw_done = 1;
                if (t.burst != 1 || t.size > $clog2(STRB_W))
                    `uvm_fatal("AW_PROFILE", "unsupported observed profile")
                if (((64'(t.addr) / (64'(1) << t.size) * (64'(1) << t.size) + 64'(t.beats) * (64'(1) << t.size) - 1) >> 12) != (64'(t.addr) >> 12))
                    `uvm_error("BOUNDARY", "observed crossing burst")
                awaiting_w.push_back(t);
                awaiting_b.push_back(t);
                aw_count++;
                e = axi_write_item::type_id::create("aw_event");
                e.copy(t);
                aw_ap.write(e);
            end
            if (vif.mon.WVALID && vif.mon.WREADY) begin
                beat_event = axi_w_beat::type_id::create("beat_event");
                beat_event.data = vif.mon.WDATA;
                beat_event.strb = vif.mon.WSTRB;
                beat_event.last = vif.mon.WLAST;
                beat_event.cycle = cycle;
                beat_event.epoch = epoch;
                beat_event.burst_seq = w_serial;
                beat_event.beat_index = current.data.size();
                beat_ap.write(beat_event);
                if (vif.mon.WLAST)
                    w_serial++;
                if (current.data.size() == 0)
                    current.first_cycle = cycle;
                current.data.push_back(vif.mon.WDATA);
                current.strb.push_back(vif.mon.WSTRB);
                w_count++;
                if (current.data.size() > 256)
                    `uvm_fatal("W_LENGTH", "more than 256 beats without WLAST")
                if (awaiting_w.size() > bursts.size()) begin
                    t = awaiting_w[bursts.size()];
                    if ((current.data.size() == t.beats) != vif.mon.WLAST)
                        `uvm_error("WLAST", "wrong WLAST position")
                end
                if (vif.mon.WLAST) begin
                    current.last_cycle = cycle;
                    bursts.push_back(current);
                    current = new;
                end
            end
            while (awaiting_w.size() > 0 && bursts.size() > 0) begin
                t = awaiting_w.pop_front();
                w = bursts.pop_front();
                check_bytes(t, w);
                t.data = new[w.data.size()];
                t.strb = new[w.strb.size()];
                foreach (t.data[i]) begin
                    t.data[i] = w.data[i];
                    t.strb[i] = w.strb[i];
                end
                t.w_done = (w.data.size() == t.beats);
                t.w_cycle = w.last_cycle;
                cov_size = int'(t.size);
                cov_length = int'(t.beats);
                observed_writes.sample(cov_size, cov_length);
                size_hits[t.size]++;
                if (t.beats == 1)
                    length_hits[0]++;
                else if (t.beats <= 16)
                    length_hits[1]++;
                else if (t.beats < 256)
                    length_hits[2]++;
                else
                    length_hits[3]++;
                if (w.first_cycle < t.aw_cycle)
                    w_first++;
                else if (w.first_cycle > t.aw_cycle)
                    aw_first++;
                else
                    same_edge++;
                e = axi_write_item::type_id::create("w_event");
                e.copy(t);
                write_ap.write(e);
            end
            if (awaiting_b.size() > peak)
                peak = awaiting_b.size();
            if (awaiting_b.size() > cfg.max_outstanding)
                `uvm_error("CAPACITY", "observed too many AW outstanding")
            if (awaiting_w.size() + bursts.size() > cfg.monitor_limit)
                `uvm_fatal("MON_LIMIT", "unpaired queue limit")
        end
    endtask
endclass
