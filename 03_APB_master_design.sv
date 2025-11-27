module apb_master(
	input logic [7:0] apb_write_paddr, apb_read_paddr,
	input logic [7:0] apb_write_data, prdata,
	input logic presetn,
	input logic pclk,
	input logic read,
	input logic write,
	input logic transfer,
	input logic pready,

	output logic psel1,psel2,
	output logic penable,
	output logic [8:0] paddr,
	output logic pwrite,
	output logic [7:0] pwdata, apb_read_data_out,
	output logic pslverr
	);

	
	logic invalid_setup_error;
	logic invalid_read_paddr;
	logic invalid_write_paddr;
	logic invalid_write_data;

	typedef enum [1:0]bit { IDLE,SETUP,ENABLE } state_t;
	state_t present_state,next_state;

	always@(@posedge clk)
		begin
			if(!resetn) present_state <= IDLE;
			else present_state <= next_state;
		end

	always@(present_state,transfer,pready)
		begin
			pwrite = write;

			case(present_state)
				IDLE: begin
					penable = 0;
					if(!transfer) next_state = IDLE;
					else next_state = SETUP;
				end

				SETUP: begin
					penable = 0;
					case({read,write})
						2'b10: begin
							paddr = apb_read_paddr;
							next_state = ENABLE;
						end
						2'b01: begin
							paddr = apb_write_paddr;
							pwdata = apb_write_data;
							next_state = ENABLE;
						end
						default: begin
							next_state = present_state;
						end
					endcase
				end

				ENABLE: begin
					penable = 1'b1;					
					if(pready)
						begin
							if(read == 1'b1 && write == 1'b0) next_state = SETUP;
							else if(read == 1'b0 && write == 1'b1) 
									begin
										next_state = SETUP;
										apb_read_data_out = prdata;
									end	
						end
					else 
						next_state = present_state;

				end

			endcase
		end

	// PSLAVE ERROR LOGIC
	always@(*)
		begin
			invalid_setup_error = setup_error || invalid_read_paddr || invalid_write_data || invalid_write_paddr;
			if(!presetn) begin
				setup_error = 0;
				invalid_read_paddr = 0;
				invalid_write_paddr = 0;
				invalid_write_data = 0;
			end
			else if(present_state == IDLE &&  next_state == ENABLE)
				begin
					setup_error = 1'b1;
				end
			else if((apb_write_data == 8'dx) && (read == 1'b0) && (write == 1'b1) && (present_state == SETUP || present_state == ENABLE))
				begin
					invalid_write_data = 1'b1;
				end
			else if((apb_read_paddr == 9'dx) && (read == 1'b1) && (write == 1'b0) && (present_state == SETUP  || present_state == ENABLE))
				begin
					invalid_read_paddr = 1'b1;
				end
			else if((apb_write_paddr == 9'dx) && (read == 1'b0) && (write == 1'b1) && (present_state == SETUP || present_state == ENABLE))
				begin
					invalid_write_paddr = 1'b0;
				end
			else 
				begin
					invalid_write_paddr = 1'b0;
					invalid_write_data = 1'b0;
					invalid_read_paddr = 1'b0;
				end
		end

	assign pslverr = invalid_setup_error;

endmodule