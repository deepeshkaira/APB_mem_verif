`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.12.2025 01:25:58
// Design Name: 
// Module Name: apb_mem
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



module apb_mem #(parameter DEPTH = 5) (
    input logic PCLK,
    input logic PRESETn,
    input logic PSEL1,
    input logic PWRITE,
    input logic PENABLE,
    input logic [31:0] PADDR,
    input logic [31:0] PWDATA,

    // outputs
    output logic [31:0] PRDATA,
    output logic PREADY, PSLVERR
);

    typedef enum bit[1:0] {IDLE,SETUP,ACCESS} state_t;
    state_t state,next_state;

    logic [31:0] mem [2**DEPTH-1:0];
    logic [31:0] PRDATA_reg;
    logic PREADY_reg;
    logic PSLVERR_reg;

    always @(posedge PCLK or negedge PRESETn ) begin
        
        if(!PRESETn) begin
            state <= IDLE;
            PRDATA_reg <= '0;
            PREADY_reg <= 0;
            PSLVERR_reg <= 0;
            foreach(mem[i]) mem[i] <= 32'hffffffff;
        end
        else
            begin
            state <= next_state;
			case(state)
				IDLE:begin
					PRDATA_reg <= '0;
            		PREADY_reg <= 0;
            		PSLVERR_reg <= 0;
				end

				SETUP:begin
					if(PENABLE) begin
						PREADY_reg <= 1;
						if((PADDR >= 2**DEPTH) || (PWRITE && (PWDATA === 32'hx || PWDATA === 32'hz) || ((!PWRITE) && mem[PADDR[DEPTH-1:0]] == 32'hffffffff))) begin
							PSLVERR_reg <= 1;
						end
						if(!PWRITE) PRDATA_reg <= mem[PADDR[DEPTH-1:0]];
					end
				end

				ACCESS: begin
					PREADY_reg <= 0;
					if(PWRITE && !PSLVERR_reg) begin
						mem[PADDR[DEPTH-1:0]] <= PWDATA;
					end
				end
			endcase
            end
    end

	assign PRDATA = PRDATA_reg;
	assign PREADY = PREADY_reg;
	assign PSLVERR = PSLVERR_reg;

    always_comb begin
        next_state = state;
        case (state)
            IDLE:                
            begin
                if(PSEL1) next_state = SETUP;
                else next_state = state;
            end
                
            SETUP:
            begin
                if(PSEL1 && PENABLE) next_state = ACCESS;
                else  next_state = state;
            end

            ACCESS:
            begin
                // going back to read/write in memory if PSEL1 = 1. Else, going back to the SETUP state.
                if(!PSEL1) next_state = IDLE;
                else next_state = SETUP;
            end 
        endcase
    end

endmodule 
