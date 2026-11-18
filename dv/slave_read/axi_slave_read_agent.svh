class axi_slave_read_agent extends uvm_agent;
    `uvm_component_utils(axi_slave_read_agent)
    axi_slave_cfg cfg;
    axi_slave_read_driver driver;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        virtual axi_read_if#(ADDR_W, DATA_W, ID_W) vif;
        if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = axi_slave_cfg::type_id::create("cfg");
        end
        cfg.validate();
        if (!uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::get(this, "", "vif", vif))
            `uvm_fatal("SRAGENT_VIF", "Slave read agent: vif missing")
        uvm_config_db#(axi_slave_cfg)::set(this, "*", "cfg", cfg);
        uvm_config_db#(virtual axi_read_if#(ADDR_W, DATA_W, ID_W))::set(this, "*", "vif", vif);
        driver = axi_slave_read_driver::type_id::create("driver", this);
    endfunction
    function bit idle();
        return driver.idle();
    endfunction
endclass
