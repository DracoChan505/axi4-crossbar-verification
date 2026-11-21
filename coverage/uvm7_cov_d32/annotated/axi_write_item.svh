//      // verilator_coverage annotation
%000000 class axi_write_item extends uvm_sequence_item;
            rand bit [ADDR_W - 1 : 0] addr;
            rand bit [ID_W - 1 : 0] id;
 005107     int unsigned beats = 1, size = 2;
 005107     bit [1 : 0] burst = 1, resp = 0;
 005107     bit lock = 0;
 005107     bit [3 : 0] cache = 2, qos = 0;
 005107     bit [2 : 0] prot = 2;
            bit [DATA_W - 1 : 0] data[];
            bit [STRB_W - 1 : 0] strb[];
 005107     int unsigned aw_delay = 0, w_delay = 0, w_gap = 0;
 005107     longint unsigned uid = 0, epoch = 0, aw_cycle = 0, w_cycle = 0, b_cycle = 0;
 005107     bit aw_done = 0, w_done = 0;
 005107     int beat_index = 0, aw_wait = 0, w_wait = 0;
~000945     `uvm_object_utils(axi_write_item)
        
~005107     function new(string name = "axi_write_item");
 005107         super.new(name);
            endfunction
        
 003445     function void do_copy(uvm_object rhs);
 003445         axi_write_item t;
 003445         super.do_copy(rhs);
~003445         if (!$cast(t, rhs))
%000000             `uvm_fatal("COPY_TYPE", "not axi_write_item")
 003445         addr = t.addr;
 003445         id = t.id;
 003445         beats = t.beats;
 003445         size = t.size;
 003445         burst = t.burst;
 003445         resp = t.resp;
 003445         lock = t.lock;
 003445         cache = t.cache;
 003445         qos = t.qos;
 003445         prot = t.prot;
 003445         data = t.data;
 003445         strb = t.strb;
 003445         aw_delay = t.aw_delay;
 003445         w_delay = t.w_delay;
 003445         w_gap = t.w_gap;
 003445         uid = t.uid;
 003445         epoch = t.epoch;
 003445         aw_cycle = t.aw_cycle;
 003445         w_cycle = t.w_cycle;
 003445         b_cycle = t.b_cycle;
 003445         aw_done = t.aw_done;
 003445         w_done = t.w_done;
 003445         beat_index = t.beat_index;
 003445         aw_wait = t.aw_wait;
 003445         w_wait = t.w_wait;
            endfunction
        
 003353     function bit [STRB_W - 1 : 0] allowed_mask(int i);
 003353         longint unsigned a, q, lo, hi, base, s;
 003353         bit [STRB_W - 1 : 0] m = '0;
 003353         s = 64'(1) << size;
 003353         q = (64'(addr) / s) * s;
 003353         a = (i == 0) ? 64'(addr) : q + 64'(i) * s;
 003353         lo = a;
 003353         hi = q + (64'(i) + 1) * s -1;
 003353         base = (a / STRB_W) * STRB_W;
 013412         for (int j = 0; j < STRB_W; j++)
~013412             if (base + 64'(j) >= lo && base + 64'(j) <= hi)
 013412                 m[j] = 1;
 003353         return m;
            endfunction
            // Convenience construction from a byte-address pattern; scoreboard uses a
            // separate address enumeration, not this mask/data routine.
        
 000945     function void fill_pattern(int pattern, int sparse = 0);
 000945         longint unsigned s, q, a, base;
 000945         data = new[beats];
 000945         strb = new[beats];
 000945         s = 64'(1) << size;
 000945         q = (64'(addr) / s) * s;
 001777         for (int i = 0; i < int'(beats); i++) begin
 001777             a = (i == 0) ? 64'(addr) : q + 64'(i) * s;
 001777             base = (a / STRB_W) * STRB_W;
 001777             strb[i] = allowed_mask(i);
 001777             data[i] = '0;
 007108             for (int j = 0; j < STRB_W; j++) begin
 006426                 if (sparse == 1 && ((base + 64'(j)) % 2) == 0)
 000682                     strb[i][j] = 0;
 005812                 if (sparse == 2)
 001296                     strb[i][j] = 0;
 007108                 data[i][8 * j +: 8] = 8'((base + 64'(j)) ^ 64'(pattern));
                    end
                end
            endfunction
        
 000873     function string invalid_reason();
 000873         longint unsigned s, q, e;
~000873         if (beats < 1 || beats > 256 || size > $clog2(STRB_W))
%000000             return "length/size";
~000873         if (burst != 1 || lock != 0)
%000000             return "first-stage requires INCR non-exclusive";
 000873         s = 64'(1) << size;
 000873         q = (64'(addr) / s) * s;
 000873         e = q + 64'(beats) * s -1;
~000873         if ((e >> ADDR_W) != 0 || (64'(addr) >> 12) != (e >> 12))
%000000             return "address overflow/4KB crossing";
~000873         if (data.size() != beats || strb.size() != beats)
%000000             return "array length";
~001576         foreach (strb[i])
~001576             if ((strb[i] & ~allowed_mask(i)) != '0)
%000000                 return "illegal WSTRB";
 000873         return "";
            endfunction
        endclass
        
