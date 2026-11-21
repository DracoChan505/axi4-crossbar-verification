//      // verilator_coverage annotation
%000000 class axi_read_item extends uvm_sequence_item;
            rand bit [ADDR_W - 1 : 0] addr;
            rand bit [ID_W - 1 : 0]   id;
 004662     int unsigned beats  = 1;
 004662     int unsigned size   = 2;
 004662     bit [1:0]    burst  = 1;
 004662     bit [1:0]    resp   = 0;
 004662     bit          lock   = 0;
 004662     bit [3:0]    cache  = 2;
 004662     bit [2:0]    prot   = 2;
 004662     bit [3:0]    qos    = 0;
            bit [DATA_W-1:0] data[];
            bit [1:0]        rresp[];
 004662     int unsigned ar_delay = 0;
 004662     longint unsigned uid = 0, epoch = 0;
 004662     longint unsigned ar_cycle = 0, r_cycle = 0;
 004662     bit ar_done = 0, r_done = 0;
 004662     int beat_index = 0, ar_wait = 0;
~001048     `uvm_object_utils(axi_read_item)
        
~004662     function new(string name = "axi_read_item");
 004662         super.new(name);
            endfunction
        
 002890     function void do_copy(uvm_object rhs);
 002890         axi_read_item t;
 002890         super.do_copy(rhs);
~002890         if (!$cast(t, rhs))
%000000             `uvm_fatal("COPY_TYPE", "not axi_read_item")
 002890         addr     = t.addr;
 002890         id       = t.id;
 002890         beats    = t.beats;
 002890         size     = t.size;
 002890         burst    = t.burst;
 002890         resp     = t.resp;
 002890         lock     = t.lock;
 002890         cache    = t.cache;
 002890         prot     = t.prot;
 002890         qos      = t.qos;
 002890         data     = t.data;
 002890         rresp    = t.rresp;
 002890         ar_delay = t.ar_delay;
 002890         uid      = t.uid;
 002890         epoch    = t.epoch;
 002890         ar_cycle = t.ar_cycle;
 002890         r_cycle  = t.r_cycle;
 002890         ar_done  = t.ar_done;
 002890         r_done   = t.r_done;
 002890         beat_index = t.beat_index;
 002890         ar_wait  = t.ar_wait;
            endfunction
        
 000976     function string invalid_reason();
 000976         longint unsigned s, q, e;
~000976         if (beats < 1 || beats > 256 || size > $clog2(STRB_W))
%000000             return "length/size";
~000976         if (burst != 1 || lock != 0)
%000000             return "first-stage requires INCR non-exclusive";
 000976         s = 64'(1) << size;
 000976         q = (64'(addr) / s) * s;
 000976         e = q + 64'(beats) * s - 1;
~000976         if ((e >> ADDR_W) != 0 || (64'(addr) >> 12) != (e >> 12))
%000000             return "address overflow/4KB crossing";
 000976         return "";
            endfunction
        endclass
        
