//      // verilator_coverage annotation
        typedef enum int { SLAVE_AW, SLAVE_WRITE, SLAVE_B, SLAVE_RESET } axi_slave_event_kind;
        
        // Published events are snapshots; the Monitor never publishes its live record.
        class axi_slave_observation extends uvm_object;
%000000     `uvm_object_utils(axi_slave_observation)
            axi_slave_event_kind kind;
            longint unsigned epoch;
            longint unsigned serial;
            longint unsigned event_cycle;
            longint unsigned aw_cycle;
            longint unsigned w_cycle;
            longint unsigned b_cycle;
            bit [ADDR_W-1:0] address;
            bit [ID_W-1:0] id;
            bit [7:0] len;
            bit [2:0] size;
            bit [16:0] attr;
            bit [1:0] response;
            bit [DATA_W-1:0] data[$];
            bit [STRB_W-1:0] strb[$];
 002655     bit write_done = 0;
            int cancelled_aw;
~002655     function new(string name = "axi_slave_observation");
 002655         super.new(name);
            endfunction
 001935     function axi_slave_observation snapshot(axi_slave_event_kind event_kind, longint unsigned now_cycle);
 001935         axi_slave_observation result;
 001935         result = new;
 001935         result.kind = event_kind;
 001935         result.epoch = epoch;
 001935         result.serial = serial;
 001935         result.event_cycle = now_cycle;
 001935         result.aw_cycle = aw_cycle;
 001935         result.w_cycle = w_cycle;
 001935         result.b_cycle = b_cycle;
 001935         result.address = address;
 001935         result.id = id;
 001935         result.len = len;
 001935         result.size = size;
 001935         result.attr = attr;
 001935         result.response = response;
 001935         result.data = data;
 001935         result.strb = strb;
 001935         result.write_done = write_done;
 001935         result.cancelled_aw = cancelled_aw;
 001935         return result;
            endfunction
        endclass
        
 001258 class axi_slave_observed_burst;
            bit [DATA_W-1:0] data[$];
            bit [STRB_W-1:0] strb[$];
            longint unsigned last_cycle;
        endclass
        
