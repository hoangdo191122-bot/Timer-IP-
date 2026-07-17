module register(
    input wire          sys_clk,
    input wire          sys_rst_n,
    input wire          wr_en,
    input wire          rd_en,
    input wire [11:0]   addr,
    input wire [31:0]   wdata,
    input wire [63:0]   count,
    input wire          dbg_mode,
    input wire          int_st,
    input wire [3:0]    tim_pstrb,

    output wire [31:0] rdata,
    output wire         timer_en,
    output wire         div_en,
    output wire [3:0]  div_val,
    output wire         tim_int,
    output wire         halt_ack,
    output wire [63:0] comp_val,
    output wire [63:0] load_val,
    output wire         load_en,
    output wire         slverr
);

//------------------------------------
// TIMER CONTROL REGISTER (0x00)
//------------------------------------
wire        tcr_sel = (addr == 12'h0) & wr_en;
reg [31:0] tcr_out;

//Byte Strobe Logic
wire [31:0] valid_wdata_tcr;

assign valid_wdata_tcr[7:0]   = (tim_pstrb[0]) ? wdata[7:0]   : tcr_out[7:0];
assign valid_wdata_tcr[15:8]  = (tim_pstrb[1]) ? wdata[15:8]  : tcr_out[15:8];
assign valid_wdata_tcr[23:16] = (tim_pstrb[2]) ? wdata[23:16] : tcr_out[23:16];
assign valid_wdata_tcr[31:24] = (tim_pstrb[3]) ? wdata[31:24] : tcr_out[31:24];

//Identify if div_val/div_en are changing compared to previous state
wire div_val_changed = (valid_wdata_tcr[11:8] != tcr_out[11:8]);
wire div_en_changed  = (valid_wdata_tcr[1]    != tcr_out[1]);

wire prohibit_div    = (valid_wdata_tcr[11:8] > 4'b1000); //prohibited div_val condition
wire illegal_config  = tcr_out[0] && (div_val_changed || div_en_changed); // timer_en high -> block div_en/div_val changes

wire illegal_write   = tcr_sel && (prohibit_div || illegal_config);

//prohibited change to div_val when timer_en is High
wire [3:0] next_div_val = (tcr_sel && !illegal_write) ? valid_wdata_tcr[11:8] : tcr_out[11:8];
wire       next_div_en  = (tcr_sel && !illegal_write) ? valid_wdata_tcr[1] : tcr_out[1];
wire       next_tim_en  = (tcr_sel && !illegal_write) ? valid_wdata_tcr[0] : tcr_out[0];

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) tcr_out <= {20'h0, 4'h1, 6'h0, 1'b0, 1'b0};
    else            tcr_out <= {20'h0, next_div_val, 6'h0, next_div_en, next_tim_en};
end

assign div_val  = tcr_out[11:8];
assign div_en   = tcr_out[1];
assign timer_en = tcr_out[0];

// SLVERR Logic
assign slverr = illegal_write;

//------------------------------------
// TIMER DATA REGISTER 0 & 1 (0x04 & 0x08)
//------------------------------------

//Synchronous Edge Detection for "timer_en" (H->L)
reg timer_en_q;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) timer_en_q <= 1'b0;
    else            timer_en_q <= timer_en;
end

wire timer_en_fall = (!timer_en && timer_en_q); //Falling edge detection on timer_en

//Timer Data Registers
wire        tdr0_sel;
wire        tdr1_sel;
reg  [31:0] tdr0_out;
reg  [31:0] tdr1_out;

// holds the user-written start counting value
reg  [31:0] tdr0_load_latch;
reg  [31:0] tdr1_load_latch;

assign tdr0_sel = (addr == 12'h4) & wr_en;
assign tdr1_sel = (addr == 12'h8) & wr_en;

//Byte Strobe Logic
wire [31:0] valid_wdata_tdr0;
wire [31:0] valid_wdata_tdr1;

assign valid_wdata_tdr0[7:0]   = (tim_pstrb[0]) ? wdata[7:0]   : tdr0_out[7:0];
assign valid_wdata_tdr0[15:8]  = (tim_pstrb[1]) ? wdata[15:8]  : tdr0_out[15:8];
assign valid_wdata_tdr0[23:16] = (tim_pstrb[2]) ? wdata[23:16] : tdr0_out[23:16];
assign valid_wdata_tdr0[31:24] = (tim_pstrb[3]) ? wdata[31:24] : tdr0_out[31:24];

assign valid_wdata_tdr1[7:0]   = (tim_pstrb[0]) ? wdata[7:0]   : tdr1_out[7:0];
assign valid_wdata_tdr1[15:8]  = (tim_pstrb[1]) ? wdata[15:8]  : tdr1_out[15:8];
assign valid_wdata_tdr1[23:16] = (tim_pstrb[2]) ? wdata[23:16] : tdr1_out[23:16];
assign valid_wdata_tdr1[31:24] = (tim_pstrb[3]) ? wdata[31:24] : tdr1_out[31:24];


always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tdr0_out         <= 32'h0;
        tdr0_load_latch  <= 32'h0;
        tdr1_out         <= 32'h0;
        tdr1_load_latch  <= 32'h0;
    end else if (timer_en_fall) begin
        tdr0_out         <= 32'h0;
        tdr0_load_latch  <= 32'h0;
        tdr1_out         <= 32'h0;
        tdr1_load_latch  <= 32'h0;
    end else if (tdr0_sel) begin
        // User writes a start value; latch it and hold until counter picks it up
        tdr0_load_latch <= valid_wdata_tdr0;
        tdr0_out        <= valid_wdata_tdr0;
    end else if (tdr1_sel) begin
        tdr1_load_latch <= valid_wdata_tdr1;
        tdr1_out        <= valid_wdata_tdr1;
    end else if (timer_en && !halt_ack) begin
        tdr0_out <= count[31:0];
        tdr1_out <= count[63:32];
    end
end

// load_en: allows counter to accept register value whenever either TDR is written
assign load_en = tdr0_sel | tdr1_sel;
assign load_val = {(tdr1_sel ? valid_wdata_tdr1 : tdr1_load_latch), (tdr0_sel ? valid_wdata_tdr0 : tdr0_load_latch)};


//------------------------------------
// TIMER COMPARE REGISTER 0 & 1 (0xC & 0x10)
//------------------------------------
wire        tcmp0_sel = (addr == 12'hC) & wr_en;
wire        tcmp1_sel = (addr == 12'h10) & wr_en;
reg  [31:0] tcmp0_out;
reg  [31:0] tcmp1_out;

//Byte Strobe Logic
wire [31:0] valid_wdata_tcmp0;
wire [31:0] valid_wdata_tcmp1;

assign valid_wdata_tcmp0[7:0]   = (tim_pstrb[0]) ? wdata[7:0]   : tcmp0_out[7:0];
assign valid_wdata_tcmp0[15:8]  = (tim_pstrb[1]) ? wdata[15:8]  : tcmp0_out[15:8];
assign valid_wdata_tcmp0[23:16] = (tim_pstrb[2]) ? wdata[23:16] : tcmp0_out[23:16];
assign valid_wdata_tcmp0[31:24] = (tim_pstrb[3]) ? wdata[31:24] : tcmp0_out[31:24];

assign valid_wdata_tcmp1[7:0]   = (tim_pstrb[0]) ? wdata[7:0]   : tcmp1_out[7:0];
assign valid_wdata_tcmp1[15:8]  = (tim_pstrb[1]) ? wdata[15:8]  : tcmp1_out[15:8];
assign valid_wdata_tcmp1[23:16] = (tim_pstrb[2]) ? wdata[23:16] : tcmp1_out[23:16];
assign valid_wdata_tcmp1[31:24] = (tim_pstrb[3]) ? wdata[31:24] : tcmp1_out[31:24];

wire [31:0] tcmp0_pre = (tcmp0_sel) ? valid_wdata_tcmp0 : tcmp0_out;
wire [31:0] tcmp1_pre = (tcmp1_sel) ? valid_wdata_tcmp1 : tcmp1_out;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tcmp0_out <= 32'hFFFF_FFFF;
        tcmp1_out <= 32'hFFFF_FFFF;
    end else begin
        tcmp0_out <= tcmp0_pre;
        tcmp1_out <= tcmp1_pre;
    end
end

assign comp_val = {tcmp1_out, tcmp0_out};


//------------------------------------
// TIMER INTERRUPT ENABLE REGISTER (0x14)
//------------------------------------

wire        tier_sel = (addr == 12'h14) & wr_en;
reg  [31:0] tier_out;

//Byte Strobe Logic
wire [31:0] valid_wdata_tier;

assign valid_wdata_tier[7:0]   = (tim_pstrb[0]) ? wdata[7:0]   : tier_out[7:0];
assign valid_wdata_tier[15:8]  = (tim_pstrb[1]) ? wdata[15:8]  : tier_out[15:8];
assign valid_wdata_tier[23:16] = (tim_pstrb[2]) ? wdata[23:16] : tier_out[23:16];
assign valid_wdata_tier[31:24] = (tim_pstrb[3]) ? wdata[31:24] : tier_out[31:24];

wire [31:0] tier_pre = (tier_sel) ? {31'h0, valid_wdata_tier[0]} : tier_out;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) tier_out <= 32'h0;
    else            tier_out <= tier_pre;
end

//------------------------------------
// TIMER INTERRUPT STATUS REGISTER (0x18)
//------------------------------------

wire tisr_sel = (addr == 12'h18) & wr_en;
reg  int_st_out_pre;
wire [31:0] tisr_out;
wire clear_cond = tisr_sel & tim_pstrb[0] && wdata[0]; //Write 1 to clear logic
wire set_cond   = int_st;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) int_st_out_pre <= 1'b0;
    else begin
        if      (clear_cond) int_st_out_pre <= 1'b0;
        else if (set_cond)   int_st_out_pre <= 1'b1;
    end
end

assign tisr_out = {31'h0, int_st_out_pre};
assign tim_int  = int_st_out_pre & tier_out[0];


//------------------------------------
// TIMER HALT CONTROL STATUS REGISTER (0x1C)
//------------------------------------

wire thcsr_sel = (addr == 12'h1C) & wr_en;
reg  halt_req_reg;
wire [31:0] thcsr_out;

//Byte Strobe Logic
wire [31:0] valid_wdata_thcsr;

assign valid_wdata_thcsr[7:0]   = (tim_pstrb[0]) ? wdata[7:0]   : thcsr_out[7:0];
assign valid_wdata_thcsr[15:8]  = (tim_pstrb[1]) ? wdata[15:8]  : thcsr_out[15:8];
assign valid_wdata_thcsr[23:16] = (tim_pstrb[2]) ? wdata[23:16] : thcsr_out[23:16];
assign valid_wdata_thcsr[31:24] = (tim_pstrb[3]) ? wdata[31:24] : thcsr_out[31:24];


always @(posedge sys_clk or negedge sys_rst_n) begin
    if      (!sys_rst_n) halt_req_reg <= 1'b0;
    else if (thcsr_sel)  halt_req_reg <= valid_wdata_thcsr[0];
end

assign halt_ack  = halt_req_reg & dbg_mode;
assign thcsr_out = {30'h0, halt_ack, halt_req_reg};

//------------
// READ LOGIC
//------------

reg [31:0] rdata_pre;
assign     rdata = (rd_en) ? rdata_pre : 32'h0;

always @(*) begin
    case(addr)
        12'h0:   rdata_pre = tcr_out;
        12'h4:   rdata_pre = count[31:0];
        12'h8:   rdata_pre = count[63:32];
        12'hC:   rdata_pre = tcmp0_out;
        12'h10:  rdata_pre = tcmp1_out;
        12'h14:  rdata_pre = tier_out;
        12'h18:  rdata_pre = tisr_out;
        12'h1C:  rdata_pre = thcsr_out;
        default: rdata_pre = 32'h0;
    endcase
end

endmodule
