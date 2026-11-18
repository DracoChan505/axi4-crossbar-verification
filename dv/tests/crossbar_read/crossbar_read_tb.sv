`timescale 1ns/1ps
module crossbar_read_tb;
    parameter int INPUTS       = 4;
    parameter int SLAVES       = 4;
    parameter int ADDR_WIDTH   = 32;
    parameter int DATA_WIDTH   = 32;
    parameter int INPUT_LIMIT  = 2;
    parameter int OUTPUT_LIMIT = 4;
    localparam int ID_WIDTH        = 2;
    localparam int SOURCE_WIDTH    = INPUTS > 1 ? $clog2(INPUTS) : 1;
    localparam int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH;
    localparam int STRB_WIDTH      = DATA_WIDTH / 8;

    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;

    logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_base;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0] map_limit;

    logic [INPUTS-1:0]                   s_arvalid = '0;
    logic [INPUTS-1:0]                   s_arready;
    logic [INPUTS-1:0][ID_WIDTH-1:0]     s_arid    = '0;
    logic [INPUTS-1:0][ADDR_WIDTH-1:0]   s_araddr  = '0;
    logic [INPUTS-1:0][7:0]              s_arlen   = '0;
    logic [INPUTS-1:0][2:0]              s_arsize  = '0;
    logic [INPUTS-1:0][1:0]              s_arburst = '0;
    logic [INPUTS-1:0]                   s_arlock  = '0;
    logic [INPUTS-1:0][3:0]              s_arcache = '0;
    logic [INPUTS-1:0][2:0]              s_arprot  = '0;
    logic [INPUTS-1:0][3:0]              s_arqos   = '0;
    logic [INPUTS-1:0]                   s_rvalid;
    logic [INPUTS-1:0]                   s_rready  = '0;
    logic [INPUTS-1:0][ID_WIDTH-1:0]     s_rid;
    logic [INPUTS-1:0][DATA_WIDTH-1:0]   s_rdata;
    logic [INPUTS-1:0][1:0]              s_rresp;
    logic [INPUTS-1:0]                   s_rlast;
    logic [SLAVES-1:0]                   m_arvalid;
    logic [SLAVES-1:0]                   m_arready = '0;
    logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_arid;
    logic [SLAVES-1:0][ADDR_WIDTH-1:0]   m_araddr;
    logic [SLAVES-1:0][7:0]              m_arlen;
    logic [SLAVES-1:0][2:0]              m_arsize;
    logic [SLAVES-1:0][1:0]              m_arburst;
    logic [SLAVES-1:0]                   m_arlock;
    logic [SLAVES-1:0][3:0]              m_arcache;
    logic [SLAVES-1:0][2:0]              m_arprot;
    logic [SLAVES-1:0][3:0]              m_arqos;
    logic [SLAVES-1:0]                   m_rvalid  = '0;
    logic [SLAVES-1:0]                   m_rready;
    logic [SLAVES-1:0][OUTPUT_ID_WIDTH-1:0] m_rid  = '0;
    logic [SLAVES-1:0][DATA_WIDTH-1:0]   m_rdata   = '0;
    logic [SLAVES-1:0][1:0]              m_rresp   = '0;
    logic [SLAVES-1:0]                   m_rlast   = '0;

    axi_crossbar_read #(
        .INPUTS(INPUTS), .SLAVES(SLAVES), .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INPUT_LIMIT(INPUT_LIMIT), .OUTPUT_LIMIT(OUTPUT_LIMIT)
    ) dut (.*);

    initial begin
        for (int s = 0; s < SLAVES; s++) begin
            map_base[s]  = ADDR_WIDTH'(s) << 16;
            map_limit[s] = (ADDR_WIDTH'(s) << 16) | ADDR_WIDTH'(32'hffff);
        end
    end

    localparam int TX_PER_MASTER = 24;
    localparam int TX_TOTAL      = INPUTS * TX_PER_MASTER;

    typedef struct {
        int        dest;
        logic [ID_WIDTH-1:0]   id;
        logic [ADDR_WIDTH-1:0] addr;
        int        beats;
        logic [2:0] size;
    } ar_ref_t;

    // ----- Reference table (built at time 0) -----
    ar_ref_t ar_ref [INPUTS][TX_PER_MASTER];

    // Per-master: sequential tracking of accepted and completed transactions.
    // accepted_head[i] = how many ARs have been accepted for master i (index into ar_ref)
    // complete_head[i] = how many R transactions have completed for master i
    // in_flight[i][slot] = ar_ref index of the slot-th in-flight transaction (FIFO)
    // in_flight_beats[i][slot] = beats received so far for that in-flight transaction
    int   accepted_head [INPUTS];   // next ar_ref index to accept
    int   complete_head [INPUTS];   // next ar_ref index to complete
    int   in_flight_ref  [INPUTS][$];  // ar_ref indices in flight (oldest first)
    int   in_flight_beat [INPUTS][$];  // beat counters per in-flight txn

    int   total_ar_issued  = 0;
    int   total_r_complete = 0;
    int   total_decerr     = 0;
    int   expected_decerr  = 0;
    int   seed             = 7;
    bit   bad_source_inject = 0;

    // per-master driver state
    int   ar_seq    [INPUTS];   // next ar_ref index to issue
    int   ar_stall  [INPUTS];   // negedge stalls before next issue
    bit   ar_cooldown [INPUTS]; // one-negedge gap after accept

    logic [INPUTS-1:0] accepted_mask;  // posedge-latched handshake mask

    int rng [INPUTS];

    initial begin
        void'($value$plusargs("SEED=%d", seed));
        bad_source_inject = $test$plusargs("BAD_SOURCE");
        for (int i = 0; i < INPUTS; i++) begin
            automatic int r = seed * (i + 1) * 7919;
            for (int n = 0; n < TX_PER_MASTER; n++) begin
                automatic int dest = n % (SLAVES + 1);
                r = r * 1664525 + 1013904223;
                ar_ref[i][n].dest  = dest;
                ar_ref[i][n].id    = ID_WIDTH'(n % (1 << ID_WIDTH));
                ar_ref[i][n].beats = 1 + (n % 4);
                ar_ref[i][n].size  = $clog2(STRB_WIDTH) > 0 ?
                                     3'(n % ($clog2(STRB_WIDTH) + 1)) : 3'h0;
                if (dest == SLAVES) begin
                    ar_ref[i][n].addr = ADDR_WIDTH'(64'h0010_0000 + i * 256 + n * 4);
                    expected_decerr++;
                end else begin
                    ar_ref[i][n].addr = ADDR_WIDTH'(dest << 16) + ADDR_WIDTH'(i * 4096 + n * 64);
                end
            end
            ar_seq[i] = 0; ar_stall[i] = 0; ar_cooldown[i] = 0;
            accepted_head[i] = 0; complete_head[i] = 0;
            rng[i] = seed * (i + 7) * 3571;
        end
        @(negedge clk); reset_n = 0;
        @(negedge clk); reset_n = 1;
    end

    // Latch accepted handshakes at posedge
    always @(posedge clk)
        accepted_mask <= reset_n ? (s_arvalid & s_arready) : '0;

    // AR acceptance monitor: add to in-flight queue in order
    always @(posedge clk) begin
        if (reset_n) begin
            for (int i = 0; i < INPUTS; i++) begin
                if (s_arvalid[i] && s_arready[i]) begin
                    in_flight_ref[i].push_back(accepted_head[i]);
                    in_flight_beat[i].push_back(0);
                    accepted_head[i]++;
                    total_ar_issued++;
                end
            end
        end
    end

    // Negedge: drive AR + R-ready
    always @(negedge clk) begin
        if (!reset_n) begin
            s_arvalid = '0; s_rready = '0;
            for (int i = 0; i < INPUTS; i++) begin
                s_arid[i]='0; s_araddr[i]='0; s_arlen[i]='0; s_arsize[i]='0;
                ar_cooldown[i] = 0;
            end
        end else begin
            // Clear accepted valids
            for (int i = 0; i < INPUTS; i++) begin
                if (accepted_mask[i]) begin
                    s_arvalid[i] = 0; s_arid[i]='0; s_araddr[i]='0;
                    s_arlen[i]='0; s_arsize[i]='0;
                    ar_cooldown[i] = 1;  // block next issue this negedge
                end
            end
            // Issue new AR
            for (int i = 0; i < INPUTS; i++) begin
                if (!s_arvalid[i] && ar_seq[i] < TX_PER_MASTER && !ar_cooldown[i]) begin
                    if (ar_stall[i] > 0) begin
                        ar_stall[i]--;
                    end else begin
                        s_arvalid[i] = 1;
                        s_arid[i]    = ar_ref[i][ar_seq[i]].id;
                        s_araddr[i]  = ar_ref[i][ar_seq[i]].addr;
                        s_arlen[i]   = 8'(ar_ref[i][ar_seq[i]].beats - 1);
                        s_arsize[i]  = ar_ref[i][ar_seq[i]].size;
                        s_arburst[i] = 2'b01;
                        rng[i] = rng[i] * 1664525 + 1013904223;
                        ar_stall[i] = (rng[i] >> 8) % 3;
                        ar_seq[i]++;
                    end
                end
                ar_cooldown[i] = 0;
                // R-ready backpressure
                rng[i] = rng[i] * 1664525 + 1013904223;
                s_rready[i] = ((rng[i] >> 10) % 4) != 0;
            end
        end
    end

    // Scoreboard: check R at master side (posedge, ordered by in-flight queue)
    always @(posedge clk) begin
        if (reset_n) begin
            for (int i = 0; i < INPUTS; i++) begin
                if (s_rvalid[i] && s_rready[i]) begin
                    automatic int ref_idx;
                    automatic ar_ref_t ref_txn;
                    automatic int beat;
                    // Find the in-flight entry matching this RID (oldest first)
                    // DUT guarantees same-ID ordering; different IDs may interleave.
                    // We find the oldest in-flight entry whose ID matches s_rid.
                    begin
                        automatic int slot = -1;
                        for (int k = 0; k < in_flight_ref[i].size(); k++) begin
                            if (slot < 0 &&
                                ar_ref[i][in_flight_ref[i][k]].id == s_rid[i]) begin
                                slot = k;
                            end
                        end
                        if (slot < 0)
                            $fatal(1, "SCBD_ORPHAN: master=%0d rid=%0d in_flight=%0d",
                                   i, int'(s_rid[i]), in_flight_ref[i].size());
                        ref_idx = in_flight_ref[i][slot];
                        ref_txn = ar_ref[i][ref_idx];
                        // Check response
                        if (ref_txn.dest == SLAVES) begin
                            if (s_rresp[i] != 2'b11)
                                $fatal(1, "SCBD_DECERR: master=%0d resp=%0b", i, s_rresp[i]);
                        end else begin
                            if (s_rresp[i] != 2'b00)
                                $fatal(1, "SCBD_RESP: master=%0d resp=%0b", i, s_rresp[i]);
                        end
                        // Count beat
                        beat = in_flight_beat[i][slot] + 1;
                        in_flight_beat[i][slot] = beat;
                        // Check RLAST
                        if (s_rlast[i] != (beat == ref_txn.beats))
                            $fatal(1, "SCBD_RLAST: master=%0d rid=%0d slot=%0d beat=%0d beats=%0d rlast=%b",
                                   i, int'(s_rid[i]), slot, beat, ref_txn.beats, s_rlast[i]);
                        // On RLAST, remove from in-flight
                        if (s_rlast[i]) begin
                            in_flight_ref[i].delete(slot);
                            in_flight_beat[i].delete(slot);
                            total_r_complete++;
                            if (ref_txn.dest == SLAVES) total_decerr++;
                        end
                    end
                end
            end
        end
    end

    // Slave AR receivers + R response generators (negedge)
    for (genvar o = 0; o < SLAVES; o++) begin : slave_port
        typedef struct {
            logic [OUTPUT_ID_WIDTH-1:0] xid;
            int source;
            int beats;
            int seq;
        } slave_txn_t;
        slave_txn_t s_queue [$];
        int sv_rng;
        int sv_beat;
        int sv_delay;
        initial begin sv_rng = seed*(o+5)*3571; sv_beat=0; sv_delay=0; end

        always @(negedge clk) begin
            if (!reset_n) begin
                m_arready[o]=0; m_rvalid[o]=0; m_rid[o]='0;
                m_rdata[o]='0; m_rresp[o]='0; m_rlast[o]=0;
                sv_beat=0; sv_delay=0;
                s_queue = {};
            end else begin
                // AR
                sv_rng = sv_rng*1664525+1013904223;
                m_arready[o] = ((sv_rng>>12)%3) != 0;
                if (m_arvalid[o] && m_arready[o]) begin
                    automatic slave_txn_t t;
                    t.xid    = m_arid[o];
                    t.source = int'(m_arid[o][OUTPUT_ID_WIDTH-1:ID_WIDTH]);
                    t.beats  = int'(m_arlen[o]) + 1;
                    t.seq    = total_ar_issued;
                    s_queue.push_back(t);
                end
                // R
                if (s_queue.size() > 0) begin
                    if (m_rvalid[o] && m_rready[o]) begin
                        if (m_rlast[o]) begin
                            void'(s_queue.pop_front());
                            sv_beat = 0;
                            m_rvalid[o] = 0; m_rid[o]='0;
                            m_rdata[o]='0; m_rresp[o]='0; m_rlast[o]=0;
                            sv_rng = sv_rng*1664525+1013904223;
                            sv_delay = (sv_rng>>14)%4;
                        end else begin
                            sv_beat++;
                            sv_rng = sv_rng*1664525+1013904223;
                            if ((sv_rng>>15)%3 == 0) begin
                                m_rvalid[o]=0; m_rid[o]='0;
                                m_rdata[o]='0; m_rresp[o]='0; m_rlast[o]=0;
                            end else begin
                                m_rvalid[o] = 1;
                                m_rid[o]    = s_queue[0].xid;
                                m_rdata[o]  = DATA_WIDTH'(s_queue[0].source*65536 +
                                                           s_queue[0].seq*256 + sv_beat);
                                m_rresp[o]  = 2'b00;
                                m_rlast[o]  = (sv_beat == s_queue[0].beats-1);
                            end
                        end
                    end else if (!m_rvalid[o]) begin
                        if (sv_delay > 0) begin
                            sv_delay--;
                        end else begin
                            m_rvalid[o] = 1;
                            m_rid[o]    = s_queue[0].xid;
                            m_rdata[o]  = DATA_WIDTH'(s_queue[0].source*65536 +
                                                       s_queue[0].seq*256 + sv_beat);
                            m_rresp[o]  = 2'b00;
                            m_rlast[o]  = (sv_beat == s_queue[0].beats-1);
                        end
                    end
                end else begin
                    m_rvalid[o]=0; m_rid[o]='0;
                    m_rdata[o]='0; m_rresp[o]='0; m_rlast[o]=0;
                end
            end
        end
    end

    // Inject bad source
    initial begin
        if (bad_source_inject) begin
            repeat(100) @(negedge clk);
            @(negedge clk);
            m_rvalid[0]=1;
            m_rid[0] = {SOURCE_WIDTH'(INPUTS), ID_WIDTH'(0)};
            m_rdata[0]='0; m_rresp[0]=2'b11; m_rlast[0]=1;
            @(negedge clk);
            m_rvalid[0]=0; m_rid[0]='0;
        end
    end

    // Timeout / pass
    initial begin
        automatic int waited;
        @(posedge reset_n);
        for (waited = 0; waited < 500000; waited++) begin
            @(posedge clk);
            if (total_r_complete == TX_TOTAL) break;
        end
        if (total_r_complete != TX_TOTAL)
            $fatal(1, "CROSSBAR_READ_INCOMPLETE: completed=%0d expected=%0d",
                   total_r_complete, TX_TOTAL);
        for (int i = 0; i < INPUTS; i++) begin
            if (in_flight_ref[i].size() != 0)
                $fatal(1, "CROSSBAR_READ_PENDING: master=%0d remaining=%0d",
                       i, in_flight_ref[i].size());
        end
        $display("CROSSBAR_READ_PASS completed=%0d decerr=%0d expected_decerr=%0d ar_issued=%0d",
                 total_r_complete, total_decerr, expected_decerr, total_ar_issued);
        $finish;
    end

endmodule
