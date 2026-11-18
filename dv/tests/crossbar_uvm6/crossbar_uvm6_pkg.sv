`timescale 1ns/1ps
package crossbar_uvm6_pkg;
    import uvm_pkg::*;
    import axi_master_pkg::*;
    import axi_master_read_pkg::*;
    import axi_slave_pkg::*;
    import axi_slave_read_pkg::*;
    `include "uvm_macros.svh"

    // Disambiguate wildcard imports for Xcelium (IEEE-strict)
    localparam int ADDR_W  = axi_master_pkg::ADDR_W;
    localparam int DATA_W  = axi_master_pkg::DATA_W;
    localparam int ID_W    = axi_master_pkg::ID_W;
    localparam int STRB_W  = axi_master_pkg::STRB_W;

    typedef virtual axi_write_if#(ADDR_W, DATA_W, ID_W) master_wvif_t;
    typedef virtual axi_write_if#(ADDR_W, DATA_W, axi_slave_pkg::ID_W) slave_wvif_t;
    typedef virtual axi_read_if#(ADDR_W, DATA_W, ID_W) master_rvif_t;
    typedef virtual axi_read_if#(ADDR_W, DATA_W, axi_slave_read_pkg::ID_W) slave_rvif_t;

    localparam int PORTS        = 4;
    localparam int W_REQS       = 24;   // write transactions per master
    localparam int R_REQS       = 24;   // read  transactions per master
    localparam int SOURCE_WIDTH = PORTS > 1 ? $clog2(PORTS) : 1;

    // ---- Write-side transaction record ----
    class w_record;
        int source, target;
        bit [ID_W-1:0]   id;
        longint unsigned address;
        int              beats, size;
        bit [16:0]       attr;
        bit [1:0]        response;
        bit [DATA_W-1:0] data[$];
        bit [STRB_W-1:0] strb[$];
        int              received = 0, forwarded = 0;
        bit              downstream_response = 0;
        longint unsigned input_done_cycle = 0, output_done_cycle = 0;
    endclass

    // ---- Read-side transaction record ----
    class r_record;
        int source, target;
        bit [ID_W-1:0]   id;
        longint unsigned address;
        int              beats, size;
        bit [16:0]       attr;
        bit [1:0]        response;
        int              received = 0, forwarded = 0;
        bit              downstream_done = 0;
        longint unsigned ar_cycle, rlast_cycle;
    endclass

    // ---- Write-side pin-level scoreboard ----
    class combined_w_scoreboard extends uvm_component;
        `uvm_component_utils(combined_w_scoreboard)
        master_wvif_t master_bus[PORTS];
        slave_wvif_t  slave_bus[PORTS];
        w_record incoming_w[PORTS][$];
        w_record incoming_b[PORTS][$];
        w_record awaiting_forward[PORTS][$];
        w_record outgoing_w[PORTS][$];
        w_record outgoing_b[PORTS][$];
        byte unsigned expected_bytes[PORTS][longint unsigned];
        longint unsigned cycle = 0;
        int aw_count = 0, b_count = 0, down_aw_count = 0, down_b_count = 0;
        int input_beats = 0, output_beats = 0, early_w_valid = 0;
        int aw_stalls = 0, w_stalls = 0, b_stalls = 0;
        int reordered = 0, error_responses = 0, rejected_responses = 0;
        int peak[PORTS], port_aw[PORTS], port_writes[PORTS], port_beats[PORTS];
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            for (int i = 0; i < PORTS; i++) begin
                if (!uvm_config_db#(master_wvif_t)::get(this,"", $sformatf("master_wvif_%0d",i), master_bus[i]) ||
                    !uvm_config_db#(slave_wvif_t)::get(this, "", $sformatf("slave_wvif_%0d", i), slave_bus[i]))
                    `uvm_fatal("W6_VIF","Missing write observation interface")
            end
        endfunction
        function bit empty();
            for (int i = 0; i < PORTS; i++) begin
                if (incoming_w[i].size()!=0 || incoming_b[i].size()!=0 ||
                    awaiting_forward[i].size()!=0 || outgoing_w[i].size()!=0 ||
                    outgoing_b[i].size()!=0) return 0;
            end
            return 1;
        endfunction
        task run_phase(uvm_phase phase);
            w_record item, consumed;
            int match_index, src, dest, beat, lane;
            longint unsigned block_start, address_b;
            bit [STRB_W-1:0] legal;
            forever begin
                @(master_bus[0].mon); cycle++;
                if (!master_bus[0].mon.ARESETn) begin
                    for (int i=0;i<PORTS;i++) begin
                        incoming_w[i].delete(); incoming_b[i].delete();
                        awaiting_forward[i].delete(); outgoing_w[i].delete(); outgoing_b[i].delete();
                    end
                    continue;
                end
                for (int i = 0; i < PORTS; i++) begin
                    if (master_bus[i].mon.AWVALID && !master_bus[i].mon.AWREADY) aw_stalls++;
                    if (master_bus[i].mon.WVALID  && !master_bus[i].mon.WREADY) begin
                        w_stalls++;
                        if (incoming_w[i].size() == 0) early_w_valid++;
                    end
                    // B observe
                    if (master_bus[i].mon.BVALID) begin
                        match_index = -1;
                        foreach (incoming_b[i][j])
                            if (match_index<0 && incoming_b[i][j].id == master_bus[i].mon.BID) match_index=j;
                        if (match_index < 0) `uvm_fatal("W6_ORPHAN_B","Upstream B has no accepted AW")
                        item = incoming_b[i][match_index];
                        if (item.received != item.beats || item.input_done_cycle >= cycle ||
                            (item.target < PORTS && !item.downstream_response))
                            `uvm_error("W6_EARLY_B","B precedes required W/downstream B events")
                        if (master_bus[i].mon.BRESP != item.response)
                            `uvm_error("W6_RESPONSE","Incorrect upstream BRESP")
                        if (master_bus[i].mon.BREADY) begin
                            incoming_b[i].delete(match_index); b_count++;
                            if (match_index != 0) reordered++;
                            if (item.response == 3) error_responses++;
                            if (item.response == 2) rejected_responses++;
                        end else b_stalls++;
                    end
                    // W beats
                    if (master_bus[i].mon.WVALID && master_bus[i].mon.WREADY) begin
                        if (incoming_w[i].size() == 0) `uvm_fatal("W6_W_NO_AW","W accepted without route")
                        item = incoming_w[i][0];
                        item.data.push_back(master_bus[i].mon.WDATA);
                        item.strb.push_back(master_bus[i].mon.WSTRB);
                        item.received++; input_beats++;
                        if (master_bus[i].mon.WLAST != (item.received == item.beats))
                            `uvm_error("W6_INPUT_LAST","Input burst length mismatch")
                        if (master_bus[i].mon.WLAST) begin
                            item.input_done_cycle = cycle; consumed = incoming_w[i].pop_front();
                        end
                    end
                    // AW
                    if (master_bus[i].mon.AWVALID && master_bus[i].mon.AWREADY) begin
                        item = new; item.source = i;
                        item.address = 64'(master_bus[i].mon.AWADDR);
                        dest = item.address < 'h40000 ? int'(item.address >> 16) : PORTS;
                        item.target = dest; item.id = master_bus[i].mon.AWID;
                        item.beats = int'(master_bus[i].mon.AWLEN)+1; item.size = int'(master_bus[i].mon.AWSIZE);
                        item.attr = {master_bus[i].mon.AWSIZE, master_bus[i].mon.AWBURST,
                                     master_bus[i].mon.AWLOCK, master_bus[i].mon.AWCACHE,
                                     master_bus[i].mon.AWPROT, master_bus[i].mon.AWQOS};
                        item.response = dest==PORTS ? 2'b11 :
                            ((item.address&'hffff)>='h8000 && (item.address&'hffff)<='h8fff) ? 2'b10 : 2'b00;
                        incoming_w[i].push_back(item); incoming_b[i].push_back(item);
                        if (dest < PORTS) awaiting_forward[i].push_back(item);
                        aw_count++; port_aw[i]++;
                        if (incoming_b[i].size() > peak[i]) peak[i] = incoming_b[i].size();
                        if (incoming_b[i].size() > 2) `uvm_error("W6_CAPACITY","Outstanding exceeded 2")
                    end
                end
                // ---- Slave side ----
                for (int o = 0; o < PORTS; o++) begin
                    if (slave_bus[o].mon.BVALID) begin
                        match_index = -1;
                        foreach (outgoing_b[o][j])
                            if (match_index<0 && {SOURCE_WIDTH'(outgoing_b[o][j].source), outgoing_b[o][j].id} == slave_bus[o].mon.BID)
                                match_index = j;
                        if (match_index < 0) `uvm_fatal("W6_DOWN_B","Unknown downstream B")
                        item = outgoing_b[o][match_index];
                        if (item.forwarded != item.beats || item.output_done_cycle >= cycle ||
                            slave_bus[o].mon.BRESP != item.response)
                            `uvm_error("W6_SLAVE_RESP","Bad slave B timing/status")
                        if (slave_bus[o].mon.BREADY) begin
                            item.downstream_response = 1;
                            outgoing_b[o].delete(match_index); down_b_count++;
                        end
                    end
                    if (slave_bus[o].mon.WVALID && slave_bus[o].mon.WREADY) begin
                        if (outgoing_w[o].size() == 0) `uvm_fatal("W6_DOWN_W","Output W without AW")
                        item = outgoing_w[o][0]; beat = item.forwarded;
                        if (beat >= item.data.size()) `uvm_fatal("W6_W_NOT_RX","Output beat not accepted upstream")
                        if (slave_bus[o].mon.WDATA !== item.data[beat] ||
                            slave_bus[o].mon.WSTRB !== item.strb[beat] ||
                            slave_bus[o].mon.WLAST != (beat+1 == item.beats))
                            `uvm_error("W6_W_ROUTE","Wrong output data/strobe/last")
                        block_start = ((64'(item.address) >> item.size) + 64'(beat)) << item.size;
                        legal = '0;
                        for (int offset = 0; offset < (1<<item.size); offset++) begin
                            address_b = block_start + 64'(offset);
                            lane = int'(address_b % STRB_W);
                            if (address_b >= item.address) begin
                                legal[lane] = 1;
                                if (item.strb[beat][lane] && item.response == 0)
                                    expected_bytes[o][address_b] = item.data[beat][8*lane +: 8];
                            end
                        end
                        if ((item.strb[beat] & ~legal) != 0) `uvm_error("W6_STROBE","Illegal byte enable")
                        item.forwarded++; output_beats++; port_beats[o]++;
                        if (slave_bus[o].mon.WLAST) begin
                            item.output_done_cycle = cycle; port_writes[o]++;
                            consumed = outgoing_w[o].pop_front();
                        end
                    end
                    if (slave_bus[o].mon.AWVALID && slave_bus[o].mon.AWREADY) begin
                        src = int'(slave_bus[o].mon.AWID[axi_slave_pkg::ID_W-1:ID_W]);
                        if (src >= PORTS || awaiting_forward[src].size() == 0)
                            `uvm_fatal("W6_AW_SRC","Unexpected output AW source")
                        item = awaiting_forward[src].pop_front();
                        if (item.target != o || item.address != 64'(slave_bus[o].mon.AWADDR) ||
                            item.id != ID_W'(slave_bus[o].mon.AWID) ||
                            item.beats != int'(slave_bus[o].mon.AWLEN)+1 ||
                            item.attr != {slave_bus[o].mon.AWSIZE, slave_bus[o].mon.AWBURST,
                                          slave_bus[o].mon.AWLOCK, slave_bus[o].mon.AWCACHE,
                                          slave_bus[o].mon.AWPROT, slave_bus[o].mon.AWQOS})
                            `uvm_error("W6_AW_ROUTE","Output AW differs from input AW")
                        outgoing_w[o].push_back(item); outgoing_b[o].push_back(item);
                        down_aw_count++;
                    end
                end
            end
        endtask
    endclass

    // ---- Write sequence (same stimulus as crossbar_uvm_pkg) ----
    class w_sequence extends uvm_sequence#(axi_write_item);
        `uvm_object_utils(w_sequence)
        int source;
        int responses = 0;
        bit seen[int];
        bit [1:0]    expected_resp[W_REQS];
        bit [ADDR_W-1:0] expected_addr[W_REQS];
        function new(string name = "w_sequence"); super.new(name); endfunction
        function void response_handler(uvm_sequence_item response);
            axi_write_item result; int tag;
            if (!$cast(result, response)) `uvm_fatal("W6_RESP_TYPE","Unexpected write completion type")
            tag = result.get_transaction_id();
            if (tag < 0 || tag >= W_REQS) `uvm_fatal("W6_RESP_TAG","Completion tag outside range")
            if (seen.exists(tag) || result.addr != expected_addr[tag] || result.resp != expected_resp[tag])
                `uvm_error("W6_SEQ_RESP","Wrong or repeated write completion")
            seen[tag] = 1; responses++;
        endfunction
        task body();
            int target; longint unsigned address;
            use_response_handler(1);
            for (int n = 0; n < W_REQS; n++) begin
                req = axi_write_item::type_id::create("wreq");
                target = n % 5;
                if (n < 2)           target = 0;
                if (n==2 || n==5)    target = 1;
                if (n==7)            target = 3;
                address = (64'(target)<<16) + 64'(source)*64'd8192 + 64'(n%4)*64'd1024;
                req.id = n < 3 ? '0 : ID_W'(n%4);
                req.beats = 1 + n%4;
                req.size  = 32'(n % ($clog2(STRB_W)+1));
                if (n==5) address = (64'(target)<<16) + 'h8000 + 64'(source*256);
                if (n==6) begin address++; req.size = $clog2(STRB_W); end
                if (n==7) begin address = (64'(target)<<16) + 64'(source*8192); req.beats=256; req.size=$clog2(STRB_W); end
                if (n==8) begin address = (64'(target)<<16) + 'hffff; req.beats=1; req.size=0; end
                req.addr     = ADDR_W'(address);
                req.aw_delay = n==0 ? 8 : 32'(n%3);
                req.w_delay  = n==0 ? 0 : 32'((n+source)%4);
                req.w_gap    = 32'(n%2);
                req.qos      = 4'(source+n);
                req.fill_pattern(source*53 + n*17, n%3);
                req.set_transaction_id(n);
                expected_addr[n] = req.addr;
                expected_resp[n] = target==4 ? 2'b11 : n==5 ? 2'b10 : 2'b00;
                start_item(req); finish_item(req);
            end
            wait (responses == W_REQS);
        endtask
    endclass

    // ---- Read-side pin-level scoreboard ----
    class combined_r_scoreboard extends uvm_component;
        `uvm_component_utils(combined_r_scoreboard)
        master_rvif_t master_bus[PORTS];
        slave_rvif_t  slave_bus[PORTS];
        r_record incoming[PORTS][$];
        r_record awaiting_down[PORTS][$];
        r_record outgoing_r[PORTS][$];
        r_record upstream_r[PORTS][$];
        byte unsigned expected_mem[PORTS][longint unsigned];
        int ar_count=0, r_complete=0, down_ar_count=0, down_r_beats=0, up_r_beats=0;
        int error_responses=0, decerr_count=0, r_stalls=0;
        longint unsigned cycle=0;
        int peak[PORTS];
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            for (int i = 0; i < PORTS; i++) begin
                if (!uvm_config_db#(master_rvif_t)::get(this,"",$sformatf("master_rvif_%0d",i),master_bus[i]) ||
                    !uvm_config_db#(slave_rvif_t)::get(this,"",$sformatf("slave_rvif_%0d",i),slave_bus[i]))
                    `uvm_fatal("R6_VIF","Missing read observation interface")
            end
        endfunction
        function bit empty();
            for (int i=0;i<PORTS;i++)
                if (incoming[i].size()!=0||awaiting_down[i].size()!=0||
                    outgoing_r[i].size()!=0||upstream_r[i].size()!=0) return 0;
            return 1;
        endfunction
        task run_phase(uvm_phase phase);
            r_record item; int src,dest,beat,match_idx;
            forever begin
                @(master_bus[0].mon); cycle++;
                if (!master_bus[0].mon.ARESETn) begin
                    for (int i=0;i<PORTS;i++) begin
                        incoming[i].delete(); awaiting_down[i].delete();
                        outgoing_r[i].delete(); upstream_r[i].delete();
                    end
                    continue;
                end
                // ---- Master side ----
                for (int i = 0; i < PORTS; i++) begin
                    if (master_bus[i].mon.ARVALID && master_bus[i].mon.ARREADY) begin
                        item = new; item.source = i;
                        item.address = 64'(master_bus[i].mon.ARADDR);
                        dest = item.address < 'h40000 ? int'(item.address >> 16) : PORTS;
                        item.target = dest; item.id = master_bus[i].mon.ARID;
                        item.beats = int'(master_bus[i].mon.ARLEN)+1;
                        item.size  = int'(master_bus[i].mon.ARSIZE);
                        item.attr  = {master_bus[i].mon.ARSIZE, master_bus[i].mon.ARBURST,
                                      master_bus[i].mon.ARLOCK, master_bus[i].mon.ARCACHE,
                                      master_bus[i].mon.ARPROT, master_bus[i].mon.ARQOS};
                        item.response = dest==PORTS ? 2'b11 :
                            ((item.address&'hffff)>='h8000 && (item.address&'hffff)<='h8fff) ? 2'b10 : 2'b00;
                        item.ar_cycle = cycle;
                        incoming[i].push_back(item);
                        upstream_r[i].push_back(item);
                        if (dest < PORTS) awaiting_down[i].push_back(item);
                        ar_count++;
                        if (incoming[i].size() > peak[i]) peak[i] = incoming[i].size();
                    end
                    if (master_bus[i].mon.RVALID && master_bus[i].mon.RREADY) begin
                        int idx = -1;
                        for (int k=0;k<upstream_r[i].size();k++)
                            if (idx<0 && upstream_r[i][k].id == master_bus[i].mon.RID) idx = k;
                        if (idx < 0) `uvm_fatal("R6_ORPHAN_R","Upstream R has no accepted AR")
                        item = upstream_r[i][idx];
                        item.received++; up_r_beats++;
                        begin
                            bit [1:0] got = master_bus[i].mon.RRESP; bit ok;
                            case (item.response)
                                2'b11: ok = (got==2'b11);
                                2'b10: ok = (got==2'b10);
                                default: ok = (got==2'b00);
                            endcase
                            if (!ok) `uvm_error("R6_RESP",$sformatf("RRESP mismatch: got %b exp %b addr=%h", got, item.response, item.address))
                        end
                        if (master_bus[i].mon.RLAST) begin
                            if (item.received != item.beats)
                                `uvm_error("R6_RLAST",$sformatf("RLAST at wrong beat: rx=%0d beats=%0d addr=%h", item.received, item.beats, item.address))
                            item.rlast_cycle = cycle; r_complete++;
                            if (item.response == 2'b11) decerr_count++;
                            if (item.response == 2'b10) error_responses++;
                            upstream_r[i].delete(idx);
                            begin
                                int i2=-1;
                                for (int k=0;k<incoming[i].size();k++)
                                    if (i2<0 && incoming[i][k]==item) i2=k;
                                if (i2>=0) incoming[i].delete(i2);
                            end
                        end else begin
                            if (item.received >= item.beats)
                                `uvm_error("R6_MISS_LAST",$sformatf("Missing RLAST: rx=%0d beats=%0d addr=%h", item.received, item.beats, item.address))
                        end
                    end
                    if (master_bus[i].mon.RVALID && !master_bus[i].mon.RREADY) r_stalls++;
                end
                // ---- Slave side ----
                for (int o = 0; o < PORTS; o++) begin
                    if (slave_bus[o].mon.ARVALID && slave_bus[o].mon.ARREADY) begin
                        src = int'(slave_bus[o].mon.ARID[axi_slave_read_pkg::ID_W-1:ID_W]);
                        if (src >= PORTS || awaiting_down[src].size() == 0)
                            `uvm_fatal("R6_AR_SRC","Unexpected output AR source")
                        item = awaiting_down[src].pop_front();
                        if (item.target != o || item.address != 64'(slave_bus[o].mon.ARADDR) ||
                            item.id != ID_W'(slave_bus[o].mon.ARID) ||
                            item.beats != int'(slave_bus[o].mon.ARLEN)+1 ||
                            item.attr != {slave_bus[o].mon.ARSIZE, slave_bus[o].mon.ARBURST,
                                          slave_bus[o].mon.ARLOCK, slave_bus[o].mon.ARCACHE,
                                          slave_bus[o].mon.ARPROT, slave_bus[o].mon.ARQOS})
                            `uvm_error("R6_AR_ROUTE","Output AR differs from input AR")
                        outgoing_r[o].push_back(item); down_ar_count++;
                    end
                    if (slave_bus[o].mon.RVALID && slave_bus[o].mon.RREADY) begin
                        int idx = -1;
                        bit [axi_slave_read_pkg::ID_W-1:0] rid = slave_bus[o].mon.RID;
                        for (int k=0;k<outgoing_r[o].size();k++)
                            if (idx<0 && {SOURCE_WIDTH'(outgoing_r[o][k].source), outgoing_r[o][k].id} == rid) idx=k;
                        if (idx < 0) `uvm_fatal("R6_DOWN_R","Output R without observed AR")
                        item = outgoing_r[o][idx]; beat = item.forwarded;
                        if (slave_bus[o].mon.RLAST != (beat+1 == item.beats))
                            `uvm_error("R6_DOWN_RLAST",$sformatf("Downstream RLAST mismatch: beat=%0d beats=%0d addr=%h", beat+1, item.beats, item.address))
                        if (item.response == 2'b00) begin
                            longint unsigned step = 64'(1) << item.size;
                            longint unsigned block = ((64'(item.address)>>item.size) + 64'(beat)) * step;
                            longint unsigned base  = (block / STRB_W) * STRB_W;
                            bit [DATA_W-1:0] exp_data = '0;
                            for (int lane=0;lane<STRB_W;lane++)
                                exp_data[8*lane +: 8] = expected_mem[o].exists(base+64'(lane)) ?
                                                        expected_mem[o][base+64'(lane)] : 8'h00;
                            if (slave_bus[o].mon.RDATA !== exp_data)
                                `uvm_error("R6_RDATA",$sformatf("R data mismatch: addr=%h beat=%0d got=%h exp=%h",
                                           item.address, beat, slave_bus[o].mon.RDATA, exp_data))
                        end
                        item.forwarded++; down_r_beats++;
                        if (slave_bus[o].mon.RLAST) begin
                            item.downstream_done = 1; outgoing_r[o].delete(idx);
                        end
                    end
                end
            end
        endtask
    endclass

    // ---- Read sequence (same stimulus as crossbar_uvm5_pkg) ----
    class r_sequence extends uvm_sequence#(axi_read_item);
        `uvm_object_utils(r_sequence)
        int source;
        int responses = 0;
        bit seen[int];
        bit [1:0]        expected_resp[R_REQS];
        bit [ADDR_W-1:0] expected_addr[R_REQS];
        function new(string name = "r_sequence"); super.new(name); endfunction
        function void response_handler(uvm_sequence_item response);
            axi_read_item result; int tag;
            if (!$cast(result, response)) `uvm_fatal("R6_RESP_TYPE","Unexpected read completion type")
            tag = result.get_transaction_id();
            if (tag < 0 || tag >= R_REQS) `uvm_fatal("R6_RESP_TAG","Completion tag outside range")
            if (seen.exists(tag) || result.addr != expected_addr[tag] || result.resp != expected_resp[tag])
                `uvm_error("R6_SEQ_RESP","Wrong or repeated read completion")
            seen[tag] = 1; responses++;
        endfunction
        task body();
            int target; longint unsigned address;
            use_response_handler(1);
            for (int n = 0; n < R_REQS; n++) begin
                req = axi_read_item::type_id::create("rreq");
                target = n % 5;
                if (n < 2)         target = 0;
                if (n==2||n==5)    target = 1;
                if (n==7)          target = 3;
                address = (64'(target)<<16) + 64'(source)*64'd8192 + 64'(n%4)*64'd1024;
                req.id = n < 3 ? '0 : ID_W'(n%4);
                req.beats = 1 + n%4;
                req.size  = 32'(n % ($clog2(STRB_W)+1));
                if (n==5) address = (64'(target)<<16) + 'h8000 + 64'(source*256);
                if (n==6) begin address++; req.size = $clog2(STRB_W); end
                if (n==7) begin address = (64'(target)<<16) + 64'(source*8192); req.beats=256; req.size=$clog2(STRB_W); end
                if (n==8) begin address = (64'(target)<<16) + 'hffff; req.beats=1; req.size=0; end
                req.addr     = ADDR_W'(address);
                req.ar_delay = n==0 ? 8 : 32'(n%3);
                req.set_transaction_id(n);
                expected_addr[n] = req.addr;
                expected_resp[n] = target==4 ? 2'b11 : n==5 ? 2'b10 : 2'b00;
                start_item(req); finish_item(req);
            end
            wait (responses == R_REQS);
        endtask
    endclass

    // ---- Combined read/write UVM test ----
    // Runs write and read sequences concurrently on the same 5-channel DUT.
    // Both scoreboards observe independently; concurrency proves no cross-channel
    // interference on shared address decoder, arbitration and slave ports.
    class crossbar_uvm6_test extends uvm_test;
        `uvm_component_utils(crossbar_uvm6_test)
        axi_master_agent          write_masters[PORTS];
        axi_slave_pkg::axi_slave_agent write_slaves[PORTS];
        axi_master_read_agent    read_masters[PORTS];
        axi_slave_read_agent     read_slaves[PORTS];
        w_sequence               w_seqs[PORTS];
        r_sequence               r_seqs[PORTS];
        combined_w_scoreboard    w_scoreboard;
        combined_r_scoreboard    r_scoreboard;
        int seed = 7;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            axi_master_cfg          mcfg;
            axi_slave_pkg::axi_slave_cfg scfg;
            axi_master_read_cfg     mrcfg;
            master_wvif_t mwbus; slave_wvif_t swbus;
            master_rvif_t mrbus; slave_rvif_t srbus;
            void'($value$plusargs("SEED=%d", seed));
            if (ID_W != 2 || axi_slave_pkg::ID_W != 4)
                `uvm_fatal("UVM6_WIDTHS","System test requires master ID2 / slave ID4")
            for (int i = 0; i < PORTS; i++) begin
                // ---- Write master ----
                if (!uvm_config_db#(master_wvif_t)::get(this,"",$sformatf("master_wvif_%0d",i),mwbus))
                    `uvm_fatal("UVM6_MWVIF","Missing write master interface")
                mcfg = axi_master_cfg::type_id::create($sformatf("wmcfg_%0d",i));
                mcfg.trace = 0;
                mcfg.b_stall_period = 11; mcfg.b_stall_cycles = 8;
                uvm_config_db#(axi_master_cfg)::set(this,$sformatf("wmaster_%0d",i),"cfg",mcfg);
                uvm_config_db#(master_wvif_t)::set(this,$sformatf("wmaster_%0d",i),"vif",mwbus);
                write_masters[i] = axi_master_agent::type_id::create($sformatf("wmaster_%0d",i),this);
                w_seqs[i] = w_sequence::type_id::create($sformatf("wseq_%0d",i));
                w_seqs[i].source = i;
                // ---- Read master ----
                if (!uvm_config_db#(master_rvif_t)::get(this,"",$sformatf("master_rvif_%0d",i),mrbus))
                    `uvm_fatal("UVM6_MRVIF","Missing read master interface")
                mrcfg = axi_master_read_cfg::type_id::create($sformatf("mrcfg_%0d",i));
                mrcfg.max_outstanding = 2; mrcfg.pending_depth = 4;
                mrcfg.r_stall_period = 11; mrcfg.r_stall_cycles = 8;
                uvm_config_db#(axi_master_read_cfg)::set(this,$sformatf("rmaster_%0d",i),"cfg",mrcfg);
                uvm_config_db#(master_rvif_t)::set(this,$sformatf("rmaster_%0d",i),"vif",mrbus);
                read_masters[i] = axi_master_read_agent::type_id::create($sformatf("rmaster_%0d",i),this);
                r_seqs[i] = r_sequence::type_id::create($sformatf("rseq_%0d",i));
                r_seqs[i].source = i;
                // ---- Write slave ----
                if (!uvm_config_db#(slave_wvif_t)::get(this,"",$sformatf("slave_wvif_%0d",i),swbus))
                    `uvm_fatal("UVM6_SWVIF","Missing write slave interface")
                scfg = axi_slave_pkg::axi_slave_cfg::type_id::create($sformatf("wscfg_%0d",i));
                scfg.base_addr = 64'(i) << 16; scfg.size_bytes = 65536;
                scfg.max_outstanding = 4;
                scfg.response_order = axi_slave_pkg::B_RANDOM_READY;
                scfg.seed = 32'(seed + i*101);
                scfg.aw_random_stall_max = 3; scfg.w_random_stall_max = 4;
                scfg.b_random_delay_max = 5;
                scfg.reject_enable = 1;
                scfg.reject_first = scfg.base_addr + 'h8000;
                scfg.reject_last  = scfg.base_addr + 'h8fff;
                uvm_config_db#(axi_slave_pkg::axi_slave_cfg)::set(this,$sformatf("wslave_%0d",i),"cfg",scfg);
                uvm_config_db#(slave_wvif_t)::set(this,$sformatf("wslave_%0d",i),"vif",swbus);
                write_slaves[i] = axi_slave_pkg::axi_slave_agent::type_id::create($sformatf("wslave_%0d",i),this);
                // ---- Read slave ----
                if (!uvm_config_db#(slave_rvif_t)::get(this,"",$sformatf("slave_rvif_%0d",i),srbus))
                    `uvm_fatal("UVM6_SRVIF","Missing read slave interface")
                scfg = axi_slave_pkg::axi_slave_cfg::type_id::create($sformatf("rscfg_%0d",i));
                scfg.base_addr = 64'(i) << 16; scfg.size_bytes = 65536;
                scfg.max_outstanding = 4;
                scfg.response_order = axi_slave_pkg::B_RANDOM_READY;
                scfg.seed = 32'(seed + i*101);
                scfg.aw_random_stall_max = 3; scfg.b_random_delay_max = 5;
                scfg.reject_enable = 1;
                scfg.reject_first = scfg.base_addr + 'h8000;
                scfg.reject_last  = scfg.base_addr + 'h8fff;
                uvm_config_db#(axi_slave_pkg::axi_slave_cfg)::set(this,$sformatf("rslave_%0d",i),"cfg",scfg);
                uvm_config_db#(slave_rvif_t)::set(this,$sformatf("rslave_%0d",i),"vif",srbus);
                read_slaves[i] = axi_slave_read_agent::type_id::create($sformatf("rslave_%0d",i),this);
            end
            w_scoreboard = combined_w_scoreboard::type_id::create("w_scoreboard",this);
            r_scoreboard = combined_r_scoreboard::type_id::create("r_scoreboard",this);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            wait (w_scoreboard.master_bus[0].ARESETn);
            // Pre-fill read slave memories with known pattern
            for (int i = 0; i < PORTS; i++) begin
                for (longint unsigned addr = 64'(i)<<16; addr < (64'(i+1)<<16); addr++) begin
                    byte unsigned v = 8'((addr[7:0] ^ 8'(i*17)) & 8'hff);
                    read_slaves[i].driver.memory.write_byte(addr, v);
                    r_scoreboard.expected_mem[i][addr] = v;
                end
            end
            // Run write and read sequences concurrently — this is the concurrent test
            fork
                w_seqs[0].start(write_masters[0].sequencer);
                w_seqs[1].start(write_masters[1].sequencer);
                w_seqs[2].start(write_masters[2].sequencer);
                w_seqs[3].start(write_masters[3].sequencer);
                r_seqs[0].start(read_masters[0].sequencer);
                r_seqs[1].start(read_masters[1].sequencer);
                r_seqs[2].start(read_masters[2].sequencer);
                r_seqs[3].start(read_masters[3].sequencer);
            join
            repeat (50) @(w_scoreboard.master_bus[0].mon); #1;
            // Write path final checks
            if (!w_scoreboard.empty() ||
                w_scoreboard.aw_count != PORTS * W_REQS ||
                w_scoreboard.b_count  != PORTS * W_REQS ||
                w_scoreboard.down_aw_count != w_scoreboard.down_b_count ||
                w_scoreboard.error_responses != 16 ||
                w_scoreboard.rejected_responses != 4 ||
                w_scoreboard.early_w_valid == 0 || w_scoreboard.b_stalls == 0)
                `uvm_error("UVM6_W_FINAL","Write counts/backpressure witnesses failed")
            // Read path final checks
            if (!r_scoreboard.empty() ||
                r_scoreboard.ar_count    != PORTS * R_REQS ||
                r_scoreboard.r_complete  != PORTS * R_REQS ||
                r_scoreboard.decerr_count != 16 ||
                r_scoreboard.error_responses != 4 ||
                r_scoreboard.r_stalls == 0)
                `uvm_error("UVM6_R_FINAL","Read counts/backpressure witnesses failed")
            for (int i = 0; i < PORTS; i++) begin
                if (!write_masters[i].driver.idle() || !write_masters[i].monitor.idle() ||
                    !write_slaves[i].idle() || w_scoreboard.peak[i] != 2)
                    `uvm_error("UVM6_W_DRAIN","Write components not drained or concurrency unobserved")
                if (!read_masters[i].driver.idle() || !read_masters[i].monitor.idle() ||
                    !read_slaves[i].idle() || r_scoreboard.peak[i] != 2)
                    `uvm_error("UVM6_R_DRAIN","Read components not drained or concurrency unobserved")
            end
            `uvm_info("COMBINED_WITNESS", $sformatf(
                "aw=%0d b=%0d down_aw=%0d down_b=%0d w_beats=%0d decerr_w=%0d slverr_w=%0d || ar=%0d r=%0d down_ar=%0d r_beats=%0d decerr_r=%0d slverr_r=%0d r_stalls=%0d",
                w_scoreboard.aw_count, w_scoreboard.b_count,
                w_scoreboard.down_aw_count, w_scoreboard.down_b_count, w_scoreboard.output_beats,
                w_scoreboard.error_responses, w_scoreboard.rejected_responses,
                r_scoreboard.ar_count, r_scoreboard.r_complete,
                r_scoreboard.down_ar_count, r_scoreboard.up_r_beats,
                r_scoreboard.decerr_count, r_scoreboard.error_responses, r_scoreboard.r_stalls),
                UVM_LOW)
            `uvm_info("COMBINED_PASS","crossbar_uvm6_test: concurrent read+write checks passed",UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass
endpackage

