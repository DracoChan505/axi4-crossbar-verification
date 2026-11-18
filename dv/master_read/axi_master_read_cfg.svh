class axi_master_read_cfg extends uvm_object;
    `uvm_object_utils(axi_master_read_cfg)
    int unsigned max_outstanding = 2;
    int unsigned pending_depth = 4;
    int unsigned r_stall_period = 0;
    int unsigned r_stall_cycles = 0;
    bit trace = 0;
    function new(string name = "axi_master_read_cfg");
        super.new(name);
    endfunction
    function void validate();
        if (max_outstanding == 0 || pending_depth < max_outstanding)
            `uvm_fatal("MREAD_CFG", "invalid outstanding/pending depth")
    endfunction
endclass
