// R data routing from slaves back to masters. Per-output FIFO buffers incoming
// R beats; per-input locking keeps a burst's beats together until RLAST fires.
module axi_read_data_path #(
    parameter int INPUTS          = 4,
    parameter int OUTPUTS         = 5,
    parameter int DATA_WIDTH      = 32,
    parameter int ID_WIDTH        = 2,
    parameter int RESPONSE_DEPTH  = 2,
    parameter int SOURCE_WIDTH    = INPUTS > 1 ? $clog2(INPUTS) : 1,
    parameter int OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH,
    parameter int SELECT_WIDTH    = OUTPUTS > 1 ? $clog2(OUTPUTS) : 1,
    parameter int BEAT_WIDTH      = OUTPUT_ID_WIDTH + DATA_WIDTH + 3
) (
    input  logic clk,
    input  logic reset_n,
    // From slaves (downstream R)
    input  logic [OUTPUTS-1:0]                       m_rvalid,
    output logic [OUTPUTS-1:0]                       m_rready,
    input  logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0]  m_rid,
    input  logic [OUTPUTS-1:0][DATA_WIDTH-1:0]        m_rdata,
    input  logic [OUTPUTS-1:0][1:0]                  m_rresp,
    input  logic [OUTPUTS-1:0]                       m_rlast,
    // To masters (upstream R)
    output logic [INPUTS-1:0]                  s_rvalid,
    input  logic [INPUTS-1:0]                  s_rready,
    output logic [INPUTS-1:0][ID_WIDTH-1:0]    s_rid,
    output logic [INPUTS-1:0][DATA_WIDTH-1:0]  s_rdata,
    output logic [INPUTS-1:0][1:0]             s_rresp,
    output logic [INPUTS-1:0]                  s_rlast,
    // To frontend
    output logic [OUTPUTS-1:0]                 release_valid,
    output logic [INPUTS-1:0]                  complete_valid,
    output logic [INPUTS-1:0][ID_WIDTH-1:0]    complete_id
);
    logic [OUTPUTS-1:0]            head_valid;
    logic [OUTPUTS-1:0]            head_pop;
    logic [OUTPUTS-1:0][BEAT_WIDTH-1:0] head_data;
    logic [OUTPUTS-1:0][OUTPUT_ID_WIDTH-1:0] head_id;
    logic [OUTPUTS-1:0][DATA_WIDTH-1:0]      head_pdata;
    logic [OUTPUTS-1:0][1:0]                 head_resp;
    logic [OUTPUTS-1:0]                      head_last;
    logic [INPUTS-1:0]                       full;
    logic [INPUTS-1:0]                       capture;
    logic [INPUTS-1:0][SELECT_WIDTH-1:0]      selected;
    logic [INPUTS-1:0]                        locked;
    logic [INPUTS-1:0][SELECT_WIDTH-1:0]      locked_source;

    initial begin
        assert (INPUTS > 0 && OUTPUTS > 0 && DATA_WIDTH >= 8 &&
                DATA_WIDTH % 8 == 0 && RESPONSE_DEPTH > 0 &&
                OUTPUT_ID_WIDTH == ID_WIDTH + SOURCE_WIDTH)
            else $fatal(1, "RDATA_PARAMETERS");
    end

    for (genvar o = 0; o < OUTPUTS; o++) begin : egress
        axi_record_fifo #(.WIDTH(BEAT_WIDTH), .DEPTH(RESPONSE_DEPTH)) buffer (
            .clk(clk), .reset_n(reset_n),
            .push_valid(m_rvalid[o]), .push_ready(m_rready[o]),
            .push_data({m_rid[o], m_rdata[o], m_rresp[o], m_rlast[o]}),
            .pop_valid(head_valid[o]), .pop_ready(head_pop[o]),
            .pop_data(head_data[o]), .count()
        );
        assign {head_id[o], head_pdata[o], head_resp[o], head_last[o]} = head_data[o];
        assign release_valid[o] = m_rvalid[o] && m_rready[o] && m_rlast[o];
        assert property (@(posedge clk) disable iff (!reset_n)
            m_rvalid[o] |-> int'(m_rid[o][OUTPUT_ID_WIDTH-1:ID_WIDTH]) < INPUTS)
            else $fatal(1, "RDATA_INVALID_SOURCE");
    end

    always_comb begin
        head_pop = '0;
        for (int i = 0; i < INPUTS; i++) begin
            if (capture[i])
                head_pop[selected[i]] = 1;
        end
    end

    for (genvar i = 0; i < INPUTS; i++) begin : ingress
        logic [OUTPUTS-1:0] request;
        logic selected_valid;
        for (genvar o = 0; o < OUTPUTS; o++) begin : contenders
            assign request[o] = head_valid[o] &&
                                head_id[o][OUTPUT_ID_WIDTH-1:ID_WIDTH] == SOURCE_WIDTH'(i) &&
                                (!locked[i] || locked_source[i] == SELECT_WIDTH'(o));
        end
        axi_rr_arbiter #(.PORTS(OUTPUTS)) arbiter (
            .clk(clk), .reset_n(reset_n),
            .request(request), .grant_ready(!full[i]),
            .grant_valid(selected_valid), .grant_index(selected[i]),
            .grant_onehot(), .request_ready()
        );
        assign capture[i] = selected_valid && !full[i];
        assign s_rvalid[i] = reset_n && full[i];
        assign complete_valid[i] = s_rvalid[i] && s_rready[i] && s_rlast[i];
        assign complete_id[i] = s_rid[i];
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                full[i]         <= 0;
                s_rid[i]        <= '0;
                s_rdata[i]      <= '0;
                s_rresp[i]      <= '0;
                s_rlast[i]      <= 0;
                locked[i]       <= 0;
                locked_source[i] <= '0;
            end
            else if (capture[i]) begin
                full[i]    <= 1;
                s_rid[i]   <= head_id[selected[i]][ID_WIDTH-1:0];
                s_rdata[i] <= head_pdata[selected[i]];
                s_rresp[i] <= head_resp[selected[i]];
                s_rlast[i] <= head_last[selected[i]];
                locked[i]  <= !head_last[selected[i]];
                locked_source[i] <= selected[i];
            end
            // Master accepted any beat: free the output register so the next
            // beat can capture. complete_valid (RLAST only) drives the tracker
            // separately and does not gate the output register here.
            else if (s_rvalid[i] && s_rready[i]) begin
                full[i] <= 0;
            end
        end
        assert property (@(posedge clk) disable iff (!reset_n)
            s_rvalid[i] && !s_rready[i] |=>
                s_rvalid[i] && $stable({s_rid[i], s_rdata[i], s_rresp[i], s_rlast[i]}))
            else $fatal(1, "RDATA_UNSTABLE");
    end
endmodule
