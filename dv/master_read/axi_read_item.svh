class axi_read_item extends uvm_sequence_item;
    rand bit [ADDR_W - 1 : 0] addr;
    rand bit [ID_W - 1 : 0]   id;
    int unsigned beats  = 1;
    int unsigned size   = 2;
    bit [1:0]    burst  = 1;
    bit [1:0]    resp   = 0;
    bit          lock   = 0;
    bit [3:0]    cache  = 2;
    bit [2:0]    prot   = 2;
    bit [3:0]    qos    = 0;
    bit [DATA_W-1:0] data[];
    bit [1:0]        rresp[];
    int unsigned ar_delay = 0;
    longint unsigned uid = 0, epoch = 0;
    longint unsigned ar_cycle = 0, r_cycle = 0;
    bit ar_done = 0, r_done = 0;
    int beat_index = 0, ar_wait = 0;
    `uvm_object_utils(axi_read_item)

    function new(string name = "axi_read_item");
        super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
        axi_read_item t;
        super.do_copy(rhs);
        if (!$cast(t, rhs))
            `uvm_fatal("COPY_TYPE", "not axi_read_item")
        addr     = t.addr;
        id       = t.id;
        beats    = t.beats;
        size     = t.size;
        burst    = t.burst;
        resp     = t.resp;
        lock     = t.lock;
        cache    = t.cache;
        prot     = t.prot;
        qos      = t.qos;
        data     = t.data;
        rresp    = t.rresp;
        ar_delay = t.ar_delay;
        uid      = t.uid;
        epoch    = t.epoch;
        ar_cycle = t.ar_cycle;
        r_cycle  = t.r_cycle;
        ar_done  = t.ar_done;
        r_done   = t.r_done;
        beat_index = t.beat_index;
        ar_wait  = t.ar_wait;
    endfunction

    function string invalid_reason();
        longint unsigned s, q, e;
        if (beats < 1 || beats > 256 || size > $clog2(STRB_W))
            return "length/size";
        if (burst != 1 || lock != 0)
            return "first-stage requires INCR non-exclusive";
        s = 64'(1) << size;
        q = (64'(addr) / s) * s;
        e = q + 64'(beats) * s - 1;
        if ((e >> ADDR_W) != 0 || (64'(addr) >> 12) != (e >> 12))
            return "address overflow/4KB crossing";
        return "";
    endfunction
endclass
