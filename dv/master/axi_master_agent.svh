class axi_master_agent extends uvm_agent;
    `uvm_component_utils(axi_master_agent)
    axi_master_cfg cfg;
    uvm_sequencer#(axi_write_item) sequencer;
    axi_master_driver driver;
    axi_master_monitor monitor;
    virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(axi_master_cfg)::get(this, "", "cfg", cfg))
            cfg = axi_master_cfg::type_id::create("cfg");
        cfg.validate();
        if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
            `uvm_fatal("VIF", "missing")
        uvm_config_db#(axi_master_cfg)::set(this, "*", "cfg", cfg);
        uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::set(this, "*", "vif", vif);
        monitor = axi_master_monitor::type_id::create("monitor", this);
        if (cfg.active) begin
            sequencer = new("sequencer", this);
            driver = axi_master_driver::type_id::create("driver", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        if (cfg.active)
            driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

    task run_phase(uvm_phase phase);
        if (cfg.active)
            forever begin
            @(negedge vif.ARESETn);
            sequencer.stop_sequences();
        end
    endtask
endclass
