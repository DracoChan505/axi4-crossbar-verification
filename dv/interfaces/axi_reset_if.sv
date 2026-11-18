// Reset control interface: allows the UVM test to drive mid-flight reset.
interface axi_reset_if(input bit clk);
    logic reset_n = 0;
    clocking cb @(posedge clk);
        output reset_n;
    endclocking
    clocking mon @(posedge clk);
        input reset_n;
    endclocking
endinterface
