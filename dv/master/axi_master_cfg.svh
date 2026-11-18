class axi_master_cfg extends uvm_object;
    int unsigned max_outstanding = 2, pending_depth = 2;
    int unsigned b_stall_period = 0, b_stall_cycles = 0;
    int unsigned monitor_limit = 64;
    bit active = 1, trace = 1;
    `uvm_object_utils(axi_master_cfg)

    function new(string name = "axi_master_cfg");
        super.new(name);
    endfunction

    function void validate();
        if (max_outstanding == 0 || pending_depth == 0 || monitor_limit < max_outstanding)
            `uvm_fatal("CONFIG", "invalid capacity")
        if (b_stall_period != 0 && b_stall_cycles >= b_stall_period)
            `uvm_fatal("CONFIG", "B stall must allow progress")
    endfunction
endclass
