// this is a apb slave memory, we are reading the data from the memory location.
// also, we are writing the data to the memory location.

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

    logic [1:0] delay;

    logic [31:0] mem [2**DEPTH-1:0];

    always @(posedge PCLK or negedge PRESETn ) begin
        
        if(!PRESETn) begin
            state <= IDLE;
            foreach(mem[i]) mem[i] = 32'($unsigned(i));
        end
        else
            state <= next_state;
    end

    always @(state, PSEL1, PENABLE) begin
        case (state)
            IDLE:                
            begin
                
                PSLVERR = 0;
                PREADY = 0;
                PRDATA = 32'h0;
                if(PSEL1) next_state = SETUP;
                else next_state = IDLE;
            end
                
            SETUP:
            begin
                
                PREADY = 0;
                PSLVERR =0;

                // technically , the "PENABLE" signal should be equal to "1" as soon as we reach the SETUP state but in case if it is not "1" for 
                // lets say 1 cycle, then it should stay in the "SETUP" state.

                // our reading should be finished in this cycle only. We should be throwing out the value at the mentioned memory address after fetching it.

                if(PENABLE) begin
                    
                    PREADY = 1;
                    if(PADDR >= 2**DEPTH) PSLVERR = 1;
                    else if(PWRITE && (PWDATA === 32'hx || PWDATA === 32'hz)) PSLVERR = 1;
                    else if(!PWRITE) begin
                        PRDATA = mem[PADDR[DEPTH-1:0]];
                        if(mem[PADDR[DEPTH-1:0]] == 32'hffffffff) begin
                            $display("FSM_MSG SETUP_DESIGN. PADDR is %d and content is %h", PADDR, mem[PADDR[DEPTH-1:0]]);
                            PSLVERR = 1;
                            $error("FSM_MSG SETUP_DESIGN. Reading data from unwritten address");
                        end

                    end
                    next_state = ACCESS;
                end   
                else
                    next_state = state;
            end

            ACCESS:
            begin
                
                PREADY = 0;
                if(PWRITE && !PSLVERR) begin
                    mem[PADDR[DEPTH-1:0]] = PWDATA;
                end
                
                // going back to read/write in memory if PSEL1 = 1. Else, going back to the SETUP state.
                if(!PSEL1)
                    next_state = IDLE;
                else
                    next_state = SETUP;
            end 
        endcase
    end

endmodule