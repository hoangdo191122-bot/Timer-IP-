module timer (
    input  wire          sys_clk,
    input  wire          sys_rst_n,
    input  wire          tim_psel,
    input  wire          tim_pwrite,
    input  wire          tim_penable,
    input  wire [11:0]   tim_paddr,
    input  wire [31:0]   tim_pwdata,
    input  wire [3:0]    tim_pstrb,
    input  wire          dbg_mode,

    output wire [31:0]   tim_prdata,
    output wire          tim_pready,
    output wire          tim_pslverr,
    output wire          tim_int
);

wire          wr_en;
wire          rd_en;
wire [11:0]   addr;
wire [31:0]   wdata;
wire [31:0]   rdata;
wire [63:0]   count;
wire          int_st;
wire          timer_en;
wire          div_en;
wire [3:0]    div_val;
wire          halt_ack;
wire [63:0]   comp_val;
wire [63:0]   load_val;
wire          load_en;
wire          slverr;

register regs (
    .sys_clk    (sys_clk)  ,
    .sys_rst_n  (sys_rst_n),
    .wr_en      (wr_en)    ,
    .rd_en      (rd_en)    ,
    .addr       (addr)     ,
    .wdata      (wdata)    ,
    .count      (count)    ,
    .dbg_mode   (dbg_mode) ,
    .int_st     (int_st)   ,
    .rdata      (rdata)    ,
    .timer_en   (timer_en) ,
    .div_en     (div_en)   ,
    .div_val    (div_val)  ,
    .tim_int    (tim_int)  ,
    .halt_ack   (halt_ack) ,
    .comp_val   (comp_val) ,
    .load_val   (load_val) ,
    .load_en    (load_en)  ,
    .slverr     (slverr)   ,
    .tim_pstrb  (tim_pstrb)
);

counter cnt (
    .sys_clk    (sys_clk)  ,
    .sys_rst_n  (sys_rst_n),
    .comp_val   (comp_val) ,
    .timer_en   (timer_en) ,
    .div_en     (div_en)   ,
    .div_val    (div_val)  ,
    .halt_ack   (halt_ack) ,
    .load_val   (load_val) ,
    .load_en    (load_en)  ,
    .count      (count)    ,
    .int_st     (int_st)
);

apb_slave slave (
    .sys_clk     (sys_clk)   ,
    .sys_rst_n   (sys_rst_n) ,
    .tim_psel    (tim_psel)  ,
    .tim_pwrite  (tim_pwrite),
    .tim_penable (tim_penable),
    .tim_paddr   (tim_paddr) ,
    .tim_pwdata  (tim_pwdata),
    .rdata       (rdata)     ,
    .slverr      (slverr)    ,
    .tim_prdata  (tim_prdata),
    .tim_pready  (tim_pready),
    .tim_pslverr (tim_pslverr),
    .wr_en       (wr_en)     ,
    .rd_en       (rd_en)     ,
    .addr        (addr)      ,
    .wdata       (wdata)
);

endmodule
