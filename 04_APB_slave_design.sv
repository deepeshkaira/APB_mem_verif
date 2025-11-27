module apb_slave(
	input logic pclk,
	input logic presetn,
	input logic psel,
	input logic penable,
	input logic pwrite,
	input logic [7:0] paddr,pwdata,
	
	output logic [7:0] prdata,
	output logic pready,
	output logic pslverr
);

logic [7:0] addr;
logic [7:0] mem[63:0];

assign prdata = mem[addr];

always@(*)
	begin
		if(!presetn) pready = 0;
		else if(psel && !penable && !pwrite)  pready = 0;
		else if(psel && penable && !pwrite)
			begin
				pready = 1;
				addr = paddr;
			end
		else if(psel && !penable && pwrite)  pready = 0;
		else if(psel && penable && pwrite)
			begin
				pready = 1;
				mem[addr] = pwdata;
			end
		else pready = 0;
	end

endmodule