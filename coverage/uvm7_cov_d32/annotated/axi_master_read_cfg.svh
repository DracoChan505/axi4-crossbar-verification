//      // verilator_coverage annotation
        class axi_master_read_cfg extends uvm_object;
%000000     `uvm_object_utils(axi_master_read_cfg)
 000072     int unsigned max_outstanding = 2;
 000072     int unsigned pending_depth = 4;
 000072     int unsigned r_stall_period = 0;
 000072     int unsigned r_stall_cycles = 0;
 000072     bit trace = 0;
~000072     function new(string name = "axi_master_read_cfg");
 000072         super.new(name);
            endfunction
 000144     function void validate();
~000144         if (max_outstanding == 0 || pending_depth < max_outstanding)
%000000             `uvm_fatal("MREAD_CFG", "invalid outstanding/pending depth")
            endfunction
        endclass
        
