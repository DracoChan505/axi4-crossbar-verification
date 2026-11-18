class axi_master_read_agent extends uvm_agent;
    `uvm_component_utils(axi_master_read_agent)
    axi_master_read_cfg cfg;
    axi_master_read_driver driver;
    axi_master_read_monitor monitor;
    uvm_sequencer#(axi_read_item) sequencer;
    virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        // local variable shadows class member; get into class member directly
        if (!uvm_config_db#(axi_master_read_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = axi_master_read_cfg::type_id::create("cfg");
        end
        cfg.validate();
        // Forward vif and cfg to child components
        if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
            `uvm_fatal("MRAGENT_VIF", "Read master agent: vif missing")
        uvm_config_db#(axi_master_read_cfg)::set(this, "*", "cfg", cfg);
        uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::set(this, "*", "vif", vif);
        monitor = axi_master_read_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer#(axi_read_item)::type_id::create("sequencer", this);
        driver = axi_master_read_driver::type_id::create("driver", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

    function bit idle();
        return monitor.idle() && driver.idle();
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(negedge vif.ARESETn);
            sequencer.stop_sequences();
        end
    endtask
endclass
