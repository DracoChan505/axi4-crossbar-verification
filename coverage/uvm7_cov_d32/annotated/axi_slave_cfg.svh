//      // verilator_coverage annotation
        // Testbench configuration. Set these fields before build_phase completes.
        class axi_slave_cfg extends uvm_object;
%000000     `uvm_object_utils(axi_slave_cfg)
        
 000144     bit active = 1;
 000144     int unsigned monitor_limit = 64;
 000144     longint unsigned base_addr = 0;
 000144     longint unsigned size_bytes = 65536;
 000144     int unsigned max_outstanding = 4;
 000144     int unsigned b_delay_cycles = 0;
            // IN_ORDER is the default. Other modes still preserve each full AXI ID.
 000144     axi_slave_response_order response_order = B_IN_ORDER;
 000144     int unsigned b_random_delay_max = 0;
            int unsigned b_extra_delay_by_seq[longint unsigned];
 000144     int unsigned seed = 1;
        
            // Choose periodic OR bounded-random stalls independently for AW and W.
 000144     int unsigned aw_stall_period = 0;
 000144     int unsigned aw_stall_cycles = 0;
 000144     int unsigned w_stall_period = 0;
 000144     int unsigned w_stall_cycles = 0;
 000144     int unsigned aw_random_stall_max = 0;
 000144     int unsigned w_random_stall_max = 0;
        
 000144     bit reject_enable = 0;
 000144     longint unsigned reject_first = 0;
 000144     longint unsigned reject_last = 0;
        
~000144     function new(string name = "axi_slave_cfg");
 000144         super.new(name);
            endfunction
        
 000360     function void validate();
~000360         if (ADDR_W < 12 || ADDR_W > 63 || ID_W < 1 || ID_W > 16) begin
%000000             `uvm_fatal("SLAVE_CONFIG", "Unsupported address or ID width")
                end
~000360         if (DATA_W < 8 || DATA_W > 1024 || DATA_W % 8 != 0 ||
%000000             (STRB_W & (STRB_W - 1)) != 0) begin
%000000             `uvm_fatal("SLAVE_CONFIG", "Data width must contain a power-of-two byte count")
                end
~000360         if (max_outstanding == 0 || size_bytes == 0 ||
~000360             base_addr >= (64'd1 << ADDR_W) ||
%000000             size_bytes > (64'd1 << ADDR_W) - base_addr) begin
%000000             `uvm_fatal("SLAVE_CONFIG", "Invalid capacity or address window")
                end
~000360         if (monitor_limit < max_outstanding || monitor_limit == 0) begin
%000000             `uvm_fatal("SLAVE_CONFIG", "Monitor limit must cover configured capacity")
                end
 000360         validate_stall("AW", aw_stall_period, aw_stall_cycles, aw_random_stall_max);
 000360         validate_stall("W", w_stall_period, w_stall_cycles, w_random_stall_max);
~000360         if (b_random_delay_max > 1000000) begin
%000000             `uvm_fatal("SLAVE_CONFIG", "Random B delay exceeds supported test bound")
                end
~000360         if (reject_enable && reject_first > reject_last) begin
%000000             `uvm_fatal("SLAVE_CONFIG", "Invalid rejection address range")
                end
            endfunction
        
 000720     function void validate_stall(string channel, int unsigned period,
                                         int unsigned stalls, int unsigned random_max);
~000720         if ((period == 0 && stalls != 0) ||
~000720             (period != 0 && (stalls >= period || random_max != 0)) ||
%000000             random_max > 1000000) begin
%000000             `uvm_fatal("SLAVE_CONFIG", {channel, ": invalid or non-progressing stall policy"})
                end
            endfunction
        
 4731905     function bit contains(longint unsigned address);
~4731905         return address >= base_addr && address - base_addr < size_bytes;
            endfunction
        endclass
        
