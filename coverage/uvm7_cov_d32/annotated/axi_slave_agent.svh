//      // verilator_coverage annotation
        class axi_slave_agent extends uvm_agent;
~000072     `uvm_component_utils(axi_slave_agent)
            axi_slave_cfg cfg;
            axi_slave_driver driver;
            axi_slave_monitor monitor;
            virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
            endfunction
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg)) begin
%000000             cfg = axi_slave_cfg::type_id::create("cfg");
                end
 000072         cfg.validate();
~000072         if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif)) begin
%000000             `uvm_fatal("SLAVE_AGENT_VIF", "Agent interface missing")
                end
 000072         uvm_config_db#(axi_slave_cfg)::set(this, "*", "cfg", cfg);
 000072         uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::set(this, "*", "vif", vif);
 000072         monitor = axi_slave_monitor::type_id::create("monitor", this);
~000072         if (cfg.active) begin
 000072             driver = axi_slave_driver::type_id::create("driver", this);
                end
            endfunction
%000000     function bit idle();
%000000         if (!monitor.idle()) begin
%000000             return 0;
                end
%000000         return driver == null ? 1 : driver.idle();
            endfunction
        endclass
        
