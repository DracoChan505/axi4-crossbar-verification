`timescale 1ns/1ps
module frontend_tb;
    parameter int INPUTS = 4;
    parameter int SLAVES = 4;
    parameter int ADDR_WIDTH = 32;
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
    logic [INPUTS-1:0] w_target_ready = '0;
    logic [INPUTS-1:0][TARGET_WIDTH-1:0] w_target;
    logic [INPUTS-1:0][7:0] w_target_len;
    logic [OUTPUTS-1:0] w_source_valid;
    logic [OUTPUTS-1:0] w_source_ready = '0;
    logic [OUTPUTS-1:0][SOURCE_WIDTH-1:0] w_source;
    logic [OUTPUTS-1:0][7:0] w_source_len;
    typedef struct packed {
        int source;
        int dest;
        logic [ID_WIDTH-1:0] id;
        logic [ADDR_WIDTH-1:0] addr;
        logic [7:0] len;
        logic [16:0] attr;
    } transaction_t;
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
    bit progress_w [OUTPUTS];

    axi_write_frontend #(
        .INPUTS(INPUTS), .SLAVES(SLAVES), .ADDR_WIDTH(ADDR_WIDTH),
        .INPUT_LIMIT(INPUT_LIMIT), .OUTPUT_LIMIT(OUTPUT_LIMIT)
    ) dut (.*);

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
        w_source_ready = '0;
        w_target_ready = '0;
        m_awready = '0;
        for (int i = 0; i < INPUTS; i++) begin
            cancelled += input_count[i];
            input_count[i] = 0;
            addresses[i].delete();
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
        if (s_awready != 0 || m_awvalid != 0 || w_target_valid != 0 || w_source_valid != 0) begin
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
                s_awattr[i] = {3'd2, 2'b01, 1'b0, 4'd2, 3'd2, 4'(n)};
                sequence_number[i]++;
            end
        end
        w_target_ready = '0;
        w_source_ready = '0;
        release_valid = '0;
        complete_valid = '0;
        for (int o = 0; o < OUTPUTS; o++) begin
            m_awready[o] = phase >= 20 && $urandom_range(3, 0) != 0;
            progress_w[o] = 0;
            if (w_source_valid[o]) begin
                src = int'(w_source[o]);
                if (src >= INPUTS) begin
                    $fatal(1, "SOURCE_RANGE");
                end
                if (sources[o].size() == 0 || sources[o][0].source != src ||
                    sources[o][0].len != w_source_len[o]) begin
                    $fatal(1, "SOURCE_QUEUE");
                end
                if (w_target_valid[src] && int'(w_target[src]) == o &&
                    phase >= 80 && $urandom_range(3, 0) != 0) begin
                    progress_w[o] = 1;
                    if (w_progress[o] == int'(w_source_len[o])) begin
                        w_source_ready[o] = 1;
                        w_target_ready[src] = 1;
                    end
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
            if (progress_w[o]) begin
                w_progress[o]++;
            end
            if (w_source_valid[o] && w_source_ready[o]) begin
                item = sources[o].pop_front();
                removed = routes[item.source].pop_front();
                if (item != removed || !w_target_ready[item.source] ||
                    w_progress[o] != int'(item.len) + 1) begin
                    $fatal(1, "W_PAIRING");
                end
                w_progress[o] = 0;
                responses[o].push_back(item);
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
    always @(posedge clk) begin
        accepted_mask <= reset_n ? s_awvalid & s_awready : '0;
    end
    task run_tick(int phase, bit generate_traffic);
        // Clear old offers between clock edges, before tick generates replacements.
        s_awvalid = s_awvalid & ~accepted_mask;
        tick(phase, generate_traffic);
    endtask

    function bit empty();
        bit result;
        result = s_awvalid == 0;
        for (int i = 0; i < INPUTS; i++) begin
            result &= input_count[i] == 0 && addresses[i].size() == 0 && routes[i].size() == 0;
        end
        return result;
    endfunction

    initial begin
        int ignored;
        int drain_cycles;
        void'($value$plusargs("SEED=%d", seed));
        ignored = $urandom(seed);
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
        $display("FRONTEND_PASS accepted=%0d forwarded=%0d completed=%0d cancelled=%0d blocked=%0d peak=%0d parallel_aw=%0d error_target=%0d cycles=%0d id_blocked=%0d repeated_id=%0d",
                 accepted, forwarded, completed, cancelled, blocked, peak_output, parallel_aw, error_target, cycles, id_blocked, repeated_id);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "FRONTEND_WATCHDOG");
    end
endmodule
