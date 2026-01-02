`timescale 1ns / 1ns

// apb_memory NO latch design

module apb_mem_NL #(parameter DEPTH = 5) (
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
// This is actually correct value check for PSLVERR because APB memory is byte addressable. (go through the concept whenevr confused)
						// if((PADDR[DEPTH+1:2] >= 2**DEPTH))
                        if ( (PADDR >> 2) >= 2**DEPTH )
                            // can include this condition as well to pull up the pslverr high
                            // || ((!PWRITE) && mem[PADDR[DEPTH-1:0]] == 32'hffffffff))
							PSLVERR_reg <= 1;
                        else 
                            PSLVERR_reg <= 0;
						
// ADDRESSING NOTE: APB is Byte-Addressable, Memory is Word-Indexed (32-bit).
// We discard the lower 2 bits (byte offset) to convert Byte Addr -> Word Index.
//
// Example: (go through this to get rid of confusion)
//   PADDR = 0x00 -> Index 0  (mem[0])
//   PADDR = 0x04 -> Index 1  (mem[1])
//   PADDR = 0x08 -> Index 2  (mem[2])
//
// Implementation: Use PADDR[DEPTH+1:2] instead of PADDR[DEPTH-1:0]

						if(!PWRITE) PRDATA_reg <= mem[PADDR[DEPTH+1:2]];
					end
				end

				ACCESS: begin
					PREADY_reg <= 0;
					if(PWRITE && !PSLVERR_reg) begin
						mem[PADDR[DEPTH+1:2]] <= PWDATA;
					end
				end
			endcase
            end
    end

// Check: When writing, Data must never be X or Z
property p_valid_write_data;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL1 && PENABLE && PWRITE) |-> !$isunknown(PWDATA);
endproperty

assert_valid_data: assert property (p_valid_write_data)
    else $error("APB PROTOCOL VIOLATION: Write Data contains X or Z");

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
// this state has been added just in case the PENABLE signal never come to the design and we will be stuck here forever.
// If some master had instructions to come to SETUP state after the design is done with ACCESS. And after that it disconnects with the
// slave. During this PENABLE will never come and the FSM will be stuck in this state forever. Even if some other MASTER comes and want to access memory. It willl be an issue because the 
// slave is stuck in the SETUP state. (for more check the DOC)
                if (!PSEL1) next_state = IDLE;   
                else if (PENABLE) next_state = ACCESS;
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
