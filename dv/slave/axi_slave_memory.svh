// Sparse byte memory. Ordinary control reset deliberately does not erase it.
class axi_slave_memory extends uvm_object;
    `uvm_object_utils(axi_slave_memory)

    protected byte unsigned bytes_by_address[longint unsigned];
    protected bit busy = 0;
    axi_slave_cfg cfg;

    function new(string name = "axi_slave_memory");
        super.new(name);
    endfunction

    function void set_busy(bit value);
        busy = value;
    endfunction

    function byte unsigned peek_byte(longint unsigned address);
        if (!cfg.contains(address)) begin
            `uvm_fatal("MEM_ADDRESS", "Peek outside this Slave's window")
            return 0;
        end
        if (!bytes_by_address.exists(address)) begin
            return 0;
        end
        return bytes_by_address[address];
    endfunction

    function void write_byte(longint unsigned address, byte unsigned value);
        if (!cfg.contains(address)) begin
            `uvm_fatal("MEM_ADDRESS", "Commit outside this Slave's window")
            return;
        end
        bytes_by_address[address] = value;
    endfunction

    function void clear_memory();
        if (busy) begin
            `uvm_error("CLEAR_BUSY", "Stop traffic and drain or reset before clearing memory")
            return;
        end
        bytes_by_address.delete();
    endfunction
endclass
