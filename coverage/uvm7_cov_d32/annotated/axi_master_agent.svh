//      // verilator_coverage annotation
        class axi_master_agent extends uvm_agent;
~000072     `uvm_component_utils(axi_master_agent)
            axi_master_cfg cfg;
            uvm_sequencer#(axi_write_item) sequencer;
            axi_master_driver driver;
            axi_master_monitor monitor;
            virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
            endfunction
        
 000072     function void build_phase(uvm_phase phase);
~000072         if (!uvm_config_db#(axi_master_cfg)::get(this, "", "cfg", cfg))
%000000             cfg = axi_master_cfg::type_id::create("cfg");
 000072         cfg.validate();
~000072         if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
%000000             `uvm_fatal("VIF", "missing")
 000072         uvm_config_db#(axi_master_cfg)::set(this, "*", "cfg", cfg);
 000072         uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::set(this, "*", "vif", vif);
 000072         monitor = axi_master_monitor::type_id::create("monitor", this);
~000072         if (cfg.active) begin
 000072             sequencer = new("sequencer", this);
 000072             driver = axi_master_driver::type_id::create("driver", this);
                end
            endfunction
        
 000072     function void connect_phase(uvm_phase phase);
~000072         if (cfg.active)
 000072             driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000         if (cfg.active)
 000072             forever begin
 000072             @(negedge vif.ARESETn);
 000072             sequencer.stop_sequences();
                end
            endtask
        endclass
        
