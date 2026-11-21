//      // verilator_coverage annotation
        class axi_slave_read_agent extends uvm_agent;
~000072     `uvm_component_utils(axi_slave_read_agent)
            axi_slave_cfg cfg;
            axi_slave_read_driver driver;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
            endfunction
 000072     function void build_phase(uvm_phase phase);
 000072         virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;
~000072         if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg)) begin
%000000             cfg = axi_slave_cfg::type_id::create("cfg");
                end
 000072         cfg.validate();
~000072         if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
%000000             `uvm_fatal("SRAGENT_VIF", "Slave read agent: vif missing")
 000072         uvm_config_db#(axi_slave_cfg)::set(this, "*", "cfg", cfg);
 000072         uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::set(this, "*", "vif", vif);
 000072         driver = axi_slave_read_driver::type_id::create("driver", this);
            endfunction
%000000     function bit idle();
%000000         return driver.idle();
            endfunction
        endclass
        
