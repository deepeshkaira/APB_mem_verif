`timescale 1ns/1ns
`include "uvm_macros.svh"
import uvm_pkg::*;

/////////////////////////////////
///// INTERFACE n ASSERTIONS ////
/////////////////////////////////

//   4 Property of APB Protocol is asserted
// /////  assertions
//     1. PENABLE should be HIGH one clock cycle after PSEL1 rise (0 -> 1)
//     2. All signals are stable or not when PENABLE is ASSERTED 
//     3. PENABLE should fall (1 -> 0) one cycle after PREADY is ASSERTED
//     4. PENABLE should not fall, even if PREADY is not ASSERTED
    
interface APB_intf (input logic clk);
        logic PWRITE;
        logic [31:0] PWDATA;
        logic [31:0] PRDATA;
        logic [31:0] PADDR;
        logic PREADY;
        logic PRESETn;
        logic PENABLE;
        logic PSLVERR;
        logic PSEL1;
    
        // this is how we are going to tell the design what ports to be considered as input or output
        // at certain instance of time from and to driver port.
        clocking drv_cb @(posedge clk);
            output PWRITE, PWDATA, PADDR, PENABLE, PRESETn, PSEL1;
            input PREADY; 
        endclocking
       
        // this defines the input for the monitor block
        clocking mon_cb @(posedge clk);
            input PWRITE, PWDATA, PADDR, PENABLE, PRESETn, PSEL1; 
            input #1 PRDATA, PREADY, PSLVERR;   
        endclocking
    
        // WHY TO USE the MODPORT
        // Without a clocking block, if the Driver drives a signal at the exact same picosecond that the Clock rises, we get a Race Condition.
        // The DUT might see the old value or the new value, leading to unpredictable bugs.

        //  By using modport, SystemVerilog automatically handles:
            
        // 1. Input Skew: It samples inputs (like PREADY) slightly before the clock edge (stable value).
            
        // 2. Output Skew: It drives outputs (like PSEL) slightly after the clock edge (hold time).
        
        // anything connecting to the DRV modport must access signals exclusively through the "drv_cb" clocking block. 
        modport DRV (clocking drv_cb);
        // anything connecting to the MON modport must access signals exclusively through the "mon_cb" clocking block.
        modport MON (clocking mon_cb);

		//-------------------------- Assertions  -------------------------------

        // to check whether PENABLE is asserted 1 clk after PSEL1 is asserted
        property enable_ch;
            @(posedge clk) $rose(PSEL1) |=> PENABLE;
        endproperty

        // check whether PREADY is asserted only when PSEL1 and PENABLE are high
        property check_PR_PSL_PEN;
            @(posedge clk) PSEL1 && (PENABLE) |-> PREADY;
        endproperty

        // to check whether all signal are stable or not during the PENABLE assertion in the SETUP state
        // in the same clock cycle
        property stable_ch;
            @(posedge clk) $rose(PENABLE) |-> $stable(PADDR) ##0 $stable(PWDATA) ##0 $stable(PWRITE) ##0 $stable(PSEL1);
        endproperty




        // Property to chek whether the PENABLE is deasserted 1 clk after PREADY signal is asserted
        sequence s1;
            !($past(PENABLE, 2) && $past(PREADY, 2));
        endsequence

        property enable_deassert_ch;
            @(posedge clk)
            (s1 and $rose(PREADY)) |=> $fell(PENABLE);
        endproperty
        

        // Property to check whether the PENABLE is deasserted without PREADY being asserted. Also, added to skip the first check after reset.
        // since, PREADY will never be high in the past when simulation has just started, adding and checking PENABLE was 1 anytime when PREADY, makes sense
        property enable_deassert_ch2;
            @(posedge clk)
            if((PRESETn) && !$isunknown(PENABLE))
                $fell(PENABLE) && $past(PENABLE,1,PREADY) |-> $past(PREADY) == 1;
        endproperty
    
        // properties defined earlier are asserted here.
        assert property (enable_ch)
            `uvm_info("enable_ch", "ENABLE DRIVEn 1 CYCLE AFTER PSEL1", UVM_DEBUG)
        else
            `uvm_error("enable_ch", "ENABLE NOT DRIVEn 1 CYCLE AFTER PSEL1")

        assert property (check_PR_PSL_PEN)
            `uvm_info("check_PR_PSL_PEN", "PREADY is 1 only when PSEL1 and PENABLE are both 1", UVM_DEBUG)
        else
            `uvm_info("check_PR_PSL_PEN", "PREADY is NOT 1, while PSEL1 and PENABLE are both 1", UVM_DEBUG)

        assert property (stable_ch) 
            `uvm_info("stable_ch", "ALL SIGANLS STABLE DURING PENABLE", UVM_DEBUG)
        else
            `uvm_error("stable_ch", "ALL SIGANLS NOT STABLE DURING PENABLE")
    
        assert property (enable_deassert_ch) 
            `uvm_info("enable_deassert_ch", "PENABLE DEASSERTED 1 CLK AFTER PREADY", UVM_DEBUG)
        else
            `uvm_error("enable_deassert_ch", "PENABLE NOT DEASSERTED 1 CLK AFTER PREADY")
    
        assert property (enable_deassert_ch2) 
            `uvm_info("enable_deassert_ch2", "PENABLE DEASSERTED WHEN PREADY ASSERTED", UVM_DEBUG)
        else
            `uvm_error("enable_deassert_ch2", "PENABLE GETTING DEASSERTED WITHOUT PREADY BEING ASSERTED")
   
endinterface


//////////////////////////////////////
///////////  agent_config ////////////
//////////////////////////////////////

class agent_config extends uvm_object;
    `uvm_object_utils(agent_config)

    // Virtual Interface
    virtual APB_intf intf;

    // active
    uvm_active_passive_enum active = UVM_ACTIVE;
    
    function new(string name = "agent_config");
        super.new(name);
        `uvm_info("agent_config","agent_config block got executed",UVM_NONE);
    endfunction
endclass

///////////////////////////////////////
//////////// MY SEQUENCE ITEM /////////
//////////// TRANSACTION //////////////
///////////////////////////////////////	

class transaction extends uvm_sequence_item;
    // `uvm_object_utils(transaction);			// removing this to register the variables individually and use the functons

    //  Vars  declration
    static bit [9:0] p_id;      // Packet id
    static bit [3:0] f_id;      // Feature id
    rand bit PWRITE;            // Read/Write
    rand logic [31:0] PWDATA [];   
    rand logic [31:0] PADDR [];   
    rand bit PRESETn;
    // bit PRESETn;
    
    rand bit error_case;        // To generate random error case
    rand bit PSEL1;
    bit PENABLE;

    bit PREADY;
    bit [31:0] PRDATA [];
    bit PSLVERR;

	// register the varibles here for using the inbuilt functions like copy, compare etc etc
    `uvm_object_utils_begin(transaction)
        `uvm_field_int(PWRITE, UVM_ALL_ON)
        `uvm_field_int(PSEL1, UVM_ALL_ON)
        `uvm_field_int(PENABLE, UVM_ALL_ON)
        `uvm_field_int(PRESETn, UVM_ALL_ON)
        `uvm_field_int(PSLVERR, UVM_ALL_ON)
        `uvm_field_int(PREADY, UVM_ALL_ON)
        
        // array macros for array vars
        `uvm_field_array_int(PADDR, UVM_ALL_ON)
        `uvm_field_array_int(PWDATA, UVM_ALL_ON)
        `uvm_field_array_int(PRDATA, UVM_ALL_ON)
    `uvm_object_utils_end

    // Constraints
    // if PRESETn is 0;  data and address size = 1
    // else generate random values for PWDATA and PWADDR. these arrays can have max 3 values and min 1 values
    // also, keep the number of ADDRESSES and DATA same.
    constraint arr_size {
        if(!PRESETn) {
            PWDATA.size() == 1; 
            PADDR.size() == 1;
        }
        else {
            PWDATA.size() inside {[1:30]}; 
            PADDR.size() inside {[1:30]};
        }
        PWDATA.size() == PADDR.size();
    }

    // Zero out Write Data during Read operations
    // the above constraint and the below constraint will contradict each other, lets run simulation and see what happens
    constraint clean_read_data {
        if (PWRITE == 0) {
            foreach (PWDATA[i]) {
                PWDATA[i] == 32'h0;
            }
        }
    }

    // Ensure addresses are 32-bit aligned (Byte Addressing)
    constraint align_addr {
        foreach(PADDR[i]) {
            PADDR[i] % 4 == 0; 
        }
    }
 
    // If DEPTH=5 then we have 32 words. Max Byte Address = 31*4 = 124
    constraint paddr_val {
        !error_case -> 
            foreach(PADDR[i]) 
                PADDR[i] inside {[0 : (2**5)*4 - 4]};
            // to check whether the design is going to write on to the memory locations
                    // PADDR[i] inside {[0 : (2**5)*5]};
    }

    constraint reset_dist { 
        PRESETn dist {0:=1 ,1:=200};
    }
    constraint sel_dist { PSEL1 dist {0:=10, 1:=90}; }
    constraint err_case_dist { error_case dist {1:=5, 0:=100}; } // Generates error test cases

    // Constraint for a specific memory size, can be commented for general use
    // constraint paddr_val {
    //     !error_case -> 
    //         foreach(PADDR[i]) 
    //             PADDR[i] inside {[0:(2**5)-1]};
    // }

    //  Constructor: new
    function new(string name = "transaction");
        super.new(name);
    endfunction: new

    // Functions
    /// this tells us the number of test packets we are dealing with
    function void pre_randomize();
        `uvm_info("TRANSACTION",$sformatf("This is value for p_id : %0d",p_id),UVM_NONE)
        p_id++;
    endfunction

    // this tells us the type of check we are doing with the current packet
    function void post_randomize();
        if(!PRESETn) f_id = 5;
        // for write operations
        else if (PWRITE && PADDR.size() == 1)  f_id = 1;
        else if (PWRITE && PADDR.size() > 1)   f_id = 2;
        // for read operations
        else if (!PWRITE && PADDR.size() == 1)   f_id = 3;
        else if (!PWRITE && PADDR.size() > 1)   f_id = 4;
    endfunction

    // Increases the size of the dynamic array. Helper function for IP/OP monitor which needs to
    // sample data and store in array (as monitor does not know the size of the transfer thus needs
    // to increase and add value dynamically)
    function void increaseSize();
        if(PWDATA.size() == 0)
            PWDATA = new[1];
        else
            PWDATA = new[PWDATA.size()+1] (PWDATA);

        if(PADDR.size() == 0)
            PADDR = new[1];
        else
            PADDR = new[PADDR.size()+1] (PADDR);    
    endfunction

    /// functions , may use at some stage

    //  convert2string
    virtual function string convert2string();
        string s;
        s = super.convert2string();

        /*  list of local properties to be printed:  */
        s = {s, $sformatf("Time : %0t, Packet ID: %0d, Feature ID: %0d\n",$realtime, p_id, f_id)};
        s = {s, $sformatf("Time : %0t, Input to DUT: PWRITE = %b, PRESETn = %b, PSEL1 = %b, PWDATA = %p, PADDR = %p\n",$realtime, PWRITE, PRESETn, PSEL1, PWDATA, PADDR)};
        s = {s, $sformatf("Time : %0t, OUPUT from DUT: PREADY = %b, PRDATA = %p, PSLVERR = %b",$realtime, PREADY, PRDATA, PSLVERR)};

        return s;
    endfunction: convert2string
        
endclass: transaction


/////////////////////////////////
//////// FUNCTIONAL COVERAGE ////
/////////////////////////////////

// we are using subscriber here because in this we don't need to explicitly define the analysis ports for catching 
// the incoming data. Lets say from the DUT, it should automatically take the incoming data to the class.
// and further use it for coverage analysis.
class fun_cov extends uvm_subscriber#(transaction);
    `uvm_component_utils(fun_cov)
    
    // Variables
    transaction trans;
    bit [31:0] _tempPADDR, _tempPWDATA, _tempRDATA;

    // Covergroup for Functional coverage
    covergroup apb_cg; 
        PSEL1: coverpoint trans.PSEL1 { 
            bins psel1 = {1};
            illegal_bins il_psel1= {0};
        }
        PWRITE: coverpoint trans.PWRITE {
            bins pwrite[] = {0, 1};
        }
        PWDATA: coverpoint _tempPWDATA {
            bins pwdata[16] = {[0:32'hffffffff]}; 
        }
        /*
        PADDR: coverpoint _tempPADDR { 
            bins paddr[] = {[0:32'h0000001f]}; 
            illegal_bins il_paddr = default;
        }
            */
        PREADY: coverpoint trans.PREADY { 
            bins pready = {1};
            illegal_bins il_pready= {0};
        }
        PRDATA: coverpoint _tempRDATA {
            bins prdata[16] = {[0:32'hffffffff]};
        }
        PSLVERR: coverpoint trans.PSLVERR { 
            bins pslverr[] = {0, 1}; 
        }
        PWRITE_TRANS: coverpoint trans.PWRITE{  // to check the transition coverage
            bins write_to_read = (1 => 0);
            bins read_to_write = (0 => 1);
        }
        PADDR_CORNERS: coverpoint _tempPADDR {
            bins low = {0};
            bins high = {32'h0000007C}; // Max byte address for Depth 5 (31*4)
            bins others = default;
        }
        PSEL1xPWRITE: cross PSEL1, PWRITE {
            ignore_bins ig_bins = binsof(PSEL1) intersect{0}; 
        }
        PSEL1xPWRITExPADDR: cross PSEL1, PWRITE, _tempPADDR { 
            ignore_bins ig_bins = binsof(PSEL1) intersect{0}; 
        }

    endgroup

    /* Function for sampling data for coverage
       It has to be done because the trans.PADDR and other data signals are unpacked array as they have to 
       store more than one element for multiple transfer packet. Thus a loop is used and each element is stored 
       in temperory variable and then sampled.
       Advantage - Easy to implement Disadvantage - Lot of signals will be sampled more than once for same value */
    function void cov_sample;
        `uvm_info("COV_SAMPLES_NUMBER",$sformatf("total number of cases : %0d",trans.PADDR.size()),UVM_NONE);
        // this will be checking the coverage as per the number of the addresses in the ADDR array.
        for(int j = 0; j < trans.PADDR.size(); j++) begin
            _tempRDATA = trans.PRDATA[j];
            _tempPWDATA = trans.PWDATA[j];
            _tempPADDR = trans.PADDR[j];
            /// this is to sample the incoming data to check coverage
            apb_cg.sample();
            // `uvm_info("COV",$sformatf("this is coverage sample number %0d",j),UVM_NONE);
        end
    endfunction

    // Constructor: new
    function new(string name, uvm_component parent);
        super.new(name, parent);
        apb_cg = new();
    endfunction //new()

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        trans = new("cov_trans");
    endfunction: build_phase

    // function declared here catches the incoming data from the external classes, like monitor
    function void write(transaction t);
        trans = t;
        cov_sample();
    endfunction

    
endclass


///////////////////////////////////////
//////////// MY SEQUENCES /////////////
///////////////////////////////////////	

class rnd_sequence extends uvm_sequence;
    `uvm_object_utils(rnd_sequence);

    //  Group: Variables
    transaction trans;
    int no_of_testcases;
    virtual APB_intf intf;

    //  Constructor: new
    function new(string name = "rnd_seq");
        super.new(name);
        trans = transaction::type_id::create("trans");
        // get number of cases here
        if(!uvm_config_db#(int)::get(null, "seq.", "no_cases", no_of_testcases)) begin
            `uvm_warning(get_name(), "Cant get no of testcases, Using default no of test cases = 10")
            // just in case there is an issue in recieving the number of testcases from config_db
            no_of_testcases = 10;
        end

        // get the interface here from config db
        if(!uvm_config_db#(virtual APB_intf)::get(null, "env.agnt.*", "intf", intf)) begin
            `uvm_info("SEQ", "Interface handle not found", UVM_LOW)
       end
    endfunction

    // reset task
    virtual task reset_dut();
        `uvm_info(get_name(), " Asserting System RESET", UVM_NONE)
        
        start_item(trans);        
        trans.PRESETn = 0;    
        trans.PWRITE  = 0;    
        trans.PSEL1   = 0;    
        trans.PENABLE = 0;
        
        // Initialize Dynamic Arrays here because now I am manually driving these values for those variables.
        // Since I am not randomizing, I must allocate memory manually.
        trans.PADDR   = new[1]; 
        trans.PWDATA  = new[1];
        
        // Set Data/Addr to 0
        trans.PADDR[0]  = 32'h0;
        trans.PWDATA[0] = 32'h0;       
        finish_item(trans);
        
        `uvm_info(get_name(), " System RESET Complete.", UVM_NONE)
    endtask

    //  Task: pre_body
    //  This task is a user-definable callback that is called before the execution 
    //  of <body> only when the sequence is started with <start>.
    //  If <start> is called with ~call_pre_post~ set to 0, ~pre_body~ is not called.
    
    // virtual task pre_body();
    //     start_item(trans);
    //     `uvm_info("rnd_sequence",$sformatf("Running pre-body at time %0t",$realtime),UVM_NONE)
    //     trans.p_id = 1;
    //     trans.f_id = 5; 
    //     // trans.PRESETn = 0;
    //     trans.PADDR = {32'h0};
    //     trans.PWDATA = {32'h0};
    //     finish_item(trans);
    // endtask

    //  Task: body
    //  This is the user-defined task where the main sequence code is written

    virtual task body();
        `uvm_info("rnd_sequence","rnd_sequence block got executed",UVM_NONE);
        for (int i = 0; i < no_of_testcases-1; i++) begin
            start_item(trans);
            if(!trans.randomize())
                `uvm_fatal(get_name(), "Randomization failed");

            finish_item(trans);
            `uvm_info("rnd_sequence",$sformatf("executed test case number : %0d",i),UVM_NONE)
        end
    endtask: body

endclass: rnd_sequence


///////// apb_write_sequence
///////////////////////////////////////

class apb_write_seq extends rnd_sequence;
    `uvm_object_utils(apb_write_seq)

    function new(string name="apb_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info(get_name(), "--------------------------", UVM_LOW)
        `uvm_info(get_name(), "Seq statr: apb_write_seq", UVM_LOW)
        `uvm_info(get_name(), "-----------------------------", UVM_LOW)

        // SYSTEM RESET
        reset_dut();

        // RANDOM WRITE TRAFFIC
        `uvm_info(get_name(), " Starting Random Write Bursts", UVM_MEDIUM)
        
        repeat(no_of_testcases) begin
            start_item(trans);
            
            // applied minimal constraints here.
            // the transaction class pick a random size between 1 and 10 as per 'constraint arr_size'.
            // also, the PADDR.SIZE will be equal to PWDATA.SEIZE. 
            if(!trans.randomize() with { 
                PWRITE  == 1; 
                PRESETn == 1; 
            }) `uvm_fatal(get_name(), "Randomization Failed during Traffic Phase")
            `uvm_info(get_name(), trans.convert2string(), UVM_MEDIUM)
            `uvm_info(get_name(), $sformatf(" Write Burst Address with Size: %0d, Burst DATA with size : %0d ", trans.PADDR.size(), trans.PWDATA.size()), UVM_HIGH)
            
            finish_item(trans);
        end

        `uvm_info(get_name(), "----------------------", UVM_LOW)
        `uvm_info(get_name(), "Seq Done: apb_write_seq", UVM_LOW)
        `uvm_info(get_name(), "--------------------", UVM_LOW)
    endtask
endclass

///////////////////////////////////////
///   apb_read_only_sequence
//////////////////////////////////////

class apb_read_seq extends rnd_sequence;
    `uvm_object_utils(apb_read_seq)

    function new(string name="apb_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info(get_name(), "------------------------", UVM_LOW)
        `uvm_info(get_name(), "seq start: apb_read_seq", UVM_LOW)
        `uvm_info(get_name(), "------------------------", UVM_LOW)

                //  SYSTEM RESET
        reset_dut();
   
        // random read data
        `uvm_info(get_name(), " Starting Random Read Bursts", UVM_MEDIUM)
        
        repeat(no_of_testcases) begin

            start_item(trans);
            // Randomize: force PWRITE == 0
            // PADDR is random here 
            if(!trans.randomize() with { 
                PRESETn == 1; 
                PWRITE  == 0; 
            }) `uvm_fatal(get_name(), "Read Randomization Failed")
            `uvm_info(get_name(), trans.convert2string(), UVM_MEDIUM)
            `uvm_info(get_name(), $sformatf("Driving READ Burst to Addr %0h", trans.PADDR[0]), UVM_HIGH)
            
            finish_item(trans);
        end
        
        `uvm_info(get_name(), "----------------------------------", UVM_LOW)
        `uvm_info(get_name(), "seq completed: apb_read_seq finish", UVM_LOW)
        `uvm_info(get_name(), "---------------------------------", UVM_LOW)
    endtask

endclass

/////////////////////////////////////////
////////////  simultaneous read / write sequence for  ONLY 1 LOCATION /////
////////////////////////////////////////

class apb_write_read_seq extends rnd_sequence;
    `uvm_object_utils(apb_write_read_seq)

    // send a RESET ,, PRESETn = 0, 
    // loops through no_of_testcases,
    // randomize the writing to a memory and reading from the memory

    function new(string name="apb_write_read_seq");
        super.new(name);
    endfunction

    bit [31:0] saved_addr;
    bit [31:0] saved_data;

    virtual task body();
    `uvm_info(get_name(), "---------------------------------------", UVM_LOW)
    `uvm_info(get_name(), "seq start: Directed read after write on same location", UVM_LOW)
    `uvm_info(get_name(), "---------------------------------------", UVM_LOW)



    // Directed traffic (Write then -> Read then -> Compare)

    `uvm_info(get_name(), "Starting Directed Read After write", UVM_MEDIUM)
    
    repeat(no_of_testcases) begin
        
        
        // Reset9
        reset_dut();

        // Write to a Random addresses
        start_item(trans);
        if(!trans.randomize() with { 
            PRESETn == 1; 
            PWRITE  == 1;       // Force WRITE
            PADDR.size() == 1;  // Keep it simple (Single Transfer)
        }) `uvm_fatal(get_name(), "Write Randomization Failed")
        
        // Capture the address and data we just decided to write
        saved_addr = trans.PADDR[0];
        saved_data = trans.PWDATA[0];
        
        finish_item(trans);
        
        `uvm_info(get_name(), $sformatf("Wrote : 0x%0h to Address 0x%0h", saved_data, saved_addr), UVM_HIGH)

        // Read from the same location

        start_item(trans);
        if(!trans.randomize() with { 
            PRESETn == 1; 
            PWRITE  == 0;               // Force READ
            PADDR.size() == 1;          // Single Transfer
            PADDR[0] == saved_addr;
        }) `uvm_fatal(get_name(), "Read Randomization Failed")
        
        finish_item(trans);

        `uvm_info(get_name(), $sformatf("Read from the address 0x%0h (Expecting 0x%0h)", saved_addr, saved_data), UVM_HIGH)
    end
    
    `uvm_info(get_name(), "----------------------------", UVM_LOW)
    `uvm_info(get_name(), "Seq done: Directed test done", UVM_LOW)
    `uvm_info(get_name(), "------------------------", UVM_LOW)
endtask
endclass

///////////////////////////////////////////////
///// write and read from multiple locations /////
///////////////////////////////////////////////


class apb_random_write_read_seq extends rnd_sequence;
    `uvm_object_utils(apb_random_write_read_seq)

    // send a RESET ,, PRESETn = 0, 
    // loops through no_of_testcases,
    // randomize the writing to a memory and reading from the memory

    function new(string name="apb_random_write_read_seq");
        super.new(name);
    endfunction

    logic [31:0] captured_addr []; // array to hold generated write addresses
    // logic [31:0] captured_data [];

    virtual task body();
            `uvm_info(get_name(), "---------------------------------------", UVM_LOW)
            `uvm_info(get_name(), "seq start: random write and read sequence", UVM_LOW)
            `uvm_info(get_name(), "---------------------------------------", UVM_LOW)

            // Reset
            reset_dut();

            // Directed traffic (Write then -> Read then -> Compare)

            `uvm_info(get_name(), "Starting random Read After write", UVM_MEDIUM)
            
            repeat(no_of_testcases) begin

                // Write to a Random addresses as defined by the randomized address values

                start_item(trans);
                if(!trans.randomize() with { 
                    PRESETn == 1; 
                    PWRITE  == 1;       // Force to WRITE
                }) `uvm_fatal(get_name(), "Write Randomization Failed")
                `uvm_info(get_name(), trans.convert2string(), UVM_MEDIUM)
                `uvm_info(get_name(), $sformatf(" Write Burst Address with Size: %0d, Burst DATA with size : %0d ", trans.PADDR.size(), trans.PWDATA.size()), UVM_HIGH)

                captured_addr = trans.PADDR;
                // captured_data = trans.PWDATA;
                finish_item(trans);

                // wait for sometime in middle
                if (intf != null) begin
                    repeat(5) @(posedge intf.clk);
                end
                else begin
                    #20; // just in case the interface is null at the time.
                end

                /// read from saved addresses

                start_item(trans);
                if(!trans.randomize() with { 
                    PRESETn == 1; 
                    PWRITE  == 0;               // Force to READ

                    PADDR.size() == captured_addr.size();
                    foreach(PADDR[i]) {
                        PADDR[i] == captured_addr[i];
                    }
                }) `uvm_fatal(get_name(), "Read Randomization Failed")
                
                finish_item(trans);

            end
        
        `uvm_info(get_name(), "----------------------------", UVM_LOW)
        `uvm_info(get_name(), "Seq done: random write and read sequence", UVM_LOW)
        `uvm_info(get_name(), "------------------------", UVM_LOW)
endtask
endclass


///////////////////////////////////////
//////////// invalid and valid addresses mixed and random write/read action /////////////
///////////////////////////////////////	


class apb_val_inval_addr extends rnd_sequence;

    `uvm_object_utils(apb_val_inval_addr)

    //cons
    function new(string name = "apb_val_inval_addr");
        super.new(name);
    endfunction

    int min_valid = 0;
    int max_valid = 'h1f;
    
    virtual task body();
        `uvm_info(get_name(), "--------------------------", UVM_LOW)
        `uvm_info(get_name(), "Seq statr: apb_val_inval_addr", UVM_LOW)
        `uvm_info(get_name(), "-----------------------------", UVM_LOW)

        // reset
        reset_dut();

        `uvm_info(get_name(), " Starting valid invalid addresses write and read", UVM_MEDIUM)

        repeat(no_of_testcases) begin
            start_item(trans);
            if(!trans.randomize() with {
                PRESETn == 1;
                // PWRITE  == 1;  // commenting this out to create a random write read transaction

                // set a boundary for minimum n maximum values of PADDR
                // create a condition here to keep the genrated address value greater than maxvalid value but less than the maxlimit according to bus address
                foreach (PADDR[i]) {
                    PADDR[i] dist {
                        [min_valid : max_valid] := 50,
                        [max_valid+1 : 32'hffffffff] := 50
                    };
                }
                
                // Constrain Data Elements
                foreach(PWDATA[i]) {
                    PWDATA[i] inside {[0:32'hFFFF_FFFF]};
                }

                PWRITE dist {
                    1:= 40,
                    0:= 60
                };
            }) begin
                `uvm_fatal(get_name(),"Randomization failed")
            end

            // for debug to see twhat is being sent
            if (trans.PADDR[0] > max_valid)
                `uvm_info(get_name(), $sformatf("Driving INVALID Address: 0x%0p", trans.PADDR), UVM_NONE)
            else
                `uvm_info(get_name(), $sformatf("Driving VALID Address: 0x%0p", trans.PADDR), UVM_NONE)

            finish_item(trans);
        end

        `uvm_info(get_name(), "--------------------------", UVM_LOW)
        `uvm_info(get_name(), "Seq end: apb_val_inval_addr", UVM_LOW)
        `uvm_info(get_name(), "-----------------------------", UVM_LOW)

    endtask

endclass


////////////////////////
///// invalid write data (aka noise) /////////////
//////////////////////


class apb_noise_data_seq extends rnd_sequence;

    `uvm_object_utils(apb_noise_data_seq)

    function new(string name = "apb_noise_data_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        `uvm_info(get_name(), "Starting Data Noise Sequence (X/Z Injection)", UVM_MEDIUM)

        // reset
        reset_dut();

        repeat(no_of_testcases) begin
            start_item(trans);
            

            if(!trans.randomize() with {
                PRESETn == 1;
                PWRITE  == 1; // only writing
                
                // fixing burst size here (although a constraint is already in place for this, but yeah why not add some here)
                PADDR.size() inside {[1:5]};
                // PWDATA.size() == PADDR.size();
                
                // Keep addresses valid for this test to focus purely on Data
                foreach(PADDR[i]) PADDR[i] inside {[0:'h1F]}; 
            }) begin
                `uvm_fatal(get_name(), "Randomization failed")
            end

            // 2. The Corruption Logic (Post-Randomization)
            // We iterate through the data and randomly inject X or Z
            foreach(trans.PWDATA[i]) begin
                int prob_chance = $urandom_range(0, 99); // 0 to 99
                
                if (prob_chance < 10) begin
                    // 10% Chance -- give input as "X"
                    trans.PWDATA[i] = 32'bx;
                    `uvm_info(get_name(), $sformatf("Injecting 'X' at index: %0d", i), UVM_HIGH)
                end 
                else if (prob_chance < 20) begin
                    // 10% Chance -- give input as "Z"
                    trans.PWDATA[i] = 32'bz;
                    `uvm_info(get_name(), $sformatf("Injecting 'Z' at index: %0d", i), UVM_HIGH)
                end
                // rest, let them stay valid
            end

            finish_item(trans);
        end
        
        `uvm_info(get_name(), "Finished Data Noise Sequence", UVM_MEDIUM)

    endtask
endclass

///////////////////////////////////////
//////////// RACE CONDITION /////////////
///////////////////////////////////////	

class apb_race_hazard extends rnd_sequence;

    `uvm_object_utils(apb_race_hazard)

    logic [31:0] captured_addr []; // array to hold generated write addresses
    // logic [31:0] captured_data [];   /// array to hold 

    //cons
    function new(string name = "apb_race_hazard");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info(get_name(),"Starting Race hazard: Immediate read after some write",UVM_NONE);

        reset_dut();

        repeat (no_of_testcases) begin
            // write to the memory
            start_item(trans);
            if(!trans.randomize() with {
                PRESETn == 1;
                PWRITE == 1;
                PADDR.size() inside {[1:5]}; // constraint just for observability
            }) begin
            `uvm_error(get_name(),"Write randomization failed");
            end

            captured_addr = trans.PADDR;
            finish_item(trans);

            // no wait, directly read from the memory
            start_item(trans);
            if(!trans.randomize() with {
                PRESETn == 1;
                PWRITE == 0;
                
                PADDR.size() == captured_addr.size();
                foreach(PADDR[i]) {
                PADDR[i] == captured_addr[i]; 
                }
                
            }) begin
                `uvm_error(get_name(),"Read randomization failed");
            end 
            finish_item(trans);
 
        end
        
    `uvm_info(get_name(), "Finished race hazard Sequence", UVM_MEDIUM)

    endtask

endclass

///////////////////////////////////////
//////////// MY DRIVER /////////////
///////////////////////////////////////	

class driver extends uvm_driver#(transaction);
    `uvm_component_utils(driver)
    
    //  Group: Variables
    transaction trans_drv;
    // driver interface point to make the signals enter the DUT
    virtual APB_intf drv_intf;
    int i;
    // event DRV_DONE;

    //  Constructor: new
    function new(string name, uvm_component parent);
        super.new(name, parent);
        `uvm_info("DRV","this got executed",UVM_NONE);
    endfunction

    //  Function: build_phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("DRV","Driver build phase got executed",UVM_NONE);
        if(!uvm_config_db#(virtual APB_intf)::get(this, "*", "intf", drv_intf))
        // if(!uvm_config_db#(virtual APB_intf.DRV)::get(this, "*", "intf", drv_intf))
        `uvm_fatal(get_name(), "DRIVER cant get interface")
    endfunction: build_phase

    task drive_transfer(int index);
        // SETUP PHASE
    
        drv_intf.drv_cb.PSEL1   <= 1;
        drv_intf.drv_cb.PENABLE <= 0;
        drv_intf.drv_cb.PWRITE  <= trans_drv.PWRITE;
        drv_intf.drv_cb.PADDR   <= trans_drv.PADDR[index];
        if (trans_drv.PWRITE)
            drv_intf.drv_cb.PWDATA <= trans_drv.PWDATA[index];
        
        // one clock cycle for Setup Phase to complete
        @(drv_intf.drv_cb);

        // ACCESS PHASE
        // no chaneg in PSEL value, and drive PENABLE high
        drv_intf.drv_cb.PENABLE <= 1;

        // Wait for PREADY , This will also handle the wait states.
        // wait at least one cycle as per protocol rules.
        @(drv_intf.drv_cb);
        while(drv_intf.drv_cb.PREADY === 0) begin
            @(drv_intf.drv_cb);
        end

        // IDLE
        // can Drop Select and Enable as txn is finished
        drv_intf.drv_cb.PSEL1   <= 0;
        drv_intf.drv_cb.PENABLE <= 0;
    endtask

    // drive task - Switches b/w different operating states
    task drive();
        if(!trans_drv.PRESETn) begin
            `uvm_info("DRV_RESET_GIVEN","Driver is given reset for to the system",UVM_NONE);
            @(drv_intf.drv_cb);
            
            drv_intf.drv_cb.PRESETn <= trans_drv.PRESETn;
            drv_intf.drv_cb.PSEL1   <= trans_drv.PSEL1;  
            drv_intf.drv_cb.PENABLE <= trans_drv.PENABLE;
            drv_intf.drv_cb.PWRITE  <= trans_drv.PWRITE; 
            drv_intf.drv_cb.PADDR   <= trans_drv.PADDR[0];   // give the value of index as 0
            drv_intf.drv_cb.PWDATA  <= trans_drv.PWDATA[0];  // give the value of index as 0

            // Wait for some cycles to let reset propagate
            repeat (4) @(drv_intf.drv_cb);
            
            // De-assert Reset
            drv_intf.drv_cb.PRESETn <= 1;
            
            `uvm_info("DRV", "Reset Released", UVM_NONE);
        end
        else begin
            `uvm_info("DRV_RESET_VALUE_CHECK",$sformatf("Value of reset in the design %0b",trans_drv.PRESETn),UVM_NONE);
            @(drv_intf.drv_cb);
            for(i=0; i<trans_drv.PADDR.size(); i++) begin
                drive_transfer(i);
            end
        end
        // idle();
    endtask    

    //  Function: run_phase
    task run_phase(uvm_phase phase);
    forever begin
        seq_item_port.get_next_item(trans_drv);
        drive();
        @(drv_intf.drv_cb);
        seq_item_port.item_done();
        `uvm_info("DRV",$sformatf("received item_done at time %0t",$realtime),UVM_NONE);
    end
    endtask: run_phase

    
endclass

///////////////////////////////////////
//////////// MY MONITOR ////////////////
///////////////////////////////////////	

class monitor extends uvm_monitor;
    `uvm_component_utils(monitor)
    
    // Components
    uvm_analysis_port#(transaction) ap;

    // Vares
    // virtual APB_intf.MON intf;
    virtual APB_intf intf;
    transaction trans;
    int ip_pntr, op_pntr;
    bit sampled;
    bit pck_complete;

    // Constructor: new
    function new(string name, uvm_component parent);
        super.new(name, parent);
      `uvm_info("MON","Monitor constructor got executed",UVM_NONE);
    endfunction //new()

    //  Function: build_phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("MON","Monitor build phase got executed",UVM_NONE);
        // if(!uvm_config_db#(virtual APB_intf.MON)::get(this, "*", "intf", intf))
        if(!uvm_config_db#(virtual APB_intf)::get(this, "*", "intf", intf))
        `uvm_fatal(get_name(), "Cant get interface") 
        ap = new("ap", this);
        trans = new("sam_trans");
    endfunction: build_phase
    
    //  Function: run_phase
    task run_phase(uvm_phase phase);
   

    forever begin
        fork
            begin    /// this block will not be finished until both are done.
                fork
                    ip_mon();
                    op_mon();                    
                join
            end
            begin   // just in case Reset comes in randomly, we would like to get out of the block.
                wait(intf.mon_cb.PRESETn == 0);
            end
        join_any
        
        disable fork;   // kill the threads which are slow.

        // If Reset is Active Low, discard current data 

        if(!intf.mon_cb.PRESETn) begin
             `uvm_info(get_name(), "Monitor detected RESET. Clearing internal state.", UVM_HIGH)
             trans = new("sam_trans"); 
             ip_pntr = 0;
             op_pntr = 0;
             pck_complete = 0;
             sampled = 0;
             
            //  wait(intf.mon_cb.PRESETn == 1);
        end

        // Only send if the packet is complete AND the bus has gone idle (PSEL=0), and DATA read happened with PRDATA coming out from DUT.
        // else if(pck_complete && !intf.mon_cb.PSEL1 && intf.mon_cb.PWRITE == 0 ) begin    // if we use this then it will accumulate the PADDR and PWDATA value for both read and write , while displaying for READ txn
        else if(pck_complete && !intf.mon_cb.PSEL1) begin
            `uvm_info(get_name(), $sformatf("Sampled Packet is: %s", trans.convert2string()), UVM_NONE)
            `uvm_info("MON_TEMP_VAL_TO_AP_DEBUG",$sformatf("This is data going into the analysis port %0p", trans.PRDATA),UVM_NONE)
                        
            ap.write(trans);
            
            // Prepare for next packet
            trans = new("sam_trans");
            ip_pntr = 0;
            op_pntr = 0;
            pck_complete = 0;
        end
    end
endtask: run_phase


    //   Method definitions

    task ip_mon();
        @(intf.mon_cb);  // synchronize the task with clock so that ip_mon and op_mon run together.
        // if(intf.mon_cb.PENABLE == 1 && intf.mon_cb.PRESETn == 1 && !sampled) begin
        if(intf.mon_cb.PENABLE == 1 && !sampled) begin
            trans.PWRITE    = intf.mon_cb.PWRITE;
            trans.PSEL1     = intf.mon_cb.PSEL1;
            trans.PRESETn   = intf.mon_cb.PRESETn;
            trans.increaseSize();
            trans.PADDR[ip_pntr]  = intf.mon_cb.PADDR;
            trans.PWDATA[ip_pntr] = intf.mon_cb.PWDATA;
	    `uvm_info("MON_INPUT_DATA_CAPTURE_TEMP_DEBUG", $sformatf("Input data captured by mon: Ptr=%0d |PADDR = %0p | Captured Data=%0h | PADDR Size=%0d ", ip_pntr, trans.PADDR, trans.PWDATA[ip_pntr], trans.PADDR.size()), UVM_NONE)
            ip_pntr++;
            sampled = 1;
        end
    //    if(intf.mon_cb.PENABLE == 0 && intf.mon_cb.PSEL1 == 0 ) sampled = 0;
	if(intf.mon_cb.PENABLE == 0) sampled = 0;
    endtask

    task op_mon();    // synchronize the task with clock so that ip_mon and op_mon run together.
        @(intf.mon_cb);
        if(intf.mon_cb.PREADY == 1 && intf.mon_cb.PENABLE == 1 && intf.mon_cb.PSEL1 == 1 && intf.mon_cb.PRESETn == 1) begin
        // if(intf.mon_cb.PREADY == 1 && intf.mon_cb.PENABLE == 1 ) begin         // commenting this one out to sample signals while above condition sets in
            trans.PREADY = intf.mon_cb.PREADY;
            trans.PSLVERR = intf.mon_cb.PSLVERR;
 	    `uvm_info("MON_TEMP_DEBUG",$sformatf("value op_ptr 0x%0h data coming out of dut PRDATA =  %0p",op_pntr,intf.mon_cb.PRDATA),UVM_NONE)
 	    if(trans.PRDATA.size() <= op_pntr) begin        // since I am running ip_mon and op_mon in under fork_join. Then it is happening that the PRDATA array size is 0 
                                                            // incase OP_MON ran first because increase_size() function did not execute.
                trans.PRDATA = new[op_pntr + 1] (trans.PRDATA);
            end            

	    if (intf.mon_cb.PWRITE == 0) begin
                trans.PRDATA[op_pntr]  = intf.mon_cb.PRDATA;
            end else begin
                trans.PRDATA[op_pntr] = 32'h0;
            end
            op_pntr++;
            pck_complete = 1;
        end 
    endtask


endclass
///////////////////////////////////////
//////////// MY REFERENCE MODEL ///////
///////////////////////////////////////	

class ref_model#(parameter DEPTH = 5) extends uvm_component;
    `uvm_component_utils(ref_model)

    const int ram_depth = 2**DEPTH;
    bit [31:0] ram_mem [];  // Memory for DEPTH defined
    

    // constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
        ram_mem = new[ram_depth];
        foreach(ram_mem[i]) ram_mem[i] = 32'hffffffff;       /// adding this here, because the ref_model's memory should be initialized to ffff_ffff. when the constructor runs. 
            `uvm_info("REF_MOD","ref_model execution, depth = 32, Memory Initialized to 0xffffffff",UVM_NONE);
        for(int k=0; k<5; k++) begin
            `uvm_info("REF_MOD_DEBUG", $sformatf("Index [%0d] = %h", k, ram_mem[k]), UVM_NONE)
        end
    endfunction

    // Function: get_ref_val()
    function transaction get_ref_val(transaction trans);

    /// convert byte address to word index
    bit [31:0] word_index;
    // logic [31:0] current_address;

        if(trans.PRESETn == 0) begin
            foreach (ram_mem[j]) ram_mem[j] = 32'hffffffff;
            trans.PSLVERR = 0;
            trans.PREADY = 0;
            `uvm_info("REF_MOD", "System Reset: Memory Cleared", UVM_LOW)
            return trans;
        end

        else if(trans.PRESETn == 1) begin
            for(int i=0; i<trans.PADDR.size(); i++) begin

                
                /// *******************indexes for FORK_JOIN (exlusively for race condition)*****************
                automatic int local_i = i;          // caputres 0,1,2,3 index changes as per i
                automatic bit [31:0] local_index = trans.PADDR[i] >> 2;      /// captures current address
                // ***************************************************************************************

                word_index = local_index; /// ignoring the last 2 bit values here given from the APB MASTER (convert byte addressing to word addressing so that no memory locatuons are left behind)
                

                // if(trans.PADDR[i] >= ram_depth) begin
                // check for word index if more than the memory size
                if(word_index >= ram_depth) begin
                    `uvm_info("REF_MOD", $sformatf("Invalid access Addr:0x%0h (Index:%0d) > Max:%0d", 
                                                    trans.PADDR[i], word_index, ram_depth),UVM_NONE)
                    trans.PSLVERR = 1;
                    // trans.PRDATA[i] = 32'hffffffff;   // this was earlier set to 32'd0. This was causing an issue as it was sending PRDATA value a 0. instead it should send the default memory values i.e. in this case is  32'hffff_ffff
                            `uvm_info("REF_MOD_DEBUG", "Returning the value for PRDATA fr invalid memory access", UVM_NONE)                   
                            trans.PREADY = 1;
                        // adding this so that the ref_model can understand that for PWRITE = 1, read data = 0 (nothing will be read) || for PWRITE = 0 , read data = ffff_ffff (Invalid address as input hence, invalid data as output)
                        if (trans.PWRITE == 1) begin
                            trans.PRDATA[i] = 32'b0;      // Write = Quiet Bus
                        end else begin
                            trans.PRDATA[i] = 32'hffffffff; // Read = Garbage Data
                        end
                    continue;
                end
    
                if(trans.PWRITE == 1) begin
                    // bad data written , for actual hardware -- turn PSLVERR as 1
                    // but for  simulating here we need to pass the value to rf model
                    if(trans.PWDATA[i] === 32'hx || trans.PWDATA[i] === 32'hz ) begin
                        `uvm_info("REF_MOD", $sformatf("bad data write: Addr:%0h Data:%0h", trans.PADDR[i], trans.PWDATA[i]),UVM_NONE)
                        `uvm_info("REF_MOD", $sformatf("Writing 'X' or 'Z' to memory. Addr:%0h", trans.PADDR[i]), UVM_NONE)
                        // trans.PRDATA[i] = 32'b0;
                        ram_mem[word_index] = trans.PWDATA[i];
                        trans.PREADY = 1;
                        // trans.PSLVERR = 1;
                        trans.PSLVERR = 0;   // Since, DUT will not mark it as error as it cannot recognize X or Z
                        // continue;
                    end
                    // write full 32 bit data in the memory location calculated
                    
                    // ***********************INSTANT MEMORY UPDATE *****************************
                    // ram_mem [word_index] = trans.PWDATA[i];
                    //********************************************************************

                    //********************DELAYED MEMORY UPDATE*************************
                    // delayed update to the internal memory (RACE CONDITION CREATION)
			        // fork join_none here-- creates a parallel schedule  to run. Mmeroy update is going to update later but the output has been generated immediately (PRDATA, PREADY, PSLVERR)

                    // fork
                    //     begin
                    //         foreach (trans.PWDATA[local_i]) begin
                    //             `uvm_info("REF_RACE_DEBUG", "Delayed Ref_model Memory Update start", UVM_NONE)
                    //             `uvm_info("REF_RACE_DEBUG",$sformatf("value of word_index BEFORE #0: %0h || value of trans.PWDATA[%0d] : %0p",local_index,local_i,trans.PWDATA[local_i]),UVM_NONE)
                    //             current_address = trans.PADDR[local_i];
                    //             #0; // The delay that will cause the race. can use #1 to make delay more obvious but lets try with this first.
                    //             // ram_mem[word_index] = trans.PWDATA[i]; 
                    //             ram_mem[local_index] = trans.PWDATA[local_i]; 
                    //             `uvm_info("REF_RACE_DEBUG",$sformatf("value of word_index AFTER #0: %0h || value of trans.PWDATA[%0d] : %0p, || ram_mem[word_index] : %0p",local_index,local_i,trans.PWDATA[local_i],ram_mem[local_index]),UVM_NONE)
                    //             `uvm_info("REF_RACE_DEBUG", "Delayed Memory Update Complete", UVM_NONE)                                
                    //         end

                    //     end
                    // join_none
                    //********************************************************************
                    /// ******************* moving the DELAYED MEMORY UPDATE BLOCK OUTSIDE OF THE LOOP***************
                    // So that I can run it just for 1 repetition, here it is doig multiple reps (bcz of for_loop)

                    trans.PRDATA[i] = 32'b0;
                    trans.PREADY = 1;
                    trans.PSLVERR = 0;
                    `uvm_info("REF_MOD", $sformatf("WRITE | input Bus Addr: %0h -> actual Mem Index in hex: [%0h] | Data Stored: %0h", 
                                                    trans.PADDR[i], word_index, trans.PWDATA[i]), UVM_MEDIUM)
                end
                else begin
                    if(ram_mem[word_index] == 32'hffffffff) begin
                        /// reading uninitialized memory location is valid in APB, will receive GARBAGE though
                        `uvm_warning("REF_MOD", $sformatf("Improper data READ | Bus Addr: %0h -> Mem Index in hex: [%0h] | Returning Garbage", 
                                                           trans.PADDR[i], word_index)) 
                        trans.PRDATA[i] = 32'hffffffff;
                        trans.PREADY = 1;
                        trans.PSLVERR = 0;
                        continue;
                    end
                    trans.PRDATA[i] = ram_mem [word_index];
                    trans.PREADY = 1;
                    trans.PSLVERR = 0;
                    `uvm_info("REF_MOD", $sformatf("Correct READ | Bus Addr: %0h -> Mem Index in hex: [%0h] | Data Read in hex: %0h", 
                                                    trans.PADDR[i], word_index, trans.PRDATA[i]), UVM_MEDIUM)
                end
            end


             //  ******* moved delayed memory update out of the loop******
            if (trans.PWRITE == 1) begin
            
                automatic logic [31:0] captured_pwdata[] = trans.PWDATA;
                automatic logic [31:0] captured_paddr[]  = trans.PADDR;
    
                fork
                    begin
                        
                        `uvm_info("REF_RACE_DEBUG", "Delayed Memory Update Sequence STARTED", UVM_NONE)
                        
                        // Loop through the CAPTURED copies
                        foreach (captured_pwdata[k]) begin
                            // gets a fresh 'local_addr' for every single loop iteration.
                            automatic int        iter_k     = k; 
                            automatic logic [31:0] local_addr = captured_paddr[k];
                            automatic logic [31:0] local_data = captured_pwdata[k];
                            automatic bit [31:0]   local_idx  = local_addr >> 2; 
    
                           
                            if (local_idx < ram_depth) begin
                                
                                
                                 #0; 
                                 
                                // just to be sure I m not outisde the reset block or if asynchronous reset arrives in midway, need to exit
                                 if (trans.PRESETn == 0) begin
                                     `uvm_info("REF_RACE_DEBUG", "Write aborted due to Reset", UVM_HIGH)
                                     break; 
                                 end
    
                                 ram_mem[local_idx] = local_data;
                                 
                                 `uvm_info("REF_RACE_DEBUG", $sformatf("Memory Updated: Index %0d (Addr %0h) = %0h", 
                                           iter_k, local_addr, local_data), UVM_NONE)
                            end
                        end
                        `uvm_info("REF_RACE_DEBUG", "Delayed Memory Update Sequence COMPLETED", UVM_NONE)
                    end
                join_none
            end

            return trans;
        end
        
    endfunction

endclass

///////////////////////////////////////
//////////// MY SCOREBOARD ////////////
///////////////////////////////////////	


class scoreboard extends uvm_scoreboard;
    `uvm_component_utils(scoreboard)

    ref_model rm;
    uvm_analysis_imp#(transaction, scoreboard) ap_exp;

    transaction act_trans, exp_trans;
    int passCnt, failCnt;
    
    // constrctr
    function new(string name, uvm_component parent);
        super.new(name, parent);
        `uvm_info("SCB","scoreboard constructor got executed",UVM_NONE);
    endfunction

    //  build_phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rm = ref_model#()::type_id::create("rm", this);
        act_trans = new("act_trans");
        ap_exp = new("ap_exp", this);
        `uvm_info("SCB","scoreboard build_phase block got executed",UVM_NONE);
    endfunction: build_phase


    // Function - check()
    function void check();
        // only chek for flags, PSLVERR
        // WRITE (Check Error Status Only)
         if (act_trans.PWRITE == 1) begin
            if(act_trans.PSLVERR !== exp_trans.PSLVERR) begin
                `uvm_error("SCB", $sformatf("WRITE MISMATCH! Addr:0x%0h | ExpErr:%b ActErr:%b", act_trans.PADDR[0], exp_trans.PSLVERR, act_trans.PSLVERR))
                failCnt++;
            end
            else if(act_trans.PSLVERR == 0) begin   // Normal Successful Write (No Error)
                    `uvm_info("SCB", $sformatf("WRITE PASSED (Data Stored) | Addr:0x%0h",act_trans.PADDR[0]), UVM_NONE)
                    passCnt++;
                end
            else begin   // successful write operation but invalid address hence write is blocked
                `uvm_info("SCB", $sformatf("WRITE BLOCKED (Expected) | Addr:0x%0h | Cannot write to undefined memory",act_trans.PADDR[0]), UVM_NONE)
                passCnt++;
            end
        end
        // READ (Check Data and error status)
        else if(act_trans.PWRITE == 0) begin
            if(act_trans.compare(exp_trans)) begin
                `uvm_info("SCB", $sformatf("READ PASSED  | Addr:0x%0p | Actual data: 0x%0p | expected data: 0x%0p Data Match", act_trans.PADDR,act_trans.PRDATA, exp_trans.PRDATA), UVM_NONE)
                passCnt++;
            end
            else begin
                `uvm_error("SCB",$sformatf("READ MISMATCH! Addr:0x%0h \nExpected: %s \nActual: %s", act_trans.PADDR[0], exp_trans.convert2string(), act_trans.convert2string()))
                failCnt++;
            end
        end
    endfunction

    // Func - write
    virtual function void write(transaction trans);
       
        // Reset -> active low || PSEL1 =0 , do not check now as it is either in reset or PSEL = 0(Invalid txn)
        // if (trans.PRESETn == 0 || trans.PSEL1 == 0) begin

        // adding this here so that Empty packets can be ignore for testing
        if(trans.PADDR.size() == 0) begin
            `uvm_info("SCB","Incoming packet is empty, SKIPPING",UVM_NONE)
            return;
        end

        // added this for extra safety where PRESETn and PSEL1 are not equal to one, they maybe 0,X,Z
        if (trans.PRESETn == 0 || trans.PSEL1 == 0) begin
            `uvm_info("SCB", "Skipping Scoreboard check now since, the DUT is in Reset OROR ignor now since PSEL = 0, no txn", UVM_NONE)
            return;
        end

        // go ahead with check
        if(trans.PADDR.size() != 0) begin
            act_trans.copy(trans);     // copy the value of transactions
		//`uvm_info("SCB_TEMP_DEBUG",$sformatf("Value of PRDATA array: 0x%0p and size of PRDATA array: 0x%0d",act_trans.PRDATA,act_trans.PRDATA.size()),UVM_NONE)
            exp_trans = rm.get_ref_val(trans);
`uvm_info("SCB_TEMP_DEBUG", $sformatf("value of actual PRDATA array : 0x%0p and expected PRDATA ARRAY : 0x%0p || and size of PRDATA array: 0x%0d",act_trans.PRDATA,exp_trans.PRDATA,act_trans.PRDATA.size()),UVM_NONE)
            check();            
        end

    endfunction

endclass

///////////////////////////////////////
//////////// MY AGENT  ////////////////
///////////////////////////////////////

class agent extends uvm_agent;
    `uvm_component_utils(agent)
    
    //  Group: Components
    driver drv;
    monitor mon;
    uvm_sequencer#(transaction) seqr;
    fun_cov fc;
    
    // analysis port 
    uvm_analysis_port#(transaction) ap;

    //  Group: Variables
    rnd_sequence seq;
    agent_config agnt_cfg;
	
    //  Constructor: new
    function new(string name, uvm_component parent);
        super.new(name, parent);
        `uvm_info("agent","agent constructor block got executed",UVM_NONE);
    endfunction

    //  Function: build_phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("agent","agent build phase block got executed",UVM_NONE);

        if(!uvm_config_db#(agent_config)::get(this, "*", "agnt_cfg", agnt_cfg))
        `uvm_fatal(get_name(), "agnt_cfg cannot be found in ConfigDB!")

        mon = monitor::type_id::create("mon", this);
        fc = fun_cov::type_id::create("fc", this);

        // make driver and sequencer instance only when active = UVM_ACTIVE
        if(agnt_cfg.active) begin
            drv = driver::type_id::create("drv", this);
            seqr = uvm_sequencer#(transaction)::type_id::create("seqr", this);
        end

    endfunction: build_phase
    
    //  Function: connect_phase
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // connect the virtual interface with the monitor interface
        mon.intf = agnt_cfg.intf;
        // connect the monitor analysis port with the agent analysis port
        ap = mon.ap;
        `uvm_info("agent","agent connect phase block got executed",UVM_NONE);


        // connect only when active in agnt_cnfg.active = UVM_ACTIVE
        if(agnt_cfg.active) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
            drv.drv_intf = agnt_cfg.intf;
        end

        mon.ap.connect(fc.analysis_export);

    endfunction : connect_phase
    
endclass

///////////////////////////////////////
//////////// MY ENVIRONMENT  ////////////////
///////////////////////////////////////

class environment extends uvm_env;
    `uvm_component_utils(environment)

    // Components
    agent agnt;
    scoreboard scb;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
        `uvm_info("env","env constructor block got executed",UVM_NONE);
    endfunction //new()

    virtual function void build_phase(uvm_phase phase);
        agnt = agent::type_id::create("agnt", this);
        scb = scoreboard::type_id::create("scb", this);
        `uvm_info("env","env build phase block got executed",UVM_NONE);
    endfunction: build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // connect the agent port to scoreboard port
        agnt.ap.connect(scb.ap_exp);
        `uvm_info("env","env connect phase block got executed",UVM_NONE);
    endfunction: connect_phase
    
    
endclass

////////////////////////////////
//////////// MY TEST  //////////
////////////////////////////////

class base_test extends uvm_test;
    `uvm_component_utils(base_test)
    
    // Components
    environment env;

    // Variables
    // rnd_sequence seq;
    agent_config agnt_cfg;

    // Constructor: new
    function new(string name, uvm_component parent);
        super.new(name, parent);
        `uvm_info("base test","base test constructor block got executed",UVM_NONE);
    endfunction //new()

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agnt_cfg = new("agnt_cfg");
        `uvm_info("base test","base test build phase block got executed",UVM_NONE);
        if(!uvm_config_db#(virtual APB_intf)::get(this, "*", "intf", agnt_cfg.intf))
        `uvm_fatal(get_name(), "intf cannot be found in ConfigDB!")

        // setting here a handle so that classes inside agent can access the agent_config block from here.
        uvm_config_db#(agent_config)::set(this, "env.agnt.*", "agnt_cfg", agnt_cfg);
        /// set the number of cases for the design from the base_test
        uvm_config_db#(int)::set(null, "seq.*", "no_cases", 10);
        
        // seq = new();
        env = environment::type_id::create("env", this);
    endfunction: build_phase

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction: end_of_elaboration_phase
    
    // commenting out the run phase from here and will put in specific cases below
    // task run_phase(uvm_phase phase);
    //     phase.raise_objection(this);
    //     seq.start(env.agnt.seqr);
    //     #100;
    //     phase.drop_objection(this);
    // endtask: run_phase
    
endclass

class apb_write_test extends base_test;
    `uvm_component_utils(apb_write_test)

    apb_write_seq w_seq; 

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        w_seq = apb_write_seq::type_id::create("w_seq");
        w_seq.start(env.agnt.seqr); // Start the READ sequence
        
        phase.drop_objection(this);
    endtask
endclass


class apb_read_test extends base_test;
    `uvm_component_utils(apb_read_test)

    apb_read_seq r_seq; 

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        r_seq = apb_read_seq::type_id::create("r_seq");
        r_seq.start(env.agnt.seqr); // Start the READ sequence
        
        phase.drop_objection(this);
    endtask
endclass



class apb_comprehensive_test extends base_test;
    `uvm_component_utils(apb_comprehensive_test)

    apb_write_read_seq rw_seq;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        rw_seq = apb_write_read_seq::type_id::create("rw_seq");
        rw_seq.start(env.agnt.seqr); // Start the MIXED sequence
        
        phase.drop_objection(this);
    endtask
endclass

class apb_random_write_read_test extends base_test;
    `uvm_component_utils(apb_random_write_read_test)

    apb_random_write_read_seq rrw_seq;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        rrw_seq = apb_random_write_read_seq::type_id::create("rrw_seq");
        rrw_seq.start(env.agnt.seqr); 
        
        phase.drop_objection(this);
    endtask
endclass


class apb_val_inval_addr_test extends base_test;

    `uvm_component_utils(apb_val_inval_addr_test)

    apb_val_inval_addr invalid_seq;

    //cons
    function new(string name = "apb_val_inval_addr_test", uvm_component parent);
        super.new(name,parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        invalid_seq = apb_val_inval_addr::type_id::create("invalid_seq");
        invalid_seq.start(env.agnt.seqr);     // initiate the sequence
        phase.drop_objection(this);
    endtask

endclass


class apb_noise_data_seq_test extends base_test;

    `uvm_component_utils(apb_noise_data_seq_test)

    apb_noise_data_seq noise_seq;

    //cons
    function new(string name = "apb_noise_data_seq_test", uvm_component parent);
        super.new(name,parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        noise_seq = apb_noise_data_seq::type_id::create("noise_seq");
        noise_seq.start(env.agnt.seqr);     // initiate the sequence
        phase.drop_objection(this);
    endtask

endclass

class apb_race_hazard_test extends base_test;

    `uvm_component_utils(apb_race_hazard_test)

    apb_race_hazard race_seq;

    //cons
    function new(string name = "apb_race_hazard_test", uvm_component parent);
        super.new(name,parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        race_seq = apb_race_hazard::type_id::create("race_seq");
        race_seq.start(env.agnt.seqr);     // initiate the sequence
        phase.drop_objection(this);
    endtask

endclass

///////////////////////////////////////
//////////// MY TB TOP       //////////
///////////////////////////////////////


module full_tb;
    bit clk = 0;

    APB_intf intf(clk);

    /// connect the dut to interface signals
    apb_mem_NL dut(.PCLK(clk), .PRESETn(intf.PRESETn), .PSEL1(intf.PSEL1), .PWRITE(intf.PWRITE), 
                .PENABLE(intf.PENABLE), .PADDR(intf.PADDR), .PWDATA(intf.PWDATA),
                .PRDATA(intf.PRDATA), .PREADY(intf.PREADY), .PSLVERR(intf.PSLVERR));

    always #5 clk = ~clk;

    initial begin
        uvm_config_db#(virtual APB_intf)::set(null, "*", "intf", intf);
        // run_test("base_test");
        // run_test("apb_write_test");
        // run_test("apb_read_test");
        // run_test("apb_comprehensive_test");
        // run_test("apb_random_write_read_test");
    	// run_test("apb_val_inval_addr_test");
	    // run_test("apb_noise_data_seq_test");
	    run_test("apb_race_hazard_test");
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
        $assertvacuousoff(0);
      	
    end

endmodule

