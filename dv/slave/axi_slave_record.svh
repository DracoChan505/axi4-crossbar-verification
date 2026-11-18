// One accepted AW. Its identity survives until the corresponding B handshake.
class axi_slave_record;
    longint unsigned epoch;
    longint unsigned aw_seq;
    longint unsigned aw_cycle;
    longint unsigned w_done_cycle;
    longint unsigned response_delay;
    bit [ADDR_W-1:0] address;
    bit [ID_W-1:0] id;
    bit [7:0] len;
    bit [2:0] size;
    bit [1:0] burst;
    bit lock;
    bit [3:0] cache;
    bit [2:0] prot;
    bit [3:0] qos;
    int unsigned beats;
    int unsigned received = 0;
    bit write_done = 0;
    bit reject_write = 0;
endclass
