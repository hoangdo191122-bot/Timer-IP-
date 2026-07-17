/* coverage off */
`timescale 1ns/1ns
module test_bench;

//===========================
// VARIABLES DECLARATIONS
//===========================
reg          sys_clk;
reg          sys_rst_n;
reg          tim_psel;
reg          tim_pwrite;
reg          tim_penable;
reg  [11:0]  tim_paddr;
reg  [31:0]  tim_pwdata;
reg  [3:0]   tim_pstrb;
reg          dbg_mode;

wire [31:0]  tim_prdata;
wire         tim_pready;
wire         tim_pslverr;
wire         tim_int;

integer      pass_cnt;
integer      fail_cnt;
reg  [31:0]  rdata;

reg [63:0]   current_count;
reg          pslv;

//===========================
// DUT INSTANTIATION
//===========================
timer dut (
                .sys_clk     (sys_clk)    ,
                .sys_rst_n   (sys_rst_n)  ,
                .tim_psel    (tim_psel)   ,
                .tim_pwrite  (tim_pwrite) ,
                .tim_penable (tim_penable),
                .tim_paddr   (tim_paddr)  ,
                .tim_pwdata  (tim_pwdata) ,
                .tim_pstrb   (tim_pstrb)  ,
                .dbg_mode    (dbg_mode)   ,
                .tim_prdata  (tim_prdata) ,
                .tim_pready  (tim_pready) ,
                .tim_pslverr (tim_pslverr),
                .tim_int     (tim_int)
        );


//===========================
// CLOCK INSTANTIATION
//===========================
initial begin
    sys_clk = 0; #100;
    forever #50 sys_clk = ~sys_clk;
end


//===========================
// APB Read/Write Tasks
//===========================
task apb_write;
    input [11:0]  addr;
    input [31:0]  data;
    input [3:0]   strb;
    begin
        @(posedge sys_clk); #1;
        tim_psel    = 1;
        tim_penable = 0;
        tim_pwrite  = 1;
        tim_paddr   = addr;
        tim_pwdata  = data;
        tim_pstrb   = strb;
        @(posedge sys_clk); #1;
        tim_penable = 1;
        wait(tim_pready);
        @(posedge sys_clk); #1;
        tim_psel    = 0;
        tim_penable = 0;
        tim_pwrite  = 0;
    end
endtask

task apb_read;
    input  [11:0] addr;
    output [31:0] read_data;
    begin
        @(posedge sys_clk); #1;
        tim_psel    = 1;
        tim_penable = 0;
        tim_pwrite  = 0;
        tim_paddr   = addr;
        tim_pstrb   = 4'h0;
        @(posedge sys_clk); #1;
        tim_penable = 1;
        wait(tim_pready);
        read_data   = tim_prdata;   // sample while PREADY high & still in ACCESS
        @(posedge sys_clk); #1;
        tim_psel    = 0;
        tim_penable = 0;
        tim_pwrite  = 0;
    end
endtask

task reset_system;
    begin
        repeat(3) @(posedge sys_clk); #1;
        sys_rst_n = 0; tim_psel = 0; tim_pwrite = 0; tim_penable = 0;
        tim_paddr = 12'h0; tim_pwdata = 32'h0; tim_pstrb = 4'h0; dbg_mode = 0;
        repeat(3) @(posedge sys_clk); #1;
        sys_rst_n = 1; #10;
    end
endtask

//===================
// Extra helper tasks
//===================
// Write that also captures pslverr (sampled during ACCESS while pready high)
task apb_write_pslv;
    input  [11:0] addr;
    input  [31:0] data;
    input  [3:0]  strb;
    output        pslv;
    begin
        @(posedge sys_clk); #1;
        tim_psel    = 1; tim_penable = 0; tim_pwrite = 1;
        tim_paddr   = addr; tim_pwdata = data; tim_pstrb = strb;
        @(posedge sys_clk); #1;
        tim_penable = 1;
        wait(tim_pready);
        #1;                          // let wr_en->slverr->pslverr settle (still in ACCESS)
        pslv = tim_pslverr;          // valid while in ACCESS with pready
        @(posedge sys_clk); #1;
        tim_psel = 0; tim_penable = 0; tim_pwrite = 0;
    end
endtask

// Wrong protocol: assert PENABLE without PSEL -> no transfer
task apb_bad_penable_only;
    input [11:0] addr;
    input [31:0] data;
    begin
        @(posedge sys_clk); #1;
        tim_psel = 0; tim_penable = 1; tim_pwrite = 1;
        tim_paddr = addr; tim_pwdata = data; tim_pstrb = 4'hF;
        repeat(3) @(posedge sys_clk); #1;
        tim_psel = 0; tim_penable = 0; tim_pwrite = 0;
    end
endtask

// Wrong protocol: assert PSEL but never PENABLE -> stuck in SETUP, no transfer
task apb_bad_psel_only;
    input [11:0] addr;
    input [31:0] data;
    begin
        @(posedge sys_clk); #1;
        tim_psel = 1; tim_penable = 0; tim_pwrite = 1;
        tim_paddr = addr; tim_pwdata = data; tim_pstrb = 4'hF;
        repeat(3) @(posedge sys_clk); #1;
        tim_psel = 0; tim_penable = 0; tim_pwrite = 0;
    end
endtask


//===================
// Check val tasks
//===================
task check_val;
    input [31:0]  expected;
    input [31:0]  actual;
    input [800:0] name;
    begin
        if (expected === actual) begin
            $display("t = %0dns, [PASS]: %0s", $stime, name);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("t = %0dns, [FAIL]: %0s. Expected: %0h. Got: %0h", $stime, name, expected, actual);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task check_val_no_slverr;
    input [31:0]  expected;
    input [31:0]  actual;
    input [800:0] name;
    begin
        if (expected === actual && !tim_pslverr) begin
            $display("t = %0dns, [PASS]: %0s", $stime, name);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("t = %0dns, [FAIL]: %0s. Expected: %0h. Got: %0h. slverr=%0b", $stime, name, expected, actual, tim_pslverr);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task check_bit;
    input [31:0]  actual;
    input [4:0]   bit_pos;
    input         expected_bit;
    input [800:0] name;
    begin
        if (actual[bit_pos] === expected_bit) begin
            $display("t = %0dns, [PASS]: %0s", $stime, name);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("t = %0dns, [FAIL]: %0s. Expected bit[%0d]=0b%0b. Got=0b%0b", $stime, name, bit_pos, expected_bit, actual[bit_pos]);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task check_count;
    input [63:0]  expected;
    input [63:0]  actual;
    input [800:0] name;
    begin
        if (expected === actual) begin
            $display("t = %0dns, [PASS]: %0s", $stime, name);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("t = %0dns, [FAIL]: %0s. Expected: %0h. Got: %0h", $stime, name, expected, actual);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask


//===================
// MAIN SIMULATION
//===================

initial begin
    //Variable Initialization
    reset_system();
    pass_cnt = 0;
    fail_cnt = 0;
    rdata    = 32'h0;

    #100;
    //1.0: TCR Reset value check.

    apb_read(12'h00, rdata);
    check_val(32'h0000_0100, rdata, "1.0 TCR Reset value check");


    //2.0: TCR R/W Access
    reset_system();

    apb_write(12'h00, 32'h0000_0000, 4'hF);
    apb_read(12'h00, rdata);
    check_val(32'h0000_0000, rdata, "2.1 TCR Write 00000000 readback");

    apb_write(12'h00, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h00, rdata);
    check_val(32'h0000_0000, rdata, "2.2 TCR Write FFFFFFFF readback"); //cannot write

    apb_write(12'h00, 32'h5555_5555, 4'hF);
    apb_read(12'h00, rdata);
    check_val(32'h0000_0501, rdata, "2.3 TCR Write 55555555 readback");
    apb_write(12'h00, 32'h0000_0000, 4'hF); //write all 0 to clear timer_en -> blocked

    apb_write(12'h00, 32'hAAAA_AAAA, 4'hF);
    apb_read(12'h00, rdata);
    check_val(32'h0000_0501, rdata, "2.4 TCR Write AAAAAAAA readback"); //cannot write

    apb_write(12'h00, 32'h5AA5_A55A, 4'hF);
    apb_read(12'h00, rdata);
    check_val(32'h0000_0501, rdata, "2.5 TCR Write 5AA5A55A readback"); //cannot write


    //3.0: TCR Byte Access
    reset_system();

    apb_write(12'h00, 32'hFFFF_FFFF, 4'h1);
    apb_read(12'h00, rdata);
    check_val_no_slverr(32'h0000_0103, rdata, "3.1 TCR byte access pstrb=0x1");
    reset_system();
    apb_write(12'h00, 32'h0000_0000, 4'hF);

    apb_write(12'h00, 32'hFFFF_F5FF, 4'h2);
    apb_read(12'h00, rdata);
    check_val_no_slverr(32'h000_0500, rdata, "3.2 TCR byte access pstrb=0x2");
    reset_system();
    apb_write(12'h00, 32'h0000_0000, 4'hF);

    apb_write(12'h00, 32'hFFFF_FFFF, 4'h4);
    apb_read(12'h00, rdata);
    check_val_no_slverr(32'h0000_0000, rdata, "3.3 TCR byte access pstrb=0x4");
    reset_system();
    apb_write(12'h00, 32'h0000_0000, 4'hF);

    apb_write(12'h00, 32'hFFFF_FFFF, 4'h8);
    apb_read(12'h00, rdata);
    check_val_no_slverr(32'h0000_0000, rdata, "3.4 TCR byte access pstrb=0x8");
    reset_system();
    apb_write(12'h00, 32'h0000_0000, 4'hF);

    apb_write(12'h00, 32'h5555_5555, 4'h3);
    apb_read(12'h00, rdata);
    check_val_no_slverr(32'h0000_0501, rdata, "3.5 TCR byte access pstrb=0x3");
    apb_write(12'h00, 32'h0000_0000, 4'hF);

    apb_write(12'h00, 32'hFFFF_FFFF, 4'hC);
    apb_read(12'h00, rdata);
    check_val_no_slverr(32'h0000_0501, rdata, "3.6 TCR byte access pstrb=0xC");

    //4.0: TDR0 Reset Value Check
    reset_system();

    apb_read(12'h04, rdata);
    check_val(32'h0000_0000, rdata, "4.0 TDR0 Reset value check");


    //5.0: TDR0 R/W Access
    reset_system();

    apb_write(12'h04, 32'h0000_0000, 4'hF);
    apb_read(12'h04, rdata);
    check_val(32'h0000_0000, rdata, "5.1 TDR0 Write 00000000 readback");

    apb_write(12'h04, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h04, rdata);
    check_val(32'hFFFF_FFFF, rdata, "5.2 TDR0 Write FFFFFFFF readback");

    apb_write(12'h04, 32'h5555_5555, 4'hF);
    apb_read(12'h04, rdata);
    check_val(32'h5555_5555, rdata, "5.3 TDR0 Write 55555555 readback");

    apb_write(12'h04, 32'hAAAA_AAAA, 4'hF);
    apb_read(12'h04, rdata);
    check_val(32'hAAAA_AAAA, rdata, "5.4 TDR0 Write AAAAAAAA readback");

    apb_write(12'h04, 32'h5AA5_A55A, 4'hF);
    apb_read(12'h04, rdata);
    check_val(32'h5AA5_A55A, rdata, "5.5 TDR0 Write 5AA5A55A readback");


    //6.0: TDR0 Byte Access
    reset_system();

    apb_write(12'h04, 32'h1111_1111, 4'h1);
    apb_read(12'h04, rdata);
    check_val(32'h0000_0011, rdata, "6.1 TDR0 byte access pstrb=0x1");

    apb_write(12'h04, 32'h2222_2222, 4'h2);
    apb_read(12'h04, rdata);
    check_val_no_slverr(32'h000_2211, rdata, "6.2 TDR0 byte access pstrb=0x2");

    apb_write(12'h04, 32'h3333_3333, 4'h4);
    apb_read(12'h04, rdata);
    check_val_no_slverr(32'h0033_2211, rdata, "6.3 TDR0 byte access pstrb=0x4");

    apb_write(12'h04, 32'h4444_4444, 4'h8);
    apb_read(12'h04, rdata);
    check_val_no_slverr(32'h4433_2211, rdata, "6.4 TDR0 byte access pstrb=0x8");

    apb_write(12'h04, 32'h5555_5555, 4'h3);
    apb_read(12'h04, rdata);
    check_val_no_slverr(32'h4433_5555, rdata, "6.5 TDR0 byte access pstrb=0x3");

    apb_write(12'h04, 32'h6666_6666, 4'hC);
    apb_read(12'h04, rdata);
    check_val_no_slverr(32'h6666_5555, rdata, "6.6 TDR0 byte access pstrb=0xC");


    //7.0: TDR1 Reset Value Check
    reset_system();

    apb_read(12'h08, rdata);
    check_val(32'h0000_0000, rdata, "7.0 TDR1 Reset value check");


    //8.0: TDR1 R/W Access
    reset_system();

    apb_write(12'h08, 32'h0000_0000, 4'hF);
    apb_read(12'h08, rdata);
    check_val(32'h0000_0000, rdata, "8.1 TDR1 Write 00000000 readback");

    apb_write(12'h08, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h08, rdata);
    check_val(32'hFFFF_FFFF, rdata, "8.2 TDR1 Write FFFFFFFF readback");

    apb_write(12'h08, 32'h5555_5555, 4'hF);
    apb_read(12'h08, rdata);
    check_val(32'h5555_5555, rdata, "8.3 TDR1 Write 55555555 readback");

    apb_write(12'h08, 32'hAAAA_AAAA, 4'hF);
    apb_read(12'h08, rdata);
    check_val(32'hAAAA_AAAA, rdata, "8.4 TDR1 Write AAAAAAAA readback");

    apb_write(12'h08, 32'h5AA5_A55A, 4'hF);
    apb_read(12'h08, rdata);
    check_val(32'h5AA5_A55A, rdata, "8.5 TDR1 Write 5AA5A55A readback");


    //9.0: TDR1 Byte Access
    reset_system();

    apb_write(12'h08, 32'h1111_1111, 4'h1);
    apb_read(12'h08, rdata);
    check_val(32'h0000_0011, rdata, "9.1 TDR1 byte access pstrb=0x1");

    apb_write(12'h08, 32'h2222_2222, 4'h2);
    apb_read(12'h08, rdata);
    check_val_no_slverr(32'h000_2211, rdata, "9.2 TDR1 byte access pstrb=0x2");

    apb_write(12'h08, 32'h3333_3333, 4'h4);
    apb_read(12'h08, rdata);
    check_val_no_slverr(32'h0033_2211, rdata, "9.3 TDR1 byte access pstrb=0x4");

    apb_write(12'h08, 32'h4444_4444, 4'h8);
    apb_read(12'h08, rdata);
    check_val_no_slverr(32'h4433_2211, rdata, "9.4 TDR0 byte access pstrb=0x8");

    apb_write(12'h08, 32'h5555_5555, 4'h3);
    apb_read(12'h08, rdata);
    check_val_no_slverr(32'h4433_5555, rdata, "9.5 TDR0 byte access pstrb=0x3");

    apb_write(12'h08, 32'h6666_6666, 4'hC);
    apb_read(12'h08, rdata);
    check_val_no_slverr(32'h6666_5555, rdata, "9.6 TDR0 byte access pstrb=0xC");


    //10.0: TCMP0 Reset Value Check
    reset_system();

    apb_read(12'h0C, rdata);
    check_val(32'hFFFF_FFFF, rdata, "10.0 TCMP0 Reset value check");


    //11.0: TCMP0 R/W Access
    reset_system();

    apb_write(12'h0C, 32'h0000_0000, 4'hF);
    apb_read(12'h0C, rdata);
    check_val(32'h0000_0000, rdata, "11.1 TCMP0 Write 00000000 readback");

    apb_write(12'h0C, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h0C, rdata);
    check_val(32'hFFFF_FFFF, rdata, "11.2 TCMP0 Write FFFFFFFF readback");

    apb_write(12'h0C, 32'h5555_5555, 4'hF);
    apb_read(12'h0C, rdata);
    check_val(32'h5555_5555, rdata, "11.3 TCMP0 Write 55555555 readback");

    apb_write(12'h0C, 32'hAAAA_AAAA, 4'hF);
    apb_read(12'h0C, rdata);
    check_val(32'hAAAA_AAAA, rdata, "11.4 TCMP0 Write AAAAAAAA readback");

    apb_write(12'h0C, 32'h5AA5_A55A, 4'hF);
    apb_read(12'h0C, rdata);
    check_val(32'h5AA5_A55A, rdata, "11.5 TCMP0 Write 5AA5A55A readback");


    //12.0: TCMP0 Byte Access
    reset_system();

    apb_write(12'h0C, 32'h1111_1111, 4'h1);
    apb_read(12'h0C, rdata);
    check_val(32'hFFFF_FF11, rdata, "12.1 TCMP0 byte access pstrb=0x1");

    apb_write(12'h0C, 32'h2222_2222, 4'h2);
    apb_read(12'h0C, rdata);
    check_val(32'hFFFF_2211, rdata, "12.2 TCMP0 byte access pstrb=0x2");

    apb_write(12'h0C, 32'h3333_3333, 4'h4);
    apb_read(12'h0C, rdata);
    check_val(32'hFF33_2211, rdata, "12.3 TCMP0 byte access pstrb=0x4");

    apb_write(12'h0C, 32'h4444_4444, 4'h8);
    apb_read(12'h0C, rdata);
    check_val(32'h4433_2211, rdata, "12.4 TCMP0 byte access pstrb=0x8");

    apb_write(12'h0C, 32'h5555_5555, 4'h3);
    apb_read(12'h0C, rdata);
    check_val(32'h4433_5555, rdata, "12.5 TCMP0 byte access pstrb=0x3");

    apb_write(12'h0C, 32'h6666_6666, 4'hC);
    apb_read(12'h0C, rdata);
    check_val(32'h6666_5555, rdata, "12.6 TCMP0 byte access pstrb=0xC");


    //13.0: TCMP1 Reset Value Check
    reset_system();

    apb_read(12'h10, rdata);
    check_val(32'hFFFF_FFFF, rdata, "13.0 TCMP1 Reset value check");


    //14.0: TCMP1 R/W Access
    reset_system();

    apb_write(12'h10, 32'h0000_0000, 4'hF);
    apb_read(12'h10, rdata);
    check_val(32'h0000_0000, rdata, "14.1 TCMP1 Write 00000000 readback");

    apb_write(12'h10, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h10, rdata);
    check_val(32'hFFFF_FFFF, rdata, "14.2 TCMP1 Write FFFFFFFF readback");

    apb_write(12'h10, 32'h5555_5555, 4'hF);
    apb_read(12'h10, rdata);
    check_val(32'h5555_5555, rdata, "14.3 TCMP1 Write 55555555 readback");

    apb_write(12'h10, 32'hAAAA_AAAA, 4'hF);
    apb_read(12'h10, rdata);
    check_val(32'hAAAA_AAAA, rdata, "14.4 TCMP1 Write AAAAAAAA readback");

    apb_write(12'h10, 32'h5AA5_A55A, 4'hF);
    apb_read(12'h10, rdata);
    check_val(32'h5AA5_A55A, rdata, "14.5 TCMP1 Write 5AA5A55A readback");


    //15.0: TCMP1 Byte Access
    reset_system();

    apb_write(12'h10, 32'h1111_1111, 4'h1);
    apb_read(12'h10, rdata);
    check_val(32'hFFFF_FF11, rdata, "15.1 TCMP1 byte access pstrb=0x1");

    apb_write(12'h10, 32'h2222_2222, 4'h2);
    apb_read(12'h10, rdata);
    check_val(32'hFFFF_2211, rdata, "15.2 TCMP1 byte access pstrb=0x2");

    apb_write(12'h10, 32'h3333_3333, 4'h4);
    apb_read(12'h10, rdata);
    check_val(32'hFF33_2211, rdata, "15.3 TCMP1 byte access pstrb=0x4");

    apb_write(12'h10, 32'h4444_4444, 4'h8);
    apb_read(12'h10, rdata);
    check_val(32'h4433_2211, rdata, "15.4 TCMP1 byte access pstrb=0x8");

    apb_write(12'h10, 32'h5555_5555, 4'h3);
    apb_read(12'h10, rdata);
    check_val(32'h4433_5555, rdata, "15.5 TCMP1 byte access pstrb=0x3");

    apb_write(12'h10, 32'h6666_6666, 4'hC);
    apb_read(12'h10, rdata);
    check_val(32'h6666_5555, rdata, "15.6 TCMP1 byte access pstrb=0xC");


    //16.0: TIER Reset Value Check
    reset_system();
    apb_read(12'h14, rdata);
    check_val(32'h0000_0000, rdata, "16.0 TIER Reset Value Check");

    //17.0: TIER R/W Access
    reset_system();

    apb_write(12'h14, 32'h0000_0000, 4'hF);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0000, rdata, "17.1 TIER Write 00000000 readback");

    apb_write(12'h14, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0001, rdata, "17.2 TIER Write FFFFFFFF readback");

    apb_write(12'h14, 32'h5555_5555, 4'hF);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0001, rdata, "17.3 TIER Write 55555555 readback");

    apb_write(12'h14, 32'hAAAA_AAAA, 4'hF);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0000, rdata, "17.4 TIER Write AAAAAAAA readback");

    apb_write(12'h14, 32'h5AA5_A55A, 4'hF);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0000, rdata, "17.5 TIER Write 5AA5A55A readback");


    //18.0: TIER Byte Access
    reset_system();

    apb_write(12'h14, 32'h1111_1111, 4'h1);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0001, rdata, "18.1 TIER byte access pstrb=0x1");

    apb_write(12'h14, 32'h2222_2222, 4'h2);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0001, rdata, "18.2 TIER byte access pstrb=0x2");

    apb_write(12'h14, 32'h3333_3333, 4'h4);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0001, rdata, "18.3 TIER byte access pstrb=0x4");

    apb_write(12'h14, 32'h4444_4444, 4'h8);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0001, rdata, "18.4 TIER byte access pstrb=0x8");

    apb_write(12'h14, 32'h6666_6666, 4'h3);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0000, rdata, "18.5 TIER byte access pstrb=0x3");

    apb_write(12'h14, 32'h7777_7777, 4'hC);
    apb_read(12'h14, rdata);
    check_val(32'h0000_0000, rdata, "18.6 TIER byte access pstrb=0xC");


    //19.0: TISR Reset Value Check
    reset_system();
    apb_read(12'h18, rdata);
    check_val(32'h0000_0000, rdata, "19.0 TISR Reset Value Check");

    //20.0: TISR R/W Access
    //assert interrupt
    apb_write(12'h14, 32'h0000_0001, 4'hF); // TIER: int_en=1
    apb_write(12'h0C, 32'h0000_0005, 4'hF); // TCMP0: compare=5
    apb_write(12'h10, 32'h0000_0000, 4'hF); // TCMP1: upper=0
    apb_write(12'h00, 32'h0000_0001, 4'hF); // TCR: timer_en=1

    wait(tim_int);
    @(posedge sys_clk); #1;

    apb_write(12'h18, 32'h0000_0001, 4'hF);
    apb_read(12'h18, rdata);
    check_val(32'h0000_0000, rdata, "20.1 TISR Write 1 to Clear");

    apb_write(12'h18, 32'h0000_0000, 4'hF);
    apb_read(12'h18, rdata);
    check_val(32'h0000_0000, rdata, "20.2 TISR Write 00000000 readback");

    apb_write(12'h18, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h18, rdata);
    check_val(32'h0000_0000, rdata, "20.3 TISR Write FFFFFFFF readback");

    apb_write(12'h18, 32'h5555_5555, 4'hF);
    apb_read(12'h18, rdata);
    check_val(32'h0000_0000, rdata, "20.4 TISR Write 55555555 readback");

    apb_write(12'h18, 32'hAAAA_AAAA, 4'hF);
    apb_read(12'h18, rdata);
    check_val(32'h0000_0000, rdata, "20.5 TISR Write AAAAAAAA readback");

    apb_write(12'h18, 32'h5AA5_A55A, 4'hF);
    apb_read(12'h18, rdata);
    check_val(32'h0000_0000, rdata, "20.6 TISR Write 5AA5A55A readback");


    //21.0: TISR Byte Access
    reset_system();

    //assert interrupt
    apb_write(12'h14, 32'h0000_0001, 4'hF); // TIER: int_en=1
    apb_write(12'h0C, 32'h0000_0005, 4'hF); // TCMP0: compare=5
    apb_write(12'h10, 32'h0000_0000, 4'hF); // TCMP1: upper=0
    apb_write(12'h00, 32'h0000_0001, 4'hF); // TCR: timer_en=1

    wait(tim_int);
    @(posedge sys_clk); #1;

    apb_write(12'h18, 32'hFFFF_FFFF, 4'h2);
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "21.1 TISR Byte Access pstrb=0x2");

    apb_write(12'h18, 32'hFFFF_FFFF, 4'h4);
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "21.2 TISR Byte Access pstrb=0x4");

    apb_write(12'h18, 32'hFFFF_FFFF, 4'h8);
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "21.3 TISR Byte Access pstrb=0x8");

    apb_write(12'h18, 32'hFFFF_FFFF, 4'hC);
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "21.4 TISR Byte Access pstrb=0xC");

    apb_write(12'h18, 32'h0000_0001, 4'h1);
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b0, "21.5 TISR Byte Access pstrb=0x1, Write 0x1");

    reset_system();

    //assert interrupt
    apb_write(12'h14, 32'h0000_0001, 4'hF); // TIER: int_en=1
    apb_write(12'h0C, 32'h0000_0005, 4'hF); // TCMP0: compare=5
    apb_write(12'h10, 32'h0000_0000, 4'hF); // TCMP1: upper=0
    apb_write(12'h00, 32'h0000_0001, 4'hF); // TCR: timer_en=1

    wait(tim_int);
    @(posedge sys_clk); #1;

    apb_write(12'h18, 32'h0000_0001, 4'h3);
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b0, "21.6 TISR Byte Access pstrb=0x3, Write 0x1");


    //22.0 THCSR Reset Value Check
    reset_system();

    apb_read(12'h1C, rdata);
    check_val(32'h0000_0000, rdata, "22.0 THCSR Reset Value Check");

    //23.0: THCSR R/W Access
    reset_system();

    apb_write(12'h1C, 32'h0000_0000, 4'hF);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0000, rdata, "23.1 THCSR Write 00000000 readback");

    apb_write(12'h1C, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0001, rdata, "23.2 THCSR Write FFFFFFFF readback");

    apb_write(12'h1C, 32'h5555_5555, 4'hF);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0001, rdata, "23.3 THCSR Write 55555555 readback");

    apb_write(12'h1C, 32'hAAAA_AAAA, 4'hF);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0000, rdata, "23.4 THCSR Write AAAAAAAA readback");

    apb_write(12'h1C, 32'h5AA5_A55A, 4'hF);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0000, rdata, "23.5 THCSR Write 5AA5A55A readback");


    //24.0: THCSR Byte Access
    reset_system();

    apb_write(12'h1C, 32'h1111_1111, 4'h1);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0001, rdata, "24.1 THCSR byte access pstrb=0x1");

    apb_write(12'h1C, 32'h2222_2222, 4'h2);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0001, rdata, "24.2 THCSR byte access pstrb=0x2");

    apb_write(12'h1C, 32'h3333_3333, 4'h4);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0001, rdata, "24.3 THCSR byte access pstrb=0x4");

    apb_write(12'h1C, 32'h4444_4444, 4'h8);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0001, rdata, "24.4 THCSR byte access pstrb=0x8");

    apb_write(12'h1C, 32'h6666_6666, 4'h3);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0000, rdata, "24.5 THCSR byte access pstrb=0x3");

    apb_write(12'h1C, 32'h7777_7777, 4'hC);
    apb_read(12'h1C, rdata);
    check_val(32'h0000_0000, rdata, "24.6 THCSR byte access pstrb=0xC");


    //25.0 Reserved Registers
    apb_write(12'hFFC, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'hFFC, rdata);
    check_val(32'h0000_0000, rdata, "25.1 Reserved Registers");

    apb_write(12'h020, 32'hFFFF_FFFF, 4'hF);
    apb_read(12'h020, rdata);
    check_val(32'h0000_0000, rdata, "25.2 Reserved Registers");


    //26.0 Check counting at boundary at TDR0 is correct
    reset_system();

    // Preload TDR0 so it wraps after exactly 256 cycles
    apb_write(12'h04, 32'hFFFF_FF00, 4'hF); // TDR0 = 0xFFFFFF00
    apb_write(12'h08, 32'h0000_0000, 4'hF); // TDR1 = 0

    apb_write(12'h00, 32'h0000_0001, 4'hF); // TCR: timer_en=1

    repeat(256) @(posedge sys_clk); // Wait 256 cycles
    // Halt the counter
    dbg_mode = 1;
    apb_write(12'h1C, 32'h0000_0001, 4'hF); // THCSR: halt_req=1
    repeat(2) @(posedge sys_clk); #1;

    // TDR0 should be 0 or small value (counting from beginning after wrap)
    apb_read(12'h04, rdata);
    if (rdata < 32'h0000_0010) begin
        $display("t = %0dns, [PASS]: %0s", $stime, "26.1 TDR0 counting from beginning");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("t = %0dns, [FAIL]: %0s. Got: %0h (expected small/wrapped)", $stime, "26.1 TDR0 counting from beginning", rdata);
        fail_cnt = fail_cnt + 1;
    end

    // TDR1 should be 1
    apb_read(12'h08, rdata);
    check_bit(rdata, 0, 1'b1, "26.2 TDR1 is 1");


    //27.0 Update TDR0/TDR1 when timer is working
    reset_system();
    //set timer_en=1, counter counts from 0
    apb_write(12'h00, 32'h0000_0001, 4'hF);

    repeat(256) @(posedge sys_clk); #1;
    check_count(64'h0000_0000_0000_0100, dut.cnt.count, "27.1 Counter is counting normally");

    apb_write(12'h08, 32'h0000_0000, 4'hF); // Preload TDR1=0x0
    apb_write(12'h04, 32'hffff_ff00, 4'hF); // Preload TDR0=0xFFFF_FF00

    repeat(256) @(posedge sys_clk); #1;
    check_count(64'h0000_0001_0000_0000, dut.cnt.count, "27.2 Counter is counting from beginning normally");
    check_bit(dut.cnt.count[63:32], 0, 1'b1, "27.3 TDR is 1");


    //28.0 Counter value is Reset when timer_en changed from 1->0
    apb_write(12'h00, 32'h0000_0000, 4'hF);
    repeat(2) @(posedge sys_clk); #1;
    check_count(64'h0000_0000_0000_0000, dut.cnt.count, "28.0 Counter value is reset when timer_en changed from 1->0");

    //29.0 TDR0/1 can be set while timer_en=0
    apb_write(12'h04, 32'hffff_ff00, 4'hF); // Preload TDR0=0xffff_ff00
    apb_write(12'h08, 32'h0000_0100, 4'hF); //Preload TDR1=0x0000_0100
    apb_read(12'h04, rdata);
    check_val(32'hffff_ff00, rdata, "29.1 TDR0 can be set while timer_en=0");
    apb_read(12'h08, rdata);
    check_val(32'h0000_0100, rdata, "29.2 TDR1 can be set while timer_en=0");

    //30.0 Counter works normally for timer_en=1->0->1
    apb_write(12'h00, 32'h0000_0302, 4'hF); // div_en=1, div_val=0011 (:8), timer_en=0
    apb_write(12'h00, 32'h0000_0303, 4'hF); // set timer_en=1

    //count is currently 64'h0000_0100_ffff_ff00
    repeat(8) @(posedge sys_clk); #1; // increment count by 1
    check_count(64'h0000_0100_ffff_ff01, dut.cnt.count, "30.0 Counter works normally for timer_en=1->0->1");


    //31.0 Counter counts normally during interrupt
    reset_system();
    apb_write(12'h14, 32'h0000_0001, 4'hF);
    apb_write(12'h0C, 32'h0000_0005, 4'hF);
    apb_write(12'h10, 32'h0000_0000, 4'hF);
    apb_write(12'h00, 32'h0000_0001, 4'hF); //timer_en=1

    wait(tim_int);
    repeat(3) @(posedge sys_clk); #1;
    check_val(32'h0000_0008, dut.regs.tdr0_out, "31.1 Counter counts normally during interrupt");
    check_val(32'h0000_0000, dut.regs.tdr1_out, "31.2 Counter counts normally during interrupt");

    //32.0 Counter counts normally after overflow
    reset_system();
    apb_write(12'h04, 32'hffff_fff0, 4'hF); //TDR0 = fffffff0
    apb_write(12'h08, 32'hffff_ffff, 4'hF); //TDR1 = ffffffff
    apb_write(12'h00, 32'h0000_0001, 4'hF); //timer_en=1

    wait(dut.cnt.count==64'hffff_ffff_ffff_ffff);
    repeat(2) @(posedge sys_clk); #1;
    check_val(32'h0000_0000, dut.regs.tdr0_out, "32.2 Counter counts normally after overflow");
    check_val(32'h0000_0000, dut.regs.tdr1_out, "32.2 Counter counts normally after overflow");

    //33.0 div_en=1, div_val=1
    reset_system();
    apb_write(12'h00, 32'h0000_0102, 4'hF);
    apb_write(12'h00, 32'h0000_0103, 4'hF);
    current_count = dut.cnt.count;
    repeat(2) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "33.0 Count freq is correct for div_en=1, div_val=1");

    //34.0 div_en=1, div_val=2
    reset_system();
    apb_write(12'h00, 32'h0000_0202, 4'hF);
    apb_write(12'h00, 32'h0000_0203, 4'hF);
    current_count = dut.cnt.count;
    repeat(4) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "34.0 Count freq is correct for div_en=1, div_val=2");

    //35.0 div_en=1, div_val=3
    reset_system();
    apb_write(12'h00, 32'h0000_0302, 4'hF);
    apb_write(12'h00, 32'h0000_0303, 4'hF);
    current_count = dut.cnt.count;
    repeat(8) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "35.0 Count freq is correct for div_en=1, div_val=3");

    //36.0 div_en=1, div_val=4
    reset_system();
    apb_write(12'h00, 32'h0000_0402, 4'hF);
    apb_write(12'h00, 32'h0000_0403, 4'hF);
    current_count = dut.cnt.count;
    repeat(16) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "36.0 Count freq is correct for div_en=1, div_val=4");


    //37.0 div_en=1, div_val=5
    reset_system();
    apb_write(12'h00, 32'h0000_0502, 4'hF);
    apb_write(12'h00, 32'h0000_0503, 4'hF);
    current_count = dut.cnt.count;
    repeat(32) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "37.0 Count freq is correct for div_en=1, div_val=5");


    //38.0 div_en=1, div_val=6
    reset_system();
    apb_write(12'h00, 32'h0000_0602, 4'hF);
    apb_write(12'h00, 32'h0000_0603, 4'hF);
    current_count = dut.cnt.count;
    repeat(64) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "38.0 Count freq is correct for div_en=1, div_val=6");


    //39.0 div_en=1, div_val=7
    reset_system();
    apb_write(12'h00, 32'h0000_0702, 4'hF);
    apb_write(12'h00, 32'h0000_0703, 4'hF);
    current_count = dut.cnt.count;
    repeat(128) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "39.0 Count freq is correct for div_en=1, div_val=7");


    //40.0 div_en=1, div_val=8
    reset_system();
    apb_write(12'h00, 32'h0000_0802, 4'hF);
    apb_write(12'h00, 32'h0000_0803, 4'hF);
    current_count = dut.cnt.count;
    repeat(256) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "40.0 Count freq is correct for div_en=1, div_val=8");


    //41.0 Timer counts correctly when div_val is set but div_en is not set
    reset_system();
    apb_write(12'h00, 32'h0000_0001, 4'hF); //timer_en=1
    apb_write(12'h00, 32'h0000_0201, 4'hF); //div_val=2
    current_count = dut.cnt.count;
    @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "41.0 Timer counts correctly when div_val is set but div_en is not set");



    //==================================================================
    // ADDED CHECKLIST COVERAGE (items not in the original sequence)
    //==================================================================

    //42.0 Halt in debug mode: counter stops, halt_ack=1, then resumes
    reset_system();
    apb_write(12'h00, 32'h0000_0001, 4'hF); // timer_en=1
    repeat(20) @(posedge sys_clk); #1;
    dbg_mode = 1;
    apb_write(12'h1C, 32'h0000_0001, 4'hF); // halt_req=1 (debug mode -> honored)
    repeat(2) @(posedge sys_clk); #1;
    apb_read(12'h1C, rdata);
    check_bit(rdata, 1, 1'b1, "42.1 halt_ack=1 in debug mode");
    current_count = dut.cnt.count;
    repeat(8) @(posedge sys_clk); #1;
    check_count(current_count, dut.cnt.count, "42.2 counter halted (no count) in debug mode");
    // release halt -> resume
    apb_write(12'h1C, 32'h0000_0000, 4'hF); // halt_req=0
    current_count = dut.cnt.count;
    repeat(1) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "42.3 counter resumes after halt cleared");

    //43.0 Halt request NOT honored in normal mode (dbg_mode=0)
    reset_system();              // dbg_mode back to 0
    apb_write(12'h00, 32'h0000_0001, 4'hF); // timer_en=1
    apb_write(12'h1C, 32'h0000_0001, 4'hF); // halt_req=1 but dbg_mode=0
    repeat(2) @(posedge sys_clk); #1;
    apb_read(12'h1C, rdata);
    check_bit(rdata, 1, 1'b0, "43.1 halt_ack=0 in normal mode");
    current_count = dut.cnt.count;
    repeat(1) @(posedge sys_clk); #1;
    check_count(current_count+1, dut.cnt.count, "43.2 counter keeps counting in normal mode");

    //44.0 APB normal: write then read TDR0 (protocol sanity)
    reset_system();
    apb_write(12'h04, 32'h1234_5678, 4'hF);
    apb_read (12'h04, rdata);
    check_val(32'h1234_5678, rdata, "44.0 normal APB write-then-read TDR0");

    //45.0 Wrong protocol: PENABLE only (no PSEL) -> register unchanged
    reset_system();
    apb_write(12'h0C, 32'hDEAD_BEEF, 4'hF);     // known TCMP0 value
    apb_bad_penable_only(12'h0C, 32'hFFFF_FFFF);
    apb_read(12'h0C, rdata);
    check_val(32'hDEAD_BEEF, rdata, "45.0 PENABLE-only does not write");

    //46.0 Wrong protocol: PSEL only (no PENABLE) -> register unchanged
    apb_bad_psel_only(12'h0C, 32'h0000_0000);
    apb_read(12'h0C, rdata);
    check_val(32'hDEAD_BEEF, rdata, "46.0 PSEL-only does not write");

    //47.0 Pready/wait-state: PREADY is low during first ACCESS cycle, high next
    reset_system();
    @(posedge sys_clk); #1;
    tim_psel = 1; tim_penable = 0; tim_pwrite = 0; tim_paddr = 12'h00; tim_pstrb = 4'h0;
    @(posedge sys_clk); #1;
    tim_penable = 1;                 // request ACCESS
    @(posedge sys_clk); #1;          // first ACCESS cycle (wait state)
    check_bit({31'h0, tim_pready}, 0, 1'b0, "47.1 PREADY low during wait state");
    wait(tim_pready);
    check_bit({31'h0, tim_pready}, 0, 1'b1, "47.2 PREADY high to end transfer");
    @(posedge sys_clk); #1;
    tim_psel = 0; tim_penable = 0;

    //48.0 Pslverr: prohibited div_val sweep (9..F => error, 8 => ok)
    reset_system();
    apb_write_pslv(12'h00, 32'h0000_0900, 4'hF, pslv);
    check_bit({31'h0, pslv}, 0, 1'b1, "48.1 div_val=9 pslverr=1");
    apb_read(12'h00, rdata);
    check_val(32'h0000_0100, rdata, "48.1b div_val=9 TCR unchanged");
    apb_write_pslv(12'h00, 32'h0000_0A00, 4'hF, pslv);
    check_bit({31'h0, pslv}, 0, 1'b1, "48.2 div_val=A pslverr=1");
    apb_write_pslv(12'h00, 32'h0000_0F00, 4'hF, pslv);
    check_bit({31'h0, pslv}, 0, 1'b1, "48.3 div_val=F pslverr=1");
    apb_read(12'h00, rdata);
    check_val(32'h0000_0100, rdata, "48.4 TCR still reset value after illegal writes");
    apb_write_pslv(12'h00, 32'h0000_0800, 4'hF, pslv);   // div_val=8 allowed
    check_bit({31'h0, pslv}, 0, 1'b0, "48.5 div_val=8 pslverr=0");
    apb_read(12'h00, rdata);
    check_val(32'h0000_0800, rdata, "48.6 div_val=8 written back");

    //49.0 Pslverr: change div_en/div_val while timer_en=1
    reset_system();
    apb_write_pslv(12'h00, 32'h0000_0001, 4'hF, pslv); // timer_en=1
    check_bit({31'h0, pslv}, 0, 1'b0, "49.1 enable timer pslverr=0");
    apb_write_pslv(12'h00, 32'h0000_0103, 4'hF, pslv); // change div while en
    check_bit({31'h0, pslv}, 0, 1'b1, "49.2 change div_val/en while timer_en=1 pslverr=1");
    apb_read(12'h00, rdata);
    check_val(32'h0000_0001, rdata, "49.3 TCR unchanged (still 0x1)");
    apb_write_pslv(12'h00, 32'h0000_0002, 4'hF, pslv); // change div_en while en
    check_bit({31'h0, pslv}, 0, 1'b1, "49.4 change div_en while timer_en=1 pslverr=1");

    //50.0 Pslverr timing: pslverr asserted together with pready
    reset_system();
    apb_write_pslv(12'h00, 32'h0000_0900, 4'hF, pslv); // illegal -> pslv captured at pready
    check_bit({31'h0, pslv}, 0, 1'b1, "50.0 pslverr=1 sampled when pready=1");

    //51.0 Multiple access WW-RR (write TDR0, TDR1 then read both)
    reset_system();
    apb_write(12'h04, 32'hCAFE_0001, 4'hF);
    apb_write(12'h08, 32'hCAFE_0002, 4'hF);
    apb_read (12'h04, rdata);
    check_val(32'hCAFE_0001, rdata, "51.1 WW-RR TDR0 readback");
    apb_read (12'h08, rdata);
    check_val(32'hCAFE_0002, rdata, "51.2 WW-RR TDR1 readback");

    //52.0 Multiple access WR-WR
    reset_system();
    apb_write(12'h04, 32'h0BAD_F00D, 4'hF);
    apb_read (12'h04, rdata);
    check_val(32'h0BAD_F00D, rdata, "52.1 WR-WR TDR0");
    apb_write(12'h08, 32'h0FEE_1234, 4'hF);
    apb_read (12'h08, rdata);
    check_val(32'h0FEE_1234, rdata, "52.2 WR-WR TDR1");

    //53.0 Unaligned access: writes to unaligned offsets are ignored
    reset_system();
    apb_write(12'h04, 32'hA5A5_5A5A, 4'hF);   // preload TDR0
    apb_write(12'h05, 32'hFFFF_FFFF, 4'hF);   // unaligned -> ignored
    apb_write(12'h06, 32'hFFFF_FFFF, 4'hF);
    apb_write(12'h07, 32'hFFFF_FFFF, 4'hF);
    apb_read (12'h04, rdata);
    check_val(32'hA5A5_5A5A, rdata, "53.0 unaligned writes do not change register");

    //54.0 One-hot / aliasing: distinct values to all regs, then read back
    reset_system();
    apb_write(12'h0C, 32'h3333_3333, 4'hF);   // TCMP0
    apb_write(12'h10, 32'h4444_4444, 4'hF);   // TCMP1
    apb_write(12'h14, 32'h0000_0001, 4'hF);   // TIER
    apb_write(12'h1C, 32'h0000_0001, 4'hF);   // THCSR (halt_req, dbg=0 -> ack=0)
    apb_write(12'h04, 32'h1111_1111, 4'hF);   // TDR0 (timer_en=0 -> count=load_val)
    apb_write(12'h08, 32'h2222_2222, 4'hF);   // TDR1
    apb_write(12'h00, 32'h0000_0800, 4'hF);   // TCR div_val=8, timer_en=0
    apb_read(12'h00, rdata); check_val(32'h0000_0800, rdata, "54.1 TCR no alias");
    apb_read(12'h04, rdata); check_val(32'h1111_1111, rdata, "54.2 TDR0 no alias");
    apb_read(12'h08, rdata); check_val(32'h2222_2222, rdata, "54.3 TDR1 no alias");
    apb_read(12'h0C, rdata); check_val(32'h3333_3333, rdata, "54.4 TCMP0 no alias");
    apb_read(12'h10, rdata); check_val(32'h4444_4444, rdata, "54.5 TCMP1 no alias");
    apb_read(12'h14, rdata); check_val(32'h0000_0001, rdata, "54.6 TIER no alias");
    apb_read(12'h1C, rdata); check_val(32'h0000_0001, rdata, "54.7 THCSR no alias");

    //55.0 Reset clears all registers back to defaults
    reset_system();
    apb_write(12'h00, 32'h0000_0801, 4'hF);   // mess up regs while running
    apb_write(12'h0C, 32'h1234_5678, 4'hF);
    apb_write(12'h14, 32'h0000_0001, 4'hF);
    reset_system();                            // assert reset again
    apb_read(12'h00, rdata); check_val(32'h0000_0100, rdata, "55.1 TCR reset value after reset");
    apb_read(12'h0C, rdata); check_val(32'hFFFF_FFFF, rdata, "55.2 TCMP0 reset value after reset");
    apb_read(12'h14, rdata); check_val(32'h0000_0000, rdata, "55.3 TIER reset value after reset");

    //56.0 Reset during operation clears pending interrupt; can re-assert
    reset_system();
    apb_write(12'h14, 32'h0000_0001, 4'hF);   // int_en=1
    apb_write(12'h0C, 32'h0000_0005, 4'hF);   // TCMP0=5
    apb_write(12'h10, 32'h0000_0000, 4'hF);
    apb_write(12'h00, 32'h0000_0001, 4'hF);   // timer_en=1
    wait(tim_int);
    reset_system();                            // reset while interrupt pending
    apb_read(12'h18, rdata);
    check_val(32'h0000_0000, rdata, "56.1 TISR cleared by reset");
    // re-arm and confirm interrupt asserts again
    apb_write(12'h14, 32'h0000_0001, 4'hF);
    apb_write(12'h0C, 32'h0000_0005, 4'hF);
    apb_write(12'h10, 32'h0000_0000, 4'hF);
    apb_write(12'h00, 32'h0000_0001, 4'hF);
    wait(tim_int);
    check_bit({31'h0, tim_int}, 0, 1'b1, "56.2 interrupt re-asserts after reset");

    //57.0 Interrupt pending SET with int_en=0 (output stays low, int_st=1)
    reset_system();
    apb_write(12'h0C, 32'h0000_0005, 4'hF);   // TCMP0=5, TIER NOT enabled
    apb_write(12'h10, 32'h0000_0000, 4'hF);
    apb_write(12'h00, 32'h0000_0001, 4'hF);   // timer_en=1
    repeat(20) @(posedge sys_clk); #1;        // count passes 5
    check_bit({31'h0, tim_int}, 0, 1'b0, "57.1 tim_int stays low when int_en=0");
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "57.2 TISR.int_st=1 even when int disabled");

    //58.0 Interrupt clear behaviour without enable (W1C)
    apb_write(12'h18, 32'h0000_0000, 4'hF);   // write 0 -> no effect
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "58.1 write 0 to int_st keeps 1");
    apb_write(12'h18, 32'h0000_0001, 4'hF);   // write 1 -> clears
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b0, "58.2 write 1 to int_st clears it");

    //59.0 Interrupt manual condition: TDR=0xFFFFFFFF makes count==comp (default)
    reset_system();
    apb_write(12'h04, 32'hFFFF_FFFF, 4'hF);   // TDR0=FFFFFFFF
    apb_write(12'h08, 32'hFFFF_FFFF, 4'hF);   // TDR1=FFFFFFFF -> count=all 1s = comp default
    repeat(4) @(posedge sys_clk); #1;
    check_bit({31'h0, tim_int}, 0, 1'b0, "59.1 manual int: tim_int low (int_en=0)");
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "59.2 manual int: TISR.int_st=1");

    //60.0 Interrupt manual condition WITH enable -> tim_int asserts
    reset_system();
    apb_write(12'h14, 32'h0000_0001, 4'hF);   // int_en=1
    apb_write(12'h04, 32'hFFFF_FFFF, 4'hF);
    apb_write(12'h08, 32'hFFFF_FFFF, 4'hF);
    repeat(4) @(posedge sys_clk); #1;
    check_bit({31'h0, tim_int}, 0, 1'b1, "60.0 manual int with enable: tim_int=1");

    //61.0 Mask: clear int_en while pending -> output negates, int_st stays
    reset_system();
    apb_write(12'h14, 32'h0000_0001, 4'hF);   // int_en=1
    apb_write(12'h0C, 32'h0000_0005, 4'hF);
    apb_write(12'h10, 32'h0000_0000, 4'hF);
    apb_write(12'h00, 32'h0000_0001, 4'hF);   // timer_en=1
    wait(tim_int);
    apb_write(12'h14, 32'h0000_0000, 4'hF);   // mask: int_en=0
    repeat(2) @(posedge sys_clk); #1;
    check_bit({31'h0, tim_int}, 0, 1'b0, "61.1 masked: tim_int negated");
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "61.2 masked: TISR.int_st still 1");

    //62.0 Once asserted, interrupt kept after timer_en=0
    reset_system();
    apb_write(12'h14, 32'h0000_0001, 4'hF);
    apb_write(12'h0C, 32'h0000_0005, 4'hF);
    apb_write(12'h10, 32'h0000_0000, 4'hF);
    apb_write(12'h00, 32'h0000_0001, 4'hF);
    wait(tim_int);
    apb_write(12'h00, 32'h0000_0000, 4'hF);   // timer_en=0
    repeat(2) @(posedge sys_clk); #1;
    check_bit({31'h0, tim_int}, 0, 1'b1, "62.1 interrupt kept high after timer_en=0");
    apb_read(12'h18, rdata);
    check_bit(rdata, 0, 1'b1, "62.2 int_st kept 1 after timer_en=0");



    $display("====================================");
    $display("       VERIFICATION COMPLETE        ");
    $display("   pass_cnt = %0d     fail_cnt = %0d", pass_cnt, fail_cnt);
    $display("====================================");
    $finish;
end


endmodule
/* coverage on */
