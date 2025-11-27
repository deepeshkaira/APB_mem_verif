module apb_top(
	input logic pclk,presetn,transfer,read,write,
	input logic [8:0] apb_write_paddr,
	input logic [7:0] apb_write_data,
	input logic [8:0] apb_read_paddr,
	output logic pslverr,
	output logic [7:0] apb_read_data_out
);

logic [7:0] pwdata,prdata,prdata1,prdata2;
logic [8:0] paddr;
logic pready,pready1,pready2,penable,psel1,psel2,pwrite;

	apb_master dut_master(
		.apb_write_paddr(),
		.apb_read_paddr(),
		.apb_write_data(),
		.prdata(),
		.presetn(),
		.pclk(),
		.read(),
		.write(),
		.transfer(),
		.pready(),

		/// outputs
		.psel1(),
		.psel2(),
		.penable(),
		.paddr(),
		.pwrite(),
		.pwdata(), 
		.apb_read_data_out(),
		.pslverr()
	);


	apb_slave dut_slave_1(
		.pclk(),
		.presetn(),
		.psel(),
		.penable(),
		.pwrite(),
		.paddr(),
		.pwdata(),

		//outputs
		.prdata(),
		.pready()
	);


	apb_slave dut_slave_2(
		.pclk(),
		.presetn(),
		.psel(),
		.penable(),
		.pwrite(),
		.paddr(),
		.pwdata(),

		//outputs
		.prdata(),
		.pready()
	);

endmodule