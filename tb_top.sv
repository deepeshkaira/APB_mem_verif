`include "package.svh"
`include "apb_mem.sv"

module top;
    bit clk;

    APB_intf intf(clk);

    apb_mem dut(.PCLK(clk), .PRESETn(intf.PRESETn), .PSEL1(intf.PSEL1), .PWRITE(intf.PWRITE), 
                .PENABLE(intf.PENABLE), .PADDR(intf.PADDR), .PWDATA(intf.PWDATA),
                .PRDATA(intf.PRDATA), .PREADY(intf.PREADY), .PSLVERR(intf.PSLVERR));

    always #5 clk = ~clk;

    initial begin
        uvm_config_db#(virtual APB_intf)::set(null, "*", "vif", intf);
        run_test("base_test");
    end
endmodule