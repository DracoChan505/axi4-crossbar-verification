//      // verilator_coverage annotation
        // Sparse byte memory. Ordinary control reset deliberately does not erase it.
        class axi_slave_memory extends uvm_object;
%000000     `uvm_object_utils(axi_slave_memory)
        
            protected byte unsigned bytes_by_address[longint unsigned];
 000144     protected bit busy = 0;
            axi_slave_cfg cfg;
        
~000144     function new(string name = "axi_slave_memory");
 000144         super.new(name);
            endfunction
        
 025968     function void set_busy(bit value);
 025968         busy = value;
            endfunction
        
 008776     function byte unsigned peek_byte(longint unsigned address);
~008776         if (!cfg.contains(address)) begin
%000000             `uvm_fatal("MEM_ADDRESS", "Peek outside this Slave's window")
%000000             return 0;
                end
~004525         if (!bytes_by_address.exists(address)) begin
%000000             return 0;
                end
 008776         return bytes_by_address[address];
            endfunction
        
 4721170     function void write_byte(longint unsigned address, byte unsigned value);
~4721170         if (!cfg.contains(address)) begin
%000000             `uvm_fatal("MEM_ADDRESS", "Commit outside this Slave's window")
%000000             return;
                end
 4721170         bytes_by_address[address] = value;
            endfunction
        
%000000     function void clear_memory();
%000000         if (busy) begin
%000000             `uvm_error("CLEAR_BUSY", "Stop traffic and drain or reset before clearing memory")
%000000             return;
                end
%000000         bytes_by_address.delete();
            endfunction
        endclass
        
