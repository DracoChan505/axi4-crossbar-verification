`timescale 1ns/1ps
module routing_tb;
    parameter int PORTS = 4;
    parameter int ADDR_WIDTH = 32;
    localparam int IW = PORTS > 1 ? $clog2(PORTS) : 1;
    localparam int TW = $clog2(PORTS + 1);
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [PORTS-1:0] request = '0;
    logic grant_ready = 0;
    logic grant_valid;
    logic [IW-1:0] grant_index;
    logic [PORTS-1:0] grant_onehot;
    logic [PORTS-1:0] request_ready;
    logic [ADDR_WIDTH-1:0] address = '0;
    logic [PORTS-1:0][ADDR_WIDTH-1:0] map_base;
    logic [PORTS-1:0][ADDR_WIDTH-1:0] map_limit;
    logic map_valid;
    logic decode_error;
    logic [TW-1:0] target;
    int priority_order[$];
    int held = -1;
    int checks = 0;
    int transfers = 0;
    int stalls = 0;
    int decode_checks = 0;
    int seed = 7;

    axi_rr_arbiter #(.PORTS(PORTS)) arbiter (.*);
    axi_address_decode #(.ADDR_WIDTH(ADDR_WIDTH), .TARGETS(PORTS)) decoder (.*);

    task reset_arbiter();
        @(negedge clk);
        reset_n = 0;
        request = '0;
        grant_ready = 0;
        #1;
        if (grant_valid || grant_onehot != 0 || request_ready != 0) begin
            $fatal(1, "RESET_GRANT");
        end
        priority_order.delete();
        for (int i = 0; i < PORTS; i++) begin
            priority_order.push_back(i);
        end
        held = -1;
        @(negedge clk);
        reset_n = 1;
    endtask

    task arbitrate(logic [PORTS-1:0] requests, bit ready_i);
        int winner;
        int moved;
        logic [PORTS-1:0] expected_onehot;
        @(negedge clk);
        request = requests;
        grant_ready = ready_i;
        winner = held;
        if (winner < 0) begin
            foreach (priority_order[i]) begin
                if (winner < 0 && requests[priority_order[i]]) begin
                    winner = priority_order[i];
                end
            end
        end
        else if (!requests[winner]) begin
            $fatal(1, "TB_WITHDREW_REQUEST");
        end
        expected_onehot = '0;
        if (winner >= 0) begin
            expected_onehot[winner] = 1;
        end
        #1;
        if (grant_valid !== (winner >= 0) || grant_onehot !== expected_onehot ||
            request_ready !== (ready_i ? expected_onehot : '0)) begin
            $fatal(1, "ARBITRATION_OUTPUT");
        end
        if (winner >= 0 && int'(grant_index) != winner) begin
            $fatal(1, "ARBITRATION_INDEX");
        end
        @(posedge clk);
        if (winner >= 0 && ready_i) begin
            // Rotate an independent priority list past the actual winner.
            do begin
                moved = priority_order.pop_front();
                priority_order.push_back(moved);
            end while (moved != winner);
            held = -1;
            transfers++;
        end
        else if (winner >= 0) begin
            held = winner;
            stalls++;
        end
        checks++;
        #1;
    endtask

    task decode_at(logic [ADDR_WIDTH-1:0] addr_i, bit valid_map_i, int target_i);
        address = addr_i;
        #1;
        if (map_valid !== valid_map_i || int'(target) != target_i ||
            decode_error !== (target_i == PORTS)) begin
            $fatal(1, "DECODE address=%h map=%b target=%0d expected=%0d",
                   addr_i, map_valid, target, target_i);
        end
        decode_checks++;
    endtask

    initial begin
        int ignored;
        int expected_target;
        int chosen;
        logic [PORTS-1:0] requests;
        logic [ADDR_WIDTH-1:0] probe;
        void'($value$plusargs("SEED=%d", seed));
        ignored = $urandom(seed);
        // Default four-window shape, generalized to the parameter count.
        for (int i = 0; i < PORTS; i++) begin
            map_base[i] = ADDR_WIDTH'(i) << 16;
            map_limit[i] = map_base[i] + ADDR_WIDTH'('hffff);
        end
        for (int i = 0; i < PORTS; i++) begin
            decode_at(map_base[i], 1, i);
            decode_at(map_limit[i], 1, i);
        end
        decode_at(ADDR_WIDTH'(PORTS) << 16, 1, PORTS);
        decode_at('1, 1, PORTS);
        // Relocate every window, add gaps, and exercise high address bits at 64 bits.
        for (int i = 0; i < PORTS; i++) begin
            map_base[i] = (ADDR_WIDTH'(i + 1) << 17);
            if (ADDR_WIDTH > 32) begin
                map_base[i] = map_base[i] | (ADDR_WIDTH'(1) << (ADDR_WIDTH - 2));
            end
            map_limit[i] = map_base[i] + ADDR_WIDTH'('hffff);
        end
        for (int i = 0; i < PORTS; i++) begin
            decode_at(map_base[i] - 1'b1, 1, PORTS);
            decode_at(map_base[i], 1, i);
            decode_at(map_limit[i], 1, i);
            decode_at(map_limit[i] + 1'b1, 1, PORTS);
        end
        repeat (500) begin
            chosen = int'($urandom_range(PORTS - 1, 0));
            probe = map_base[chosen] + ADDR_WIDTH'($urandom_range('h1ffff, 0));
            expected_target = probe <= map_limit[chosen] ? chosen : PORTS;
            decode_at(probe, 1, expected_target);
        end
        map_base[0] = map_base[0] + 1'b1;
        decode_at(map_limit[0], 0, PORTS);
        map_base[0] = map_base[0] - 1'b1;
        map_limit[0] = map_limit[0] - 1'b1;
        decode_at(map_base[0], 0, PORTS);
        map_limit[0] = map_limit[0] + 1'b1;
        if (PORTS > 1) begin
            map_base[1] = map_base[0];
            decode_at(map_base[0], 0, PORTS);
        end
        map_base[0] = map_limit[0] + 1'b1;
        decode_at(map_limit[0], 0, PORTS);

        reset_arbiter();
        arbitrate('0, 1);
        // Continuous contention must complete in exact round-robin order.
        repeat (PORTS * 4) begin
            arbitrate('1, 1);
        end
        // Hold the last port, then add contenders while downstream is stalled.
        requests = '0;
        requests[PORTS-1] = 1;
        arbitrate(requests, 0);
        if ($test$plusargs("BAD_WITHDRAW")) begin
            @(negedge clk);
            request = '0;
            @(posedge clk);
            #1;
            $fatal(1, "MISSING_EXPECTED_ASSERTION");
        end
        repeat (7) begin
            arbitrate('1, 0);
        end
        arbitrate('1, 1);
        arbitrate('0, 1);
        arbitrate('1, 1);
        repeat (1000) begin
            requests = PORTS'($urandom());
            if (held >= 0) begin
                requests[held] = 1;
            end
            arbitrate(requests, $urandom_range(3, 0) != 0);
        end
        // Reset a locked grant, then restart priority at port zero.
        reset_arbiter();
        arbitrate('1, 0);
        reset_arbiter();
        arbitrate('1, 1);
        if (transfers == 0 || stalls < 8) begin
            $fatal(1, "MISSING_WITNESS");
        end
        $display("ROUTING_PASS arbitration_checks=%0d transfers=%0d stalls=%0d decode_checks=%0d",
                 checks, transfers, stalls, decode_checks);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "ROUTING_WATCHDOG");
    end
endmodule
