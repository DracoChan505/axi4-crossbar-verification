class axi_slave_agent extends uvm_agent;
    `uvm_component_utils(axi_slave_agent)
    axi_slave_cfg cfg;
    axi_slave_driver driver;
    axi_slave_monitor monitor;
    virtual axi_write_if#(ADDR_W, DATA_W, ID_W) vif;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = axi_slave_cfg::type_id::create("cfg");
        end
        cfg.validate();
        if (!uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif)) begin
            `uvm_fatal("SLAVE_AGENT_VIF", "Agent interface missing")
        end
        uvm_config_db#(axi_slave_cfg)::set(this, "*", "cfg", cfg);
        uvm_config_db#(virtual axi_write_if#(ADDR_W, DATA_W, ID_W))::set(this, "*", "vif", vif);
        monitor = axi_slave_monitor::type_id::create("monitor", this);
        if (cfg.active) begin
            driver = axi_slave_driver::type_id::create("driver", this);
        end
    endfunction
    function bit idle();
        if (!monitor.idle()) begin
            return 0;
        end
        return driver == null ? 1 : driver.idle();
    endfunction
endclass
