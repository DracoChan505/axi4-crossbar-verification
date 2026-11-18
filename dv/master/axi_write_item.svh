class axi_write_item extends uvm_sequence_item;
    rand bit [ADDR_W - 1 : 0] addr;
    rand bit [ID_W - 1 : 0] id;
    int unsigned beats = 1, size = 2;
    bit [1 : 0] burst = 1, resp = 0;
    bit lock = 0;
    bit [3 : 0] cache = 2, qos = 0;
    bit [2 : 0] prot = 2;
    bit [DATA_W - 1 : 0] data[];
    bit [STRB_W - 1 : 0] strb[];
    int unsigned aw_delay = 0, w_delay = 0, w_gap = 0;
    longint unsigned uid = 0, epoch = 0, aw_cycle = 0, w_cycle = 0, b_cycle = 0;
    bit aw_done = 0, w_done = 0;
    int beat_index = 0, aw_wait = 0, w_wait = 0;
    `uvm_object_utils(axi_write_item)

    function new(string name = "axi_write_item");
        super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
        axi_write_item t;
        super.do_copy(rhs);
        if (!$cast(t, rhs))
            `uvm_fatal("COPY_TYPE", "not axi_write_item")
        addr = t.addr;
        id = t.id;
        beats = t.beats;
        size = t.size;
        burst = t.burst;
        resp = t.resp;
        lock = t.lock;
        cache = t.cache;
        qos = t.qos;
        prot = t.prot;
        data = t.data;
        strb = t.strb;
        aw_delay = t.aw_delay;
        w_delay = t.w_delay;
        w_gap = t.w_gap;
        uid = t.uid;
        epoch = t.epoch;
        aw_cycle = t.aw_cycle;
        w_cycle = t.w_cycle;
        b_cycle = t.b_cycle;
        aw_done = t.aw_done;
        w_done = t.w_done;
        beat_index = t.beat_index;
        aw_wait = t.aw_wait;
        w_wait = t.w_wait;
    endfunction

    function bit [STRB_W - 1 : 0] allowed_mask(int i);
        longint unsigned a, q, lo, hi, base, s;
        bit [STRB_W - 1 : 0] m = '0;
        s = 64'(1) << size;
        q = (64'(addr) / s) * s;
        a = (i == 0) ? 64'(addr) : q + 64'(i) * s;
        lo = a;
        hi = q + (64'(i) + 1) * s -1;
        base = (a / STRB_W) * STRB_W;
        for (int j = 0; j < STRB_W; j++)
            if (base + 64'(j) >= lo && base + 64'(j) <= hi)
                m[j] = 1;
        return m;
    endfunction
    // Convenience construction from a byte-address pattern; scoreboard uses a
    // separate address enumeration, not this mask/data routine.

    function void fill_pattern(int pattern, int sparse = 0);
        longint unsigned s, q, a, base;
        data = new[beats];
        strb = new[beats];
        s = 64'(1) << size;
        q = (64'(addr) / s) * s;
        for (int i = 0; i < int'(beats); i++) begin
            a = (i == 0) ? 64'(addr) : q + 64'(i) * s;
            base = (a / STRB_W) * STRB_W;
            strb[i] = allowed_mask(i);
            data[i] = '0;
            for (int j = 0; j < STRB_W; j++) begin
                if (sparse == 1 && ((base + 64'(j)) % 2) == 0)
                    strb[i][j] = 0;
                if (sparse == 2)
                    strb[i][j] = 0;
                data[i][8 * j +: 8] = 8'((base + 64'(j)) ^ 64'(pattern));
            end
        end
    endfunction

    function string invalid_reason();
        longint unsigned s, q, e;
        if (beats < 1 || beats > 256 || size > $clog2(STRB_W))
            return "length/size";
        if (burst != 1 || lock != 0)
            return "first-stage requires INCR non-exclusive";
        s = 64'(1) << size;
        q = (64'(addr) / s) * s;
        e = q + 64'(beats) * s -1;
        if ((e >> ADDR_W) != 0 || (64'(addr) >> 12) != (e >> 12))
            return "address overflow/4KB crossing";
        if (data.size() != beats || strb.size() != beats)
            return "array length";
        foreach (strb[i])
            if ((strb[i] & ~allowed_mask(i)) != '0)
                return "illegal WSTRB";
        return "";
    endfunction
endclass
