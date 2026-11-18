`timescale 1ns/1ps
module decerr_tb;
    parameter int CAPACITY = 4;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic awvalid = 0;
    logic awready;
    logic [3:0] awid = 0;
    logic [7:0] awlen = 0;
    logic wvalid = 0;
    logic wready;
    logic wlast = 0;
    logic bvalid;
    logic bready = 0;
    logic [3:0] bid;
    logic [1:0] bresp;
    int responses = 0;
    int completed_w = 0;
    bit negative_case;
    axi_write_decerr #(.CAPACITY(CAPACITY)) dut (.*);

    task reset_endpoint();
        @(negedge clk);
        reset_n = 0;
        awvalid = 0;
        wvalid = 0;
        bready = 0;
        #1;
        if (awready || wready || bvalid) begin
            $fatal(1, "ERROR_RESET");
        end
        @(negedge clk);
        reset_n = 1;
    endtask
    task send_aw(int id, int len);
        @(negedge clk);
        awvalid = 1;
        awid = 4'(id);
        awlen = 8'(len);
        do begin
            @(posedge clk);
        end while (!awready);
        #1;
        awvalid = 0;
    endtask
    task send_w(int beat, int len);
        @(negedge clk);
        wvalid = 1;
        wlast = negative_case ? 0 : beat == len;
        do begin
            @(posedge clk);
        end while (!wready);
        if (completed_w == 0 && bvalid) begin
            $fatal(1, "EARLY_ERROR_B");
        end
        if (beat == len) begin
            completed_w++;
        end
        #1;
        wvalid = 0;
    endtask
    initial begin
        negative_case = $test$plusargs("BAD_LAST");
        reset_endpoint();
        @(negedge clk);
        wvalid = 1;
        repeat (3) begin
            @(posedge clk);
            if (wready || bvalid) begin
                $fatal(1, "ERROR_W_WITHOUT_AW");
            end
        end
        #1;
        wvalid = 0;
        if (negative_case) begin
            send_aw(0, 0);
            send_w(0, 0);
            $fatal(1, "MISSING_EXPECTED_ASSERTION");
        end
        for (int i = 0; i < CAPACITY; i++) begin
            send_aw(i, i == 0 ? 255 : i);
        end
        if (awready) begin
            $fatal(1, "ERROR_CAPACITY");
        end
        for (int i = 0; i < CAPACITY; i++) begin
            for (int beat = 0; beat <= (i == 0 ? 255 : i); beat++) begin
                send_w(beat, i == 0 ? 255 : i);
            end
        end
        repeat (8) begin
            @(posedge clk);
            if (!bvalid || bid != 0 || bresp != 2'b11 || awready) begin
                $fatal(1, "ERROR_B_HOLD");
            end
        end
        @(negedge clk);
        bready = 1;
        while (responses < CAPACITY) begin
            @(posedge clk);
            if (bvalid) begin
                if (bid != 4'(responses) || bresp != 2'b11) begin
                    $fatal(1, "ERROR_B_ORDER");
                end
                responses++;
            end
            #1;
        end
        @(negedge clk);
        bready = 0;
        send_aw(7, 0);
        send_w(0, 0);
        reset_endpoint();
        repeat (3) begin
            @(posedge clk);
            if (bvalid || wready) begin
                $fatal(1, "ERROR_STALE_RESPONSE");
            end
        end
        $display("DECERR_PASS capacity=%0d responses=%0d", CAPACITY, responses);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "DECERR_WATCHDOG");
    end
endmodule
