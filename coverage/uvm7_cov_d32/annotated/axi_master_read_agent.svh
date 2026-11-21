//      // verilator_coverage annotation
        class axi_master_read_agent extends uvm_agent;
~000072     `uvm_component_utils(axi_master_read_agent)
            axi_master_read_cfg cfg;
            axi_master_read_driver driver;
            axi_master_read_monitor monitor;
            uvm_sequencer#(axi_read_item) sequencer;
            virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;
        
 000072     function new(string name, uvm_component parent);
 000072         super.new(name, parent);
            endfunction
        
 000072     function void build_phase(uvm_phase phase);
                // local variable shadows class member; get into class member directly
~000072         if (!uvm_config_db#(axi_master_read_cfg)::get(this, "", "cfg", cfg)) begin
%000000             cfg = axi_master_read_cfg::type_id::create("cfg");
                end
 000072         cfg.validate();
                // Forward vif and cfg to child components
~000072         if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
%000000             `uvm_fatal("MRAGENT_VIF", "Read master agent: vif missing")
 000072         uvm_config_db#(axi_master_read_cfg)::set(this, "*", "cfg", cfg);
 000072         uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::set(this, "*", "vif", vif);
 000072         monitor = axi_master_read_monitor::type_id::create("monitor", this);
 000072         sequencer = uvm_sequencer#(axi_read_item)::type_id::create("sequencer", this);
 000072         driver = axi_master_read_driver::type_id::create("driver", this);
            endfunction
        
 000072     function void connect_phase(uvm_phase phase);
 000072         driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
        
%000000     function bit idle();
%000000         return monitor.idle() && driver.idle();
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 000072         forever begin
 000072             @(negedge vif.ARESETn);
 000072             sequencer.stop_sequences();
                end
            endtask
        endclass
        
