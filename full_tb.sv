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
        // at certain instance of time.
        clocking drv_cb @(posedge clk);
            output PWRITE, PWDATA, PADDR, PENABLE, PRESETn, PSEL1;
            input PREADY; 
        endclocking
       
        // this defines the input for the monitor block
        clocking mon_cb @(posedge clk);
            input PWRITE, PWDATA, PADDR, PENABLE, PRESETn, PSEL1; 
            input #1 PRDATA, PREADY, PSLVERR;   
        endclocking
    
        modport DRV (clocking drv_cb);
        modport MON (clocking mon_cb);

		//-------------------------- Assertions  -------------------------------

        // to check whether PENABLE is asserted 1 clk after PSEL1 is asserted
        property enable_ch;
            @(posedge clk) $rose(PSEL1) |=> PENABLE;
        endproperty

        // to check whether all signal are stable or not during the PENABLE assertion in the SETUP state
        // in the same clock cycle
        property stable_ch;
            @(posedge clk) $rose(PENABLE) |-> $stable(PADDR) ##0 $stable(PWDATA) ##0 $stable(PWRITE) ##0 $stable(PSEL1);
        endproperty

        // Property to check whether the PENABLE is deasserted 1 clk after PREADY signal is asserted
        property enable_deassert_ch;
            @(posedge clk) $fell(PENABLE) |-> s1;
        endproperty

        sequence s1;
            !($past(PENABLE, 2) && $past(PREADY, 2));
        endsequence
        
        // Property to check whether the PENABLE is deasserted without PREADY being asserted
        property enable_deassert_ch2;
            @(posedge clk) 
            if(!$isunknown(PENABLE))
                $fell(PENABLE) |-> $past(PREADY) == 1;
        endproperty
    
        // properties defined earlier are asserted here.
        assert property (enable_ch)
            `uvm_info("enable_ch", "ENABLE DRIVED 1 CYCLE AFTER PSEL1", UVM_DEBUG)
        else
            `uvm_error("enable_ch", "ENABLE NOT DRIVED 1 CYCLE AFTER PSEL1")

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
            PWDATA.size() inside {[1:3]}; 
            PADDR.size() inside {[1:3]};
        }
        PWDATA.size() == PADDR.size();
    }
    constraint reset_dist { PRESETn dist {0:=1, 1:=200}; }
    constraint sel_dist { PSEL1 dist {0:=10, 1:=90}; }
    constraint err_case_dist { error_case dist {1:=5, 0:=100}; } // Generates error test cases

    // Constraint for a specific memory size, can be commented for general use
    constraint paddr_val {
        !error_case -> 
            foreach(PADDR[i]) 
                PADDR[i] inside {[0:(2**5)-1]};
    }

    //  Group: Functions
    function void pre_randomize();
        p_id++;
    endfunction

    function void post_randomize();
        if(!PRESETn)
            f_id = 5;
        else if (PWRITE && PADDR.size() == 1)
            f_id = 1;
        else if (PWRITE && PADDR.size() > 1)
            f_id = 2;
        else if (!PWRITE && PADDR.size() == 1)
            f_id = 3;
        else if (!PWRITE && PADDR.size() > 1)
            f_id = 4;
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

    //  Constructor: new
    function new(string name = "transaction");
        super.new(name);
    endfunction: new

    /// functions , may use

    //  do_compare
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        transaction rhs_;

        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal({this.get_name(), ".do_compare()"}, "Cast failed!");
        end

        do_compare = super.do_compare(rhs, comparer);

        //  list of local props to be compared
        do_compare &= (
            this.PSLVERR == rhs_.PSLVERR &&
            this.PREADY == rhs_.PREADY
        );
        foreach ( PRDATA[i] ) begin
            do_compare &= (this.PRDATA[i] == rhs_.PRDATA[i]);
        end

    // return do_compare;
    endfunction: do_compare

    //  convert2string
    virtual function string convert2string();
        string s;
        s = super.convert2string();

        /*  list of local properties to be printed:  */
        s = {s, $sformatf("Packet ID: %0d, Feature ID: %0d\n", p_id, f_id)};
        s = {s, $sformatf("Input to DUT: PWRITE = %b, PRESETn = %b, PSEL1 = %b, PWDATA = %p, PADDR = %p\n", PWRITE, PRESETn, PSEL1, PWDATA, PADDR)};
        s = {s, $sformatf("OUPUT from DUT: PREADY = %b, PRDATA = %p, PSLVERR = %b", PREADY, PRDATA, PSLVERR)};

        return s;
    endfunction: convert2string
        
endclass: transaction


/////////////////////////////////
//////// FUNCTIONAL COVERAGE ////
/////////////////////////////////

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
        PADDR: coverpoint _tempPADDR { 
            bins paddr[] = {[0:32'h0000001f]}; 
            illegal_bins il_paddr = default;
        }
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
        PSEL1xPWRITE: cross PSEL1, PWRITE {
            ignore_bins ig_bins = binsof(PSEL1) intersect{0}; 
        }
        PSEL1xPWRITExPADDR: cross PSEL1, PWRITE, PADDR { 
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
        for(int j = 0; j < trans.PADDR.size(); j++) begin
            _tempRDATA = trans.PRDATA[j];
            _tempPWDATA = trans.PWDATA[j];
            _tempPADDR = trans.PADDR[j];
            apb_cg.sample();
            `uvm_info("COV",$sformatf("this is coverage sample number %0d",j),UVM_NONE);
        end
    endfunction

    // Constructor: new
    function new(string name, uvm_component parent);
        super.new(name, parent);
        apb_cg = new();
    endfunction //new()

    function void write(T t);
        trans = t;
        cov_sample();
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        trans = new("cov_trans");
    endfunction: build_phase
    
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
            no_of_testcases = 10;
        end
    endfunction: new

    //  Task: pre_body
    //  This task is a user-definable callback that is called before the execution 
    //  of <body> ~only~ when the sequence is started with <start>.
    //  If <start> is called with ~call_pre_post~ set to 0, ~pre_body~ is not called.
    // extern virtual task pre_body();
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
    //  This is the user-defined task where the main sequence code resides.
    // extern virtual task body();
    virtual task body();
        `uvm_info("rnd_sequence","rnd_sequence block got executed",UVM_NONE);
        for (int i = 0; i < no_of_testcases-1; i++) begin
            start_item(trans);
            if(!trans.randomize())
                `uvm_fatal(get_name(), "Randomization failed");
            `uvm_info(get_name(), trans.convert2string(), UVM_MEDIUM)
            
            finish_item(trans);
        end
    endtask: body
    
endclass: rnd_sequence


///////////////////////////////////////
//////////// MY DRIVER /////////////
///////////////////////////////////////	

class driver extends uvm_driver#(transaction);
    `uvm_component_utils(driver)
    
    //  Group: Variables
    transaction trans_drv;
    // virtual APB_intf.DRV drv_intf;
    virtual APB_intf drv_intf;
    int i;
    event DRV_DONE;
    
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

    //  Group: Functions
    // idle task - IDLE operating state
    task idle();
        drv_intf.drv_cb.PSEL1   <= 0;
        drv_intf.drv_cb.PENABLE <= 0;
    endtask //idle

    // setup task - SETUP operating state (Sets all the input for the slave)
    task setup();
        // #2;
        drv_intf.drv_cb.PSEL1   <= 1;
        drv_intf.drv_cb.PENABLE <= 0;
        drv_intf.drv_cb.PRESETn <= trans_drv.PRESETn;
        drv_intf.drv_cb.PWRITE  <= trans_drv.PWRITE;
        drv_intf.drv_cb.PWDATA  <= trans_drv.PWDATA[i];
        drv_intf.drv_cb.PADDR   <= trans_drv.PADDR[i];
    endtask

    // access task - ACCESS operating state
    task access();
        drv_intf.drv_cb.PSEL1   <= 1;
        drv_intf.drv_cb.PENABLE <= 1;
    endtask

    // drive task - Switches b/w different operating states
    task drive();
        if(!trans_drv.PRESETn) begin
            @(drv_intf.drv_cb);
            drv_intf.drv_cb.PRESETn <= trans_drv.PRESETn;
            #10;
            drv_intf.drv_cb.PRESETn <= 1;
        end
        else begin  
            @(drv_intf.drv_cb);
            for(i=0; i<trans_drv.PADDR.size(); i++) begin
                setup();
                @(drv_intf.drv_cb);
                access();
                wait(drv_intf.drv_cb.PREADY == 1);
            end
        end
        idle();
    endtask    

    //  Function: run_phase
    task run_phase(uvm_phase phase);
    forever begin
        seq_item_port.get_next_item(trans_drv);
        drive();
        @(drv_intf.drv_cb);
        seq_item_port.item_done();
    end
    endtask: run_phase
    
    // extern function void build_phase(uvm_phase phase);
    
    // extern task run_phase(uvm_phase phase);
    
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
    // extern function void build_phase(uvm_phase phase);
    
    //  Function: run_phase
    task run_phase(uvm_phase phase);
    forever begin
        fork
            ip_mon();
            op_mon();
        join
        `uvm_info(get_name(), $sformatf("pck_complete: %b, PSEL1: %b", pck_complete, intf.mon_cb.PSEL1), UVM_HIGH)
        if((pck_complete && !intf.mon_cb.PSEL1) || !intf.mon_cb.PRESETn) begin
            `uvm_info(get_name(), $sformatf("Sampled Packet is: %s", trans.convert2string()), UVM_HIGH)
            ap.write(trans);
            trans = new("sam_trans");
            ip_pntr = 0;
            op_pntr = 0;
            pck_complete = 0;
        end
    end
    endtask: run_phase
    // extern task run_phase(uvm_phase phase);

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

    
endclass //monitor extends uvm_monitor

///////////////////////////////////////
//////////// MY REFERENCE MODEL ///////
///////////////////////////////////////	


class ref_model#(parameter DEPTH = 5) extends uvm_component;
    `uvm_component_utils(ref_model)

    // Variables
    const int ram_depth = 2**DEPTH;
    bit [31:0] ram_mem [];  // Memory for DEPTH defined

    // Function: get_ref_val()
    function transaction get_ref_val(transaction trans);
        if(trans.PRESETn == 0) begin
            foreach (ram_mem[i]) ram_mem[i] = 32'hffffffff;
            trans.PSLVERR = 0;
            //trans.PRDATA[0] = 32'b0;
            trans.PREADY = 0;
            return trans;
        end
        for(int i=0; i<trans.PADDR.size(); i++) begin
            if(trans.PADDR[i] >= ram_depth) begin
                trans.PSLVERR = 1;
                trans.PRDATA[i] = 32'b0;
                trans.PREADY = 1;
                continue;
            end

            if(trans.PWRITE == 1) begin
                if(trans.PWDATA[i] === 32'hx || trans.PWDATA[i] === 32'hz ) begin
                    trans.PRDATA[i] = 32'b0;
                    trans.PREADY = 1;
                    trans.PSLVERR = 1;
                    continue;
                end
                ram_mem [trans.PADDR[i]] = trans.PWDATA[i];
                trans.PRDATA[i] = 32'b0;
                trans.PREADY = 1;
                trans.PSLVERR = 0;
            end
            else begin
                if(ram_mem[trans.PADDR[i]] == 32'hffffffff) begin
                    trans.PRDATA[i] = 32'hffffffff;
                    trans.PREADY = 1;
                    trans.PSLVERR = 1;
                    continue;
                end
                trans.PRDATA[i] = ram_mem [trans.PADDR[i]];
                trans.PREADY = 1;
                trans.PSLVERR = 0;
            end
        end
        return trans;
    endfunction

    // Constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
        ram_mem = new[ram_depth];
        `uvm_info("ref_model","ref_model block got executed",UVM_NONE);
    endfunction //new()
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
    
    // Function:check()
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

    // Fuction: write()
    function void write(transaction trans);
        act_trans.copy(trans);
        exp_trans = rm.get_ref_val(trans);
        check();
    endfunction

    // Constructor: new
    function new(string name, uvm_component parent);
        super.new(name, parent);
        `uvm_info("scoreboard","scoreboard constructor got executed",UVM_NONE);
    endfunction //new()

    //  Function: build_phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rm = ref_model#()::type_id::create("rm", this);
        act_trans = new("act_trans");
        ap_exp = new("ap_exp", this);
        `uvm_info("scoreboard","scoreboard build_phase block got executed",UVM_NONE);
    endfunction: build_phase
    
endclass //scoreboard extends uvm_scoreboard

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
    endfunction //new()

    //  Function: build_phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("agent","agent build phase block got executed",UVM_NONE);
        if(!uvm_config_db#(agent_config)::get(this, "*", "agnt_cfg", agnt_cfg))
        `uvm_fatal(get_name(), "agnt_cfg cannot be found in ConfigDB!")
        
        mon = monitor::type_id::create("mon", this);
        fc = fun_cov::type_id::create("fc", this);

        if(agnt_cfg.active) begin
            drv = driver::type_id::create("drv", this);
            seqr = uvm_sequencer#(transaction)::type_id::create("seqr", this);
        end

    endfunction: build_phase
    // extern function void build_phase(uvm_phase phase);
    
    //  Function: connect_phase
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        mon.intf = agnt_cfg.intf;
        ap = mon.ap;
        `uvm_info("agent","agent connect phase block got executed",UVM_NONE);

        if(agnt_cfg.active) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
            drv.drv_intf = agnt_cfg.intf;
        end

        mon.ap.connect(fc.analysis_export);

    endfunction: connect_phase
    // extern function void connect_phase(uvm_phase phase);
    
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
        agnt.ap.connect(scb.ap_exp);
        `uvm_info("env","env connect phase block got executed",UVM_NONE);
    endfunction: connect_phase
    
    
endclass //environment extends uvm_env

///////////////////////////////////////
//////////// MY TEST  //////////
///////////////////////////////////////

class base_test extends uvm_test;
    `uvm_component_utils(base_test)
    
    // Components
    environment env;

    // Variables
    rnd_sequence seq;
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
    
        uvm_config_db#(agent_config)::set(this, "env.agnt.*", "agnt_cfg", agnt_cfg);
        uvm_config_db#(int)::set(null, "seq.*", "no_cases", 100);
        
        seq = new();
        env = environment::type_id::create("env", this);
    endfunction: build_phase

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction: end_of_elaboration_phase
    
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        seq.start(env.agnt.seqr);
        #100;
        phase.drop_objection(this);
    endtask: run_phase
    
endclass //base_test extends uvm_test

///////////////////////////////////////
//////////// MY TB TOP       //////////
///////////////////////////////////////

// `include "package.svh"
// `include "apb_mem.sv"

module top;
    bit clk = 0;

    APB_intf intf(clk);

    apb_mem dut(.PCLK(clk), .PRESETn(intf.PRESETn), .PSEL1(intf.PSEL1), .PWRITE(intf.PWRITE), 
                .PENABLE(intf.PENABLE), .PADDR(intf.PADDR), .PWDATA(intf.PWDATA),
                .PRDATA(intf.PRDATA), .PREADY(intf.PREADY), .PSLVERR(intf.PSLVERR));

    always #5 clk = ~clk;

    initial begin
        uvm_config_db#(virtual APB_intf)::set(null, "*", "intf", intf);
        run_test("base_test");
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
        $assertvacuousoff(0);
      	#950;
        $finish();
    end

endmodule