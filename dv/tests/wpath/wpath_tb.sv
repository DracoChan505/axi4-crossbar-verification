`timescale 1ns/1ps
module wpath_tb;
    parameter int INPUTS = 4;
    parameter int SLAVES = 4;
    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    parameter int INPUT_LIMIT = 2;
    parameter int OUTPUT_LIMIT = 4;
    localparam int ID_WIDTH = 2;
    localparam int OUTPUTS = SLAVES + 1;
    localparam int SOURCE_WIDTH = INPUTS > 1 ? $clog2(INPUTS) : 1;
    localparam int TARGET_WIDTH = $clog2(OUTPUTS);
    localparam int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_base;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_limit;
    logic [INPUTS-1:0] s_awvalid = '0;
    logic [INPUTS-1:0] s_awready;
    logic [INPUTS-1:0][ID_WIDTH-1:0] s_awid = '0;
    logic [INPUTS-1:0][ADDR_WIDTH-1:0] s_awaddr = '0;
    logic [INPUTS-1:0][7:0] s_awlen = '0;
    logic [INPUTS-1:0][16:0] s_awattr = '0;
    logic [OUTPUTS-1:0] m_awvalid;
    logic [OUTPUTS-1:0] m_awready = '0;
    logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] m_awid;
    logic [OUTPUTS-1:0][ADDR_WIDTH-1:0] m_awaddr;
    logic [OUTPUTS-1:0][7:0] m_awlen;
    logic [OUTPUTS-1:0][16:0] m_awattr;
    logic [INPUTS-1:0] complete_valid = '0;
    logic [INPUTS-1:0][ID_WIDTH-1:0] complete_id = '0;
    logic [OUTPUTS-1:0] release_valid = '0;
    logic [INPUTS-1:0] w_target_valid;
    logic [INPUTS-1:0] w_target_ready;
    logic [INPUTS-1:0][TARGET_WIDTH-1:0] w_target;
    logic [INPUTS-1:0][7:0] w_target_len;
    logic [OUTPUTS-1:0] w_source_valid;
    logic [OUTPUTS-1:0] w_source_ready;
    logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] w_source;
    logic [OUTPUTS-1:0][7:0] w_source_len;
    logic [INPUTS-1:0] s_wvalid = '0;
    logic [INPUTS-1:0] s_wready;
    logic [INPUTS-1:0][DATA_WIDTH-1:0] s_wdata = '0;
    logic [INPUTS-1:0][STRB_WIDTH-1:0] s_wstrb = '0;
    logic [INPUTS-1:0] s_wlast = '0;
    logic [OUTPUTS-1:0] m_wvalid;
    logic [OUTPUTS-1:0] m_wready = '0;
    logic [OUTPUTS-1:0][DATA_WIDTH-1:0] m_wdata;
    logic [OUTPUTS-1:0][STRB_WIDTH-1:0] m_wstrb;
    logic [OUTPUTS-1:0] m_wlast;
    typedef struct packed {
        logic [DATA_WIDTH-1:0] data;
        logic [STRB_WIDTH-1:0] strb;
        logic last;
    } beat_t;
    beat_t input_beats [INPUTS][$];
    typedef struct packed {
        int source;
        int dest;
        logic [ID_WIDTH-1:0] id;
        logic [ADDR_WIDTH-1:0] addr;
        logic [7:0] len;
        logic [16:0] attr;
    } transaction_t;
    transaction_t planned_w [INPUTS][$];
    int driver_index [INPUTS];
    transaction_t addresses [INPUTS][$];
    transaction_t routes [INPUTS][$];
    transaction_t sources [OUTPUTS][$];
    transaction_t responses [OUTPUTS][$];
    transaction_t upstream_responses [INPUTS][$];
    int id_count [INPUTS][1 << ID_WIDTH];
    int id_target [INPUTS][1 << ID_WIDTH];
    int input_count [INPUTS];
    int slave_count [OUTPUTS];
    int w_progress [OUTPUTS];
    int sequence_number [INPUTS];
    int accepted = 0;
    int forwarded = 0;
    int completed = 0;
    int cancelled = 0;
    int blocked = 0;
    int id_blocked = 0;
    int repeated_id = 0;
    int parallel_aw = 0;
    int error_target = 0;
    int peak_output = 0;
    int cycles = 0;
    int seed = 7;
    int input_w_count = 0;
    int output_w_count = 0;
    int cancelled_beats = 0;
    int early_w_stalls = 0;
    int full_buffer_stalls = 0;
    int output_w_stalls = 0;
    int parallel_w = 0;
    int zero_strobes = 0;
    int sparse_strobes = 0;
    int maximum_buffered = 0;
    bit bad_early;
    bit bad_missing;

    axi_write_frontend #(
        .INPUTS(INPUTS), .SLAVES(SLAVES), .ADDR_WIDTH(ADDR_WIDTH),
        .INPUT_LIMIT(INPUT_LIMIT), .OUTPUT_LIMIT(OUTPUT_LIMIT)
    ) dut (.*);

    axi_write_data_path #(
        .INPUTS(INPUTS), .OUTPUTS(OUTPUTS), .DATA_WIDTH(DATA_WIDTH)
    ) data_path (.*);

    function int decode_reference(logic [ADDR_WIDTH-1:0] addr);
        // Test windows are contiguous 64 KiB windows, including relocated high bits.
        logic [ADDR_WIDTH-1:0] relative_address;
        relative_address = addr - map_base[0];
        if (addr >= map_base[0] && (relative_address >> 16) < ADDR_WIDTH'(SLAVES)) begin
            return int'(relative_address >> 16);
        end
        return SLAVES;
    endfunction

    task reset_control();
        @(negedge clk);
        reset_n = 0;
        s_awvalid = '0;
        complete_valid = '0;
        release_valid = '0;
        m_awready = '0;
        s_wvalid = '0;
        m_wready = '0;
        for (int i = 0; i < INPUTS; i++) begin
            cancelled += input_count[i];
            input_count[i] = 0;
            addresses[i].delete();
            cancelled_beats += input_beats[i].size();
            input_beats[i].delete();
            planned_w[i].delete();
            driver_index[i] = 0;
            routes[i].delete();
            upstream_responses[i].delete();
            sequence_number[i] = 0;
            for (int id = 0; id < (1 << ID_WIDTH); id++) begin
                id_count[i][id] = 0;
                id_target[i][id] = 0;
            end
        end
        for (int o = 0; o < OUTPUTS; o++) begin
            sources[o].delete();
            responses[o].delete();
            slave_count[o] = 0;
            w_progress[o] = 0;
        end
        #1;
        if (s_awready != 0 || m_awvalid != 0 || w_target_valid != 0 || w_source_valid != 0 || s_wready != 0 || m_wvalid != 0) begin
            $fatal(1, "RESET_STATE");
        end
        @(negedge clk);
        reset_n = 1;
    endtask

    task tick(int phase, bit generate_traffic);
        transaction_t item;
        transaction_t removed;
        int dest;
        int src;
        int aw_parallel;
        int w_parallel;
        beat_t observed;
        int n;
        @(negedge clk);
        for (int i = 0; i < INPUTS; i++) begin
            if (!s_awvalid[i] && generate_traffic && $urandom_range(3, 0) != 0) begin
                n = sequence_number[i];
                dest = n < 2 ? 0 : int'($urandom_range(SLAVES, 0));
                if (n == 2) begin
                    dest = 1;
                end
                s_awvalid[i] = 1;
                s_awid[i] = n <= 2 ? '0 : ID_WIDTH'(n % (1 << ID_WIDTH));
                s_awaddr[i] = map_base[0] + (ADDR_WIDTH'(dest) << 16) +
                              (ADDR_WIDTH'(n % 16) << 12);
                s_awlen[i] = n == 2 ? 8'd255 : 8'($urandom_range(3, 0));
                s_awattr[i] = {3'($clog2(STRB_WIDTH)), 2'b01, 1'b0, 4'd2, 3'd2, 4'(n)};
                item.source = i;
                item.dest = dest;
                item.id = s_awid[i];
                item.addr = s_awaddr[i];
                item.len = s_awlen[i];
                item.attr = s_awattr[i];
                planned_w[i].push_back(item);
                sequence_number[i]++;
            end
        end
        release_valid = '0;
        complete_valid = '0;
        for (int i = 0; i < INPUTS; i++) begin
            if (!s_wvalid[i] && planned_w[i].size() != 0 && $urandom_range(3, 0) != 0) begin
                item = planned_w[i][0];
                s_wvalid[i] = 1;
                for (int lane = 0; lane < STRB_WIDTH; lane++) begin
                    s_wdata[i][8*lane +: 8] = 8'(int'(item.addr >> 12) * 31 + i * 47 + driver_index[i] * 13 + lane * 19);
                end
                case (driver_index[i] % 4)
                    0: s_wstrb[i] = '1;
                    1: s_wstrb[i] = '0;
                    2: s_wstrb[i] = STRB_WIDTH'(1);
                    default: s_wstrb[i] = STRB_WIDTH'('h55);
                endcase
                s_wlast[i] = driver_index[i] == int'(item.len);
                if (i == 0 && bad_early && driver_index[i] == 0 && item.len != 0) begin
                    s_wlast[i] = 1;
                end
                if (i == 0 && bad_missing && driver_index[i] == int'(item.len)) begin
                    s_wlast[i] = 0;
                end
            end
        end
        for (int o = 0; o < OUTPUTS; o++) begin
            m_awready[o] = phase >= 20 && $urandom_range(3, 0) != 0;
            m_wready[o] = phase >= 80 && $urandom_range(3, 0) != 0;
            if (w_source_valid[o]) begin
                src = int'(w_source[o]);
                if (src >= INPUTS || sources[o].size() == 0 ||
                    sources[o][0].source != src || sources[o][0].len != w_source_len[o]) begin
                    $fatal(1, "SOURCE_QUEUE");
                end
            end
            if (responses[o].size() != 0 && phase >= 100 && $urandom_range(2, 0) != 0) begin
                release_valid[o] = 1;
            end
        end
        for (int i = 0; i < INPUTS; i++) begin
            if (w_target_valid[i]) begin
                if (routes[i].size() == 0 || routes[i][0].dest != int'(w_target[i]) ||
                    routes[i][0].len != w_target_len[i]) begin
                    $fatal(1, "TARGET_QUEUE");
                end
            end
            if (upstream_responses[i].size() != 0 && phase >= 140 && $urandom_range(2, 0) != 0) begin
                complete_valid[i] = 1;
                complete_id[i] = upstream_responses[i][0].id;
            end
        end
        #1;
        @(posedge clk);
        aw_parallel = 0;
        w_parallel = 0;
        // Check pre-edge limits before this edge's completions can free slots.
        for (int i = 0; i < INPUTS; i++) begin
            if (s_awvalid[i] && !s_awready[i]) begin
                blocked++;
                if (input_count[i] < INPUT_LIMIT && id_count[i][s_awid[i]] != 0 &&
                    id_target[i][s_awid[i]] != decode_reference(s_awaddr[i])) begin
                    id_blocked++;
                end
            end
            if (s_awvalid[i] && s_awready[i]) begin
                dest = decode_reference(s_awaddr[i]);
                if (input_count[i] >= INPUT_LIMIT ||
                    (id_count[i][s_awid[i]] != 0 && id_target[i][s_awid[i]] != dest)) begin
                    $fatal(1, "INPUT_ADMISSION");
                end
            end
        end
        for (int i = 0; i < INPUTS; i++) begin
            if (complete_valid[i]) begin
                item = upstream_responses[i].pop_front();
                if (id_count[i][item.id] == 0) begin
                    $fatal(1, "COMPLETE_UNKNOWN");
                end
                id_count[i][item.id]--;
                input_count[i]--;
                completed++;
            end
        end
        for (int o = 0; o < OUTPUTS; o++) begin
            if (release_valid[o]) begin
                item = responses[o].pop_front();
                upstream_responses[item.source].push_back(item);
                slave_count[o]--;
            end
            if (m_wvalid[o] && !m_wready[o]) begin
                output_w_stalls++;
            end
            if (m_wvalid[o]) begin
                if (sources[o].size() == 0) begin
                    $fatal(1, "W_WITHOUT_AW");
                end
                item = sources[o][0];
                src = item.source;
                if (input_beats[src].size() == 0) begin
                    $fatal(1, "W_WITHOUT_INPUT_BEAT");
                end
                observed = input_beats[src][0];
                if ({m_wdata[o], m_wstrb[o], m_wlast[o]} !== observed ||
                    m_wlast[o] != (w_progress[o] == int'(item.len))) begin
                    $fatal(1, "W_PAYLOAD_OR_ORDER");
                end
            end
            if (w_source_ready[o] != (m_wvalid[o] && m_wready[o] && m_wlast[o])) begin
                $fatal(1, "SOURCE_POP_TIMING");
            end
            if (m_wvalid[o] && m_wready[o]) begin
                item = sources[o][0];
                observed = input_beats[item.source].pop_front();
                w_progress[o]++;
                output_w_count++;
                w_parallel++;
                if (m_wlast[o]) begin
                    item = sources[o].pop_front();
                    removed = routes[item.source].pop_front();
                    if (item != removed || !w_target_ready[item.source] ||
                        w_progress[o] != int'(item.len) + 1) begin
                        $fatal(1, "W_PAIRING");
                    end
                    w_progress[o] = 0;
                    responses[o].push_back(item);
                end
                else if (w_target_ready[item.source]) begin
                    $fatal(1, "TARGET_POP_EARLY");
                end
            end
            if (m_awvalid[o] && m_awready[o]) begin
                src = int'(m_awid[o][OUTPUT_ID_WIDTH-1:ID_WIDTH]);
                if (src >= INPUTS || addresses[src].size() == 0) begin
                    $fatal(1, "UNEXPECTED_AW");
                end
                item = addresses[src].pop_front();
                if (item.dest != o || item.id != ID_WIDTH'(m_awid[o]) ||
                    item.addr != m_awaddr[o] || item.len != m_awlen[o] || item.attr != m_awattr[o]) begin
                    $fatal(1, "AW_PAYLOAD_OR_ORDER");
                end
                sources[o].push_back(item);
                slave_count[o]++;
                if (slave_count[o] > OUTPUT_LIMIT) begin
                    $fatal(1, "OUTPUT_CAPACITY");
                end
                if (slave_count[o] > peak_output) begin
                    peak_output = slave_count[o];
                end
                forwarded++;
                aw_parallel++;
                if (o == SLAVES) begin
                    error_target++;
                end
            end
        end
        if (w_parallel > 1) begin
            parallel_w++;
        end
        for (int i = 0; i < INPUTS; i++) begin
            if (s_wvalid[i] && !s_wready[i]) begin
                if (routes[i].size() == 0) begin
                    early_w_stalls++;
                end
                if (input_beats[i].size() == 2) begin
                    full_buffer_stalls++;
                end
            end
            if (s_wvalid[i] && s_wready[i]) begin
                if (planned_w[i].size() == 0 || routes[i].size() == 0) begin
                    $fatal(1, "EARLY_W_ACCEPTED");
                end
                input_beats[i].push_back({s_wdata[i], s_wstrb[i], s_wlast[i]});
                input_w_count++;
                if (s_wstrb[i] == 0) begin
                    zero_strobes++;
                end
                else if (s_wstrb[i] != {STRB_WIDTH{1'b1}}) begin
                    sparse_strobes++;
                end
                if (driver_index[i] == int'(planned_w[i][0].len)) begin
                    removed = planned_w[i].pop_front();
                    driver_index[i] = 0;
                end
                else begin
                    driver_index[i]++;
                end
            end
            if (input_beats[i].size() > 2) begin
                $fatal(1, "BUFFER_OVERFLOW");
            end
            if (input_beats[i].size() > maximum_buffered) begin
                maximum_buffered = input_beats[i].size();
            end
        end
        if (aw_parallel > 1) begin
            parallel_aw++;
        end
        for (int i = 0; i < INPUTS; i++) begin
            if (s_awvalid[i] && s_awready[i]) begin
                item.source = i;
                item.dest = decode_reference(s_awaddr[i]);
                item.id = s_awid[i];
                item.addr = s_awaddr[i];
                item.len = s_awlen[i];
                item.attr = s_awattr[i];
                addresses[i].push_back(item);
                routes[i].push_back(item);
                input_count[i]++;
                if (id_count[i][item.id] != 0) begin
                    repeated_id++;
                end
                id_count[i][item.id]++;
                id_target[i][item.id] = item.dest;
                accepted++;
            end
        end
        // Drive at the falling edge next time; clear accepted offers after sampling.
        #1;
        // s_awready can change after the edge, so use queue sequence witnesses instead.
        cycles++;
    endtask

    // Track source handshakes before NBA; remove each accepted offer at the next negedge.
    logic [INPUTS-1:0] accepted_mask = '0;
    logic [INPUTS-1:0] accepted_w_mask = '0;
    always @(posedge clk) begin
        accepted_mask <= reset_n ? s_awvalid & s_awready : '0;
        accepted_w_mask <= reset_n ? s_wvalid & s_wready : '0;
    end
    task run_tick(int phase, bit generate_traffic);
        // Clear old offers between clock edges, before tick generates replacements.
        s_awvalid = s_awvalid & ~accepted_mask;
        s_wvalid = s_wvalid & ~accepted_w_mask;
        tick(phase, generate_traffic);
    endtask

    function bit empty();
        bit result;
        result = s_awvalid == 0 && s_wvalid == 0;
        for (int i = 0; i < INPUTS; i++) begin
            result &= input_count[i] == 0 && addresses[i].size() == 0 && routes[i].size() == 0 && input_beats[i].size() == 0 && planned_w[i].size() == 0;
        end
        return result;
    endfunction

    initial begin
        int ignored;
        int drain_cycles;
        void'($value$plusargs("SEED=%d", seed));
        ignored = $urandom(seed);
        bad_early = $test$plusargs("BAD_EARLY_LAST");
        bad_missing = $test$plusargs("BAD_MISSING_LAST");
        for (int o = 0; o < SLAVES; o++) begin
            map_base[o] = ADDR_WIDTH'(o) << 16;
            if (ADDR_WIDTH > 32) begin
                map_base[o] |= ADDR_WIDTH'(1) << (ADDR_WIDTH - 2);
            end
            map_limit[o] = map_base[o] + ADDR_WIDTH'('hffff);
        end
        reset_control();
        // Cancel accepted, stalled work, then exercise fresh traffic.
        for (int c = 0; c < 35; c++) begin
            run_tick(c, 1);
        end
        reset_control();
        for (int c = 0; c < 2500; c++) begin
            run_tick(c, 1);
        end
        drain_cycles = 0;
        while (!empty() && drain_cycles < 12000) begin
            run_tick(3000 + drain_cycles, 0);
            drain_cycles++;
        end
        if (!empty() || accepted != completed + cancelled || blocked == 0 ||
            error_target == 0 || peak_output != ((INPUTS * INPUT_LIMIT < OUTPUT_LIMIT) ? INPUTS * INPUT_LIMIT : OUTPUT_LIMIT) ||
            (INPUTS > 1 && parallel_aw == 0) ||
            (INPUT_LIMIT > 1 && (id_blocked == 0 || repeated_id == 0))) begin
            $fatal(1, "FINAL_WITNESS accepted=%0d completed=%0d cancelled=%0d blocked=%0d peak=%0d parallel=%0d error=%0d",
                   accepted, completed, cancelled, blocked, peak_output, parallel_aw, error_target);
        end
        if (input_w_count != output_w_count + cancelled_beats || maximum_buffered != 2 ||
            early_w_stalls == 0 || full_buffer_stalls == 0 || output_w_stalls == 0 ||
            zero_strobes == 0 || sparse_strobes == 0 || (INPUTS > 1 && parallel_w == 0)) begin
            $fatal(1, "W_FINAL_WITNESS");
        end
        if (bad_early || bad_missing) begin
            $fatal(1, "MISSING_EXPECTED_ASSERTION");
        end
        $display("WDATA_WITNESS in=%0d out=%0d cancelled=%0d max_buffer=%0d early=%0d full=%0d stalled=%0d parallel=%0d zero_strb=%0d sparse_strb=%0d",
                 input_w_count, output_w_count, cancelled_beats, maximum_buffered,
                 early_w_stalls, full_buffer_stalls, output_w_stalls, parallel_w, zero_strobes, sparse_strobes);
        $display("WPATH_PASS accepted=%0d forwarded=%0d completed=%0d cancelled=%0d blocked=%0d peak=%0d parallel_aw=%0d error_target=%0d cycles=%0d id_blocked=%0d repeated_id=%0d",
                 accepted, forwarded, completed, cancelled, blocked, peak_output, parallel_aw, error_target, cycles, id_blocked, repeated_id);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "WPATH_WATCHDOG");
    end
endmodule
