`timescale 1ns/1ps
module tracker_tb;
    parameter int ID_WIDTH = 2;
    parameter int TARGETS = 5;
    parameter int CAPACITY = 2;
    localparam int TW = TARGETS > 1 ? $clog2(TARGETS) : 1;
    localparam int CW = $clog2(CAPACITY + 1);
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic request_valid = 0;
    logic request_ready;
    logic [ID_WIDTH-1:0] request_id = 0;
    logic [TW-1:0] request_target = 0;
    logic complete_valid = 0;
    logic [ID_WIDTH-1:0] complete_id = 0;
    logic complete_known;
    logic [TW-1:0] complete_target;
    logic [CW-1:0] outstanding;
    // Independent per-ID reference; RTL uses a bounded associative slot table.
    int reference_count [1 << ID_WIDTH];
    int reference_target [1 << ID_WIDTH];
    int total = 0;
    int checks = 0;
    int accepted = 0;
    int retired = 0;
    int simultaneous = 0;
    int full_block = 0;
    int target_block = 0;
    int seed = 7;
    bit expected_ready;
    bit take_request;

    axi_write_tracker #(
        .ID_WIDTH(ID_WIDTH),
        .TARGETS(TARGETS),
        .MAX_OUTSTANDING(CAPACITY)
    ) dut (.*);

    task step(bit valid_i, int id_i, int target_i, bit done_i, int done_id_i);
        @(negedge clk);
        request_valid = valid_i;
        request_id = ID_WIDTH'(id_i);
        request_target = TW'(target_i);
        complete_valid = done_i;
        complete_id = ID_WIDTH'(done_id_i);
        #1;
        expected_ready = total < CAPACITY && target_i < TARGETS &&
                         (reference_count[id_i] == 0 || reference_target[id_i] == target_i);
        if (request_ready !== expected_ready) begin
            $fatal(1, "READY expected=%b actual=%b total=%0d id=%0d target=%0d",
                   expected_ready, request_ready, total, id_i, target_i);
        end
        if (complete_known !== (reference_count[done_id_i] != 0)) begin
            $fatal(1, "COMPLETE_LOOKUP");
        end
        if (reference_count[done_id_i] != 0 &&
            int'(complete_target) != reference_target[done_id_i]) begin
            $fatal(1, "COMPLETE_TARGET");
        end
        if (done_i && reference_count[done_id_i] == 0) begin
            $fatal(1, "TB_ILLEGAL_COMPLETION");
        end
        take_request = valid_i && expected_ready;
        if (valid_i && total == CAPACITY) begin
            full_block++;
        end
        if (valid_i && reference_count[id_i] != 0 && reference_target[id_i] != target_i) begin
            target_block++;
        end
        @(posedge clk);
        if (done_i) begin
            reference_count[done_id_i]--;
            total--;
            retired++;
        end
        if (take_request) begin
            reference_count[id_i]++;
            reference_target[id_i] = target_i;
            total++;
            accepted++;
        end
        if (done_i && take_request) begin
            simultaneous++;
        end
        #1;
        if (int'(outstanding) != total) begin
            $fatal(1, "COUNT expected=%0d actual=%0d", total, outstanding);
        end
        checks++;
    endtask

    task reset_tracker();
        @(negedge clk);
        reset_n = 0;
        request_valid = 0;
        complete_valid = 0;
        #1;
        if (outstanding != 0 || request_ready || complete_known) begin
            $fatal(1, "RESET_CONTROL");
        end
        foreach (reference_count[i]) begin
            reference_count[i] = 0;
            reference_target[i] = 0;
        end
        total = 0;
        @(negedge clk);
        reset_n = 1;
    endtask

    initial begin
        int done_id;
        int random_id;
        int random_target;
        bit done;
        bit valid;
        int ignored;
        void'($value$plusargs("SEED=%d", seed));
        ignored = $urandom(seed);
        foreach (reference_count[i]) begin
            reference_count[i] = 0;
            reference_target[i] = 0;
        end
        reset_tracker();
        if ($test$plusargs("BAD_COMPLETION")) begin
            @(negedge clk);
            complete_valid = 1;
            @(posedge clk);
            #1;
            $fatal(1, "MISSING_EXPECTED_ASSERTION");
        end
        if (TARGETS < (1 << TW)) begin
            step(1, 0, TARGETS, 0, 0);
        end
        // Same ID is counted twice when capacity permits; cross-target waits.
        step(1, 0, 0, 0, 0);
        step(1, 0, TARGETS-1, 0, 0);
        if (CAPACITY > 1) begin
            step(1, 0, 0, 0, 0);
        end
        while (total < CAPACITY) begin
            step(1, 0, 0, 0, 0);
        end
        // No same-edge reuse when full, even as the old response retires.
        step(1, 0, 0, 1, 0);
        if (CAPACITY > 1) begin
            // Same-ID increment and decrement on one edge must cancel.
            step(1, 0, 0, 1, 0);
        end
        while (total != 0) begin
            step(0, 0, 0, 1, 0);
        end
        step(1, 0, TARGETS-1, 0, 0);
        step(0, 0, 0, 1, 0);
        if (CAPACITY > 1) begin
            step(1, 0, 0, 0, 0);
            step(1, 1, TARGETS-1, 1, 0);
            step(0, 0, 0, 1, 1);
        end
        // Deterministic random traffic, with legal completions chosen independently.
        repeat (2000) begin
            random_id = int'($urandom_range((1 << ID_WIDTH)-1, 0));
            random_target = int'($urandom_range(TARGETS-1, 0));
            done_id = int'($urandom_range((1 << ID_WIDTH)-1, 0));
            done = reference_count[done_id] != 0 && $urandom_range(1, 0) != 0;
            valid = $urandom_range(3, 0) != 0;
            step(valid, random_id, random_target, done, done_id);
        end
        // Reset with live records and prove a formerly bound ID can move.
        reset_tracker();
        step(1, 0, TARGETS-1, 0, 0);
        reset_tracker();
        step(1, 0, 0, 0, 0);
        step(0, 0, 0, 1, 0);
        if (full_block == 0 || (TARGETS > 1 && target_block == 0) ||
            (CAPACITY > 1 && simultaneous == 0)) begin
            $fatal(1, "MISSING_SCENARIO");
        end
        $display("TRACKER_PASS checks=%0d accepted=%0d retired=%0d simultaneous=%0d full_block=%0d target_block=%0d",
                 checks, accepted, retired, simultaneous, full_block, target_block);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "TRACKER_WATCHDOG");
    end
endmodule
