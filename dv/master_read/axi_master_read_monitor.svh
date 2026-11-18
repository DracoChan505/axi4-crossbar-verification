class axi_r_burst;
    bit [DATA_W - 1 : 0] data[$];
    bit [1:0]            resp[$];
    longint unsigned first_cycle, last_cycle;
endclass

class axi_r_beat extends uvm_object;
    bit [DATA_W - 1 : 0] data;
    bit [1:0]            resp;
    bit                  last;
    longint unsigned cycle, epoch, burst_seq;
    int beat_index;
    `uvm_object_utils(axi_r_beat)
    function new(string name = "axi_r_beat");
        super.new(name);
    endfunction
endclass

class axi_master_read_monitor extends uvm_monitor;
    `uvm_component_utils(axi_master_read_monitor)
    virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;
    axi_master_read_cfg cfg;
    uvm_analysis_port#(axi_read_item) ar_ap, complete_ap;
    uvm_analysis_port#(axi_r_beat) beat_ap;
    longint unsigned r_serial = 0;
    axi_read_item awaiting_r[$];
    axi_r_burst bursts[$], current;
    longint unsigned cycle = 0, epoch = 0, serial = 0;
    int ar_count = 0, r_count = 0, peak = 0, out_of_order = 0, r_stalled = 0;
    bit in_reset = 1;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ar_ap = new("ar_ap", this);
        complete_ap = new("complete_ap", this);
        beat_ap = new("beat_ap", this);
        current = new;
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
            `uvm_fatal("VIF", "Read master monitor interface missing")
        if (!uvm_config_db#(axi_master_read_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("CONFIG", "Read master monitor config missing")
    endfunction

    function bit idle();
        return awaiting_r.size() == 0 && bursts.size() == 0 && current.data.size() == 0;
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            axi_read_item t, e;
            axi_r_burst w;
            axi_r_beat beat_event;
            int idx;
            @(vif.mon);
            cycle++;
            if (!vif.mon.ARESETn) begin
                if (!in_reset) begin epoch++; in_reset = 1; end
                awaiting_r.delete(); bursts.delete(); current = new;
                continue;
            end
            in_reset = 0;
            // Check R before processing this edge's AR; same-edge early R is illegal.
            if (vif.mon.RVALID) begin
                idx = -1;
                foreach (awaiting_r[i])
                    if (idx < 0 && awaiting_r[i].id == vif.mon.RID)
                        idx = i;
                if (idx < 0)
                    `uvm_error("R_NO_PENDING", "no AR for observed RVALID")
                else if (vif.mon.RREADY) begin
                    t = awaiting_r[idx];
                    if (t.data.size() == 0) begin
                        t.data = new[t.beats];
                        t.rresp = new[t.beats];
                    end
                    t.data[t.beat_index] = vif.mon.RDATA;
                    t.rresp[t.beat_index] = vif.mon.RRESP;
                    t.beat_index++;
                    beat_event = axi_r_beat::type_id::create("beat_event");
                    beat_event.data = vif.mon.RDATA;
                    beat_event.resp = vif.mon.RRESP;
                    beat_event.last = vif.mon.RLAST;
                    beat_event.cycle = cycle;
                    beat_event.epoch = epoch;
                    beat_event.burst_seq = r_serial;
                    beat_event.beat_index = current.data.size();
                    beat_ap.write(beat_event);
                    if (vif.mon.RLAST) begin
                        t.r_done = 1;
                        t.r_cycle = cycle;
                        t.resp = vif.mon.RRESP;
                        e = axi_read_item::type_id::create("r_event");
                        e.copy(t);
                        complete_ap.write(e);
                        awaiting_r.delete(idx);
                        r_count++;
                        if (idx != 0) out_of_order++;
                    end
                end
                else begin
                    r_stalled++;
                end
            end
            if (vif.mon.ARVALID && vif.mon.ARREADY) begin
                t = axi_read_item::type_id::create("ar_record");
                t.addr = vif.mon.ARADDR;
                t.id = vif.mon.ARID;
                t.beats = int'(vif.mon.ARLEN) + 1;
                t.size = int'(vif.mon.ARSIZE);
                t.burst = vif.mon.ARBURST;
                t.lock = vif.mon.ARLOCK;
                t.cache = vif.mon.ARCACHE;
                t.prot = vif.mon.ARPROT;
                t.qos = vif.mon.ARQOS;
                t.uid = serial++;
                t.epoch = epoch;
                t.ar_cycle = cycle;
                t.ar_done = 1;
                if (t.burst != 1 || t.size > $clog2(STRB_W))
                    `uvm_fatal("AR_PROFILE", "unsupported observed profile")
                awaiting_r.push_back(t);
                ar_count++;
                e = axi_read_item::type_id::create("ar_event");
                e.copy(t);
                ar_ap.write(e);
            end
            if (awaiting_r.size() > peak)
                peak = awaiting_r.size();
            if (awaiting_r.size() > cfg.max_outstanding)
                `uvm_error("CAPACITY", "observed too many AR outstanding")
        end
    endtask
endclass
