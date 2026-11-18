// Testbench configuration. Set these fields before build_phase completes.
class axi_slave_cfg extends uvm_object;
    `uvm_object_utils(axi_slave_cfg)

    bit active = 1;
    int unsigned monitor_limit = 64;
    longint unsigned base_addr = 0;
    longint unsigned size_bytes = 65536;
    int unsigned max_outstanding = 4;
    int unsigned b_delay_cycles = 0;
    // IN_ORDER is the default. Other modes still preserve each full AXI ID.
    axi_slave_response_order response_order = B_IN_ORDER;
    int unsigned b_random_delay_max = 0;
    int unsigned b_extra_delay_by_seq[longint unsigned];
    int unsigned seed = 1;

    // Choose periodic OR bounded-random stalls independently for AW and W.
    int unsigned aw_stall_period = 0;
    int unsigned aw_stall_cycles = 0;
    int unsigned w_stall_period = 0;
    int unsigned w_stall_cycles = 0;
    int unsigned aw_random_stall_max = 0;
    int unsigned w_random_stall_max = 0;

    bit reject_enable = 0;
    longint unsigned reject_first = 0;
    longint unsigned reject_last = 0;

    function new(string name = "axi_slave_cfg");
        super.new(name);
    endfunction

    function void validate();
        if (ADDR_W < 12 || ADDR_W > 63 || ID_W < 1 || ID_W > 16) begin
            `uvm_fatal("SLAVE_CONFIG", "Unsupported address or ID width")
        end
        if (DATA_W < 8 || DATA_W > 1024 || DATA_W % 8 != 0 ||
            (STRB_W & (STRB_W - 1)) != 0) begin
            `uvm_fatal("SLAVE_CONFIG", "Data width must contain a power-of-two byte count")
        end
        if (max_outstanding == 0 || size_bytes == 0 ||
            base_addr >= (64'd1 << ADDR_W) ||
            size_bytes > (64'd1 << ADDR_W) - base_addr) begin
            `uvm_fatal("SLAVE_CONFIG", "Invalid capacity or address window")
        end
        if (monitor_limit < max_outstanding || monitor_limit == 0) begin
            `uvm_fatal("SLAVE_CONFIG", "Monitor limit must cover configured capacity")
        end
        validate_stall("AW", aw_stall_period, aw_stall_cycles, aw_random_stall_max);
        validate_stall("W", w_stall_period, w_stall_cycles, w_random_stall_max);
        if (b_random_delay_max > 1000000) begin
            `uvm_fatal("SLAVE_CONFIG", "Random B delay exceeds supported test bound")
        end
        if (reject_enable && reject_first > reject_last) begin
            `uvm_fatal("SLAVE_CONFIG", "Invalid rejection address range")
        end
    endfunction

    function void validate_stall(string channel, int unsigned period,
                                 int unsigned stalls, int unsigned random_max);
        if ((period == 0 && stalls != 0) ||
            (period != 0 && (stalls >= period || random_max != 0)) ||
            random_max > 1000000) begin
            `uvm_fatal("SLAVE_CONFIG", {channel, ": invalid or non-progressing stall policy"})
        end
    endfunction

    function bit contains(longint unsigned address);
        return address >= base_addr && address - base_addr < size_bytes;
    endfunction
endclass
