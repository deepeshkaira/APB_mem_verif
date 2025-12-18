
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

    `uvm_object_utils(transaction);



    //  Vars  declration

    static bit [9:0] p_id;      // Packet id

    static bit [3:0] f_id;      // Feature id

    rand bit PWRITE;            // Read/Write

    rand bit[31:0] PWDATA [];  

    rand bit[31:0] PADDR [];  

    rand bit PRESETn;

   

    rand bit error_case;        // To generate random error case

    bit PSEL1;

    bit PENABLE;



    bit PREADY;

    bit [31:0] PRDATA [int];

    bit PSLVERR;



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

            PWDATA.size() inside {[1:20]};

            PADDR.size() inside {[1:20]};

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

            `uvm_info("COV",$sformatf("this is coverage sample number %0d",j),UVM_NONE);

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



    //  Constructor: new

    function new(string name = "rnd_seq");

        super.new(name);

        trans = transaction::type_id::create("trans");

        if(!uvm_config_db#(int)::get(null, "seq.", "no_cases", no_of_testcases)) begin

            `uvm_warning(get_name(), "Cant get no of testcases, Using default no of test cases = 10")

            // just in case there is an issue in recieving the number of testcases from config_db

            no_of_testcases = 10;

        end

    endfunction: new



    //  Task: pre_body

    //  This task is a user-definable callback that is called before the execution

    //  of <body> only when the sequence is started with <start>.

    //  If <start> is called with ~call_pre_post~ set to 0, ~pre_body~ is not called.

   

    virtual task pre_body();

        start_item(trans);

        trans.p_id = 1;

        trans.f_id = 5;

        trans.PRESETn = 0;

        trans.PADDR = {32'h0};

        trans.PWDATA = {32'h0};

        finish_item(trans);

    endtask



    //  Task: body

    //  This is the user-defined task where the main sequence code is written



    virtual task body();

        `uvm_info("rnd_sequence","rnd_sequence block got executed",UVM_NONE);

        for (int i = 0; i < no_of_testcases-1; i++) begin

            start_item(trans);

            // start the randomization and transactions.

            // asks the sequencer for permission to send the data

            if(!trans.randomize())

                `uvm_fatal(get_name(), "Randomization failed");

            // `uvm_info(get_name(), trans.convert2string(), UVM_MEDIUM)

           // `uvm_info("rnd_sequence","task body executed",UVM_NONE)

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

        `uvm_info(get_name(), "[PHASE 1] Asserting Reset", UVM_MEDIUM)

        start_item(trans);

        if(!trans.randomize() with {

            PRESETn == 0;

            }) `uvm_fatal(get_name(), "Randomization Failed during Reset Phase")

        finish_item(trans);





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





   

    // random read data

    `uvm_info(get_name(), " Starting Random Read Bursts", UVM_MEDIUM)

   

    repeat(no_of_testcases) begin



        //  SYSTEM RESET

        `uvm_info(get_name(), "asserting Reset", UVM_MEDIUM)

        start_item(trans);

        if(!trans.randomize() with { PRESETn == 0; })

            `uvm_fatal(get_name(), "Reset Randomization Failed")

        finish_item(trans);



        start_item(trans);

       

        // Randomize:

        // Force PWRITE == 0

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

////////////  simultaneous read / write sequence for 1 location /////

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

       

       

        // Reset



        `uvm_info(get_name(), "asserting Reset", UVM_MEDIUM)

        start_item(trans);

        if(!trans.randomize() with { PRESETn == 0; })

            `uvm_fatal(get_name(), "Reset Randomization Failed")

        finish_item(trans);



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



    bit [31:0] captured_addr []; // array to hold generated write addresses

    bit [31:0] captured_data [];



    virtual task body();

    `uvm_info(get_name(), "---------------------------------------", UVM_LOW)

    `uvm_info(get_name(), "seq start: random write and read sequence", UVM_LOW)

    `uvm_info(get_name(), "---------------------------------------", UVM_LOW)





    // Directed traffic (Write then -> Read then -> Compare)



    `uvm_info(get_name(), "Starting random Read After write", UVM_MEDIUM)

   

    repeat(no_of_testcases) begin

       

        // Reset



        `uvm_info(get_name(), "asserting Reset", UVM_MEDIUM)

        start_item(trans);

        if(!trans.randomize() with { trans.PRESETn == 0; })

            `uvm_fatal(get_name(), "Reset Randomization Failed")

        finish_item(trans);



        // Write to a Random addresses as defined by the randomized address values



        start_item(trans);

        if(!trans.randomize() with {

            trans.PRESETn == 0;

            trans.PWRITE  == 1;       // Force WRITE

        }) `uvm_fatal(get_name(), "Write Randomization Failed")

        `uvm_info(get_name(), trans.convert2string(), UVM_MEDIUM)

        `uvm_info(get_name(), $sformatf(" Write Burst Address with Size: %0d, Burst DATA with size : %0d ", trans.PADDR.size(), trans.PWDATA.size()), UVM_HIGH)



        captured_addr = trans.PADDR;

        captured_data = trans.PWDATA;

        finish_item(trans);



        /// read from saved addresses



        start_item(trans);

        if(!trans.randomize() with {

            PRESETn == 1;

            PWRITE  == 0;               // Force READ



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

        // 1. SETUP PHASE

   

        drv_intf.drv_cb.PSEL1   <= 1;

        drv_intf.drv_cb.PENABLE <= 0;

        drv_intf.drv_cb.PWRITE  <= trans_drv.PWRITE;

        drv_intf.drv_cb.PADDR   <= trans_drv.PADDR[index];

        if (trans_drv.PWRITE)

            drv_intf.drv_cb.PWDATA <= trans_drv.PWDATA[index];

       

        // one clock cycle for Setup Phase to complete

        @(drv_intf.drv_cb);



        // 2. ACCESS PHASE

        // no chaneg in PSEL value, and drive PENABLE high

        drv_intf.drv_cb.PENABLE <= 1;



        // Wait for PREADY , This will also handle the wait states.

        // wait at least one cycle as per protocol rules.

        @(drv_intf.drv_cb);

        while(drv_intf.drv_cb.PREADY === 0) begin

            @(drv_intf.drv_cb);

        end



        // 3. IDLE

        // can Drop Select and Enable as txn is finished

        drv_intf.drv_cb.PSEL1   <= 0;

        drv_intf.drv_cb.PENABLE <= 0;

endtask



    // drive task - Switches b/w different operating states

    task drive();

        if(!trans_drv.PRESETn) begin

            `uvm_info("DRV_RESET_GIVEN","Driver is given reset for to the system",UVM_NONE);

            @(drv_intf.drv_cb);

           

            drv_intf.drv_cb.PRESETn <= 0;

            @(drv_intf.drv_cb);

            // #10;

            drv_intf.drv_cb.PRESETn <= 1;

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

            ip_mon();

            op_mon();

        join

        `uvm_info(get_name(), $sformatf("pck_complete: %b, PSEL1: %b", pck_complete, intf.mon_cb.PSEL1), UVM_HIGH)

        if((pck_complete && !intf.mon_cb.PSEL1) || !intf.mon_cb.PRESETn) begin

            `uvm_info(get_name(), $sformatf("Sampled Packet is: %s", trans.convert2string()), UVM_NONE)

            ap.write(trans);

            trans = new("sam_trans");

            ip_pntr = 0;

            op_pntr = 0;

            pck_complete = 0;

        end

    end

    endtask: run_phase



    //   Method definitionss



    task ip_mon();

        @(intf.mon_cb);

        if(intf.mon_cb.PENABLE == 1 && !sampled) begin

            trans.PWRITE    = intf.mon_cb.PWRITE;

            trans.PSEL1     = intf.mon_cb.PSEL1;

            trans.PRESETn   = intf.mon_cb.PRESETn;

            trans.increaseSize();

            trans.PADDR[ip_pntr]  = intf.mon_cb.PADDR;

            trans.PWDATA[ip_pntr] = intf.mon_cb.PWDATA;

            ip_pntr++;

            sampled = 1;

        end

        if(intf.mon_cb.PENABLE == 0) sampled = 0;

    endtask



    task op_mon();

        @(intf.mon_cb);

        if(intf.mon_cb.PREADY == 1 && intf.mon_cb.PENABLE == 1) begin

            trans.PREADY = intf.mon_cb.PREADY;

            trans.PSLVERR = intf.mon_cb.PSLVERR;

            trans.PRDATA[op_pntr]  = intf.mon_cb.PRDATA;

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

        `uvm_info("REF_MOD","ref_model execution, depth = 32",UVM_NONE);

    endfunction



    // Function: get_ref_val()

    function transaction get_ref_val(transaction trans);



    /// convert byte address to word index

    bit [31:0] word_index;



        if(trans.PRESETn == 0) begin

            foreach (ram_mem[j]) ram_mem[j] = 32'hffffffff;

            trans.PSLVERR = 0;

            trans.PREADY = 0;

            `uvm_info("REF_MOD", "System Reset: Memory Cleared", UVM_LOW)

            return trans;

        end



        else if(trans.PRESETn == 1) begin

            for(int i=0; i<trans.PADDR.size(); i++) begin



                word_index = trans.PADDR[i] >> 2; /// ignoring the last 2 bit values here given from the APB MASTER (convert byte addressing to word addressing so that no memory locatuons are left behind)

   

                // if(trans.PADDR[i] >= ram_depth) begin

                // check for word index if more than the memory size

                if(word_index >= ram_depth) begin

                    `uvm_error("REF_MOD", $sformatf("Invalid access Addr:0x%0h (Index:%0d) > Max:%0d",

                                                    trans.PADDR[i], word_index, ram_depth))

                    trans.PSLVERR = 1;

                    trans.PRDATA[i] = 32'b0;

                    trans.PREADY = 1;

                    continue;

                end

   

                if(trans.PWRITE == 1) begin

                    // bad data written , turn PSLVERR as 1

                    if(trans.PWDATA[i] === 32'hx || trans.PWDATA[i] === 32'hz ) begin

                        `uvm_error("REF_MOD", $sformatf("bad data write: Addr:%0h Data:%0h", trans.PADDR[i], trans.PWDATA[i]))

                        trans.PRDATA[i] = 32'b0;

                        trans.PREADY = 1;

                        trans.PSLVERR = 1;

                        continue;

                    end

                    // else write full 32 bit data in the memory location calculated

                    ram_mem [word_index] = trans.PWDATA[i];

                    trans.PRDATA[i] = 32'b0;

                    trans.PREADY = 1;

                    trans.PSLVERR = 0;

                    `uvm_info("REF_MOD", $sformatf("WRITE | input Bus Addr: %0h -> actual Mem Index in hex: [%0h] | Data Stored: %0h",

                                                    trans.PADDR[i], word_index, trans.PWDATA[i]), UVM_MEDIUM)

                end

                else begin

                    if(ram_mem[word_index] == 32'hffffffff) begin

                        /// reading uninitialized memory location is valid in APB, will receive GARBAGE though

                        `uvm_warning("REF_MOD", $sformatf("UNINIT READ | Bus Addr: %0h -> Mem Index in hex: [%0h] | Returning Garbage",

                                                           trans.PADDR[i], word_index))

                        trans.PRDATA[i] = 32'hffffffff;

                        trans.PREADY = 1;

                        trans.PSLVERR = 0;

                        continue;

                    end

                    trans.PRDATA[i] = ram_mem [word_index];

                    trans.PREADY = 1;

                    trans.PSLVERR = 0;

                    `uvm_info("REF_MOD", $sformatf("READ | Bus Addr: %0h -> Mem Index in hex: [%0h] | Data Read in hex: %0h",

                                                    trans.PADDR[i], word_index, trans.PRDATA[i]), UVM_MEDIUM)

                end

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

        if(act_trans.compare(exp_trans)) begin

            `uvm_info("SCB", $sformatf("%s\nStatus -> TEST___PASSED", act_trans.convert2string()), UVM_NONE)

            passCnt++;

            `uvm_info("SCB",$sformatf("pass count value : %0d",passCnt),UVM_NONE)

        end

        else begin

            `uvm_error("SCB", $sformatf("Actual Packet: %s\nExpected Packet: %s\nStatus -> TEST__FAILED",

                    act_trans.convert2string(), exp_trans.convert2string()))

            failCnt++;

            `uvm_info("SCB",$sformatf("fail count value : %0d",failCnt),UVM_NONE)

        end

    endfunction



    // Fuction - write

    virtual function void write(transaction trans)

       

        // Reset -> active low || PSEL1 =0 , do not check now as it is either in reset or PSEL = 0(Invalid txn)

        // if (trans.PRESETn == 0 || trans.PSEL1 == 0) begin



        // adding this here so that Empty packets can be ignore for testing

        if(trans.PADDR.size() == 0) begin

                `uvm_info("SCB","Incoming packet is empty, SKIPPING",UVM_NONE)

        end



        // added this for extra safety where PRESETn and PSEL1 are not equal to one, they maybe 0,X,Z

        if (!(trans.PRESETn == 0) || !(trans.PSEL1 == 0)) begin

            `uvm_info("SCB", "Skipping Scoreboard check now since, the DUT is in Reset OROR ignor now since PSEL = 0, no txn", UVM_NONE)

            return;

        end



        act_trans.copy(trans);

        exp_trans = rm.get_ref_val(trans);

        check();

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

        uvm_config_db#(int)::set(null, "seq.*", "no_cases", 1000);

       

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



    apb_random_write_read_seq rw_seq;



    function new(string name, uvm_component parent);

        super.new(name, parent);

    endfunction



    task run_phase(uvm_phase phase);

        phase.raise_objection(this);

       

        rw_seq = apb_random_write_read_seq::type_id::create("rw_seq");

        rw_seq.start(env.agnt.seqr);

       

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

        run_test("apb_read_test");

    end



    initial begin

        $dumpfile("dump.vcd");

        $dumpvars;

        $assertvacuousoff(0);

        // #1350;

        // $finish();

    end



endmodule

