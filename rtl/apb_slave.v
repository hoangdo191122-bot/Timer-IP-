module apb_slave #(
    parameter IDLE   = 2'b00,
    parameter SETUP  = 2'b01,
    parameter ACCESS = 2'b10
)(
    input wire          sys_clk,
    input wire          sys_rst_n,
    input wire          tim_psel,
    input wire          tim_pwrite,
    input wire          tim_penable,
    input wire [11:0]   tim_paddr,
    input wire [31:0]   tim_pwdata,
    input wire [31:0]   rdata,
    input wire          slverr,

    output wire [31:0]  tim_prdata,
    output wire         tim_pready,
    output wire         tim_pslverr,
    output reg          wr_en,
    output reg          rd_en,
    output reg [11:0]   addr,
    output reg [31:0]   wdata
);

//FSM Next State Logic
reg [1:0] next_state;
reg [1:0] state;
reg [1:0] wait_cnt; //To implement a 2-cycle wait state after SETUP

always @(*) begin
    case(state)
        IDLE:    next_state = (tim_psel && !tim_penable) ? SETUP  : IDLE;
        SETUP:   next_state = (tim_psel && tim_penable)  ? ACCESS : IDLE;
        ACCESS:  next_state = (tim_pready)               ? IDLE   : ACCESS;
        default: next_state = IDLE;
    endcase
end

//Flip Flop for state transition
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state    <= IDLE;
        wait_cnt <= 2'd0;
    end else begin
        state <= next_state;

        //increment counter while in ACCESS until tim_pready goes High
        if (state == ACCESS && !tim_pready) begin
            wait_cnt <= wait_cnt + 2'd1;
        end else begin
            wait_cnt <= 2'd0;
        end
    end
end

assign tim_pready = (state == ACCESS) && (wait_cnt == 2'd1);

//Slave Error Logic
assign tim_pslverr = (state == ACCESS) && slverr;

//Output FSM
always @(*) begin
    wr_en = 0;
    rd_en = 0;
    addr  = tim_paddr;
    wdata = 32'h0;

    if (state == ACCESS) begin
        if (tim_pwrite) begin
            if (tim_pready) begin
                wr_en = 1'b1;
                wdata = tim_pwdata;
            end
        end else begin
            rd_en = 1'b1;
        end
    end
end

assign tim_prdata = (state == ACCESS && !tim_pwrite) ? rdata : 32'h0;

endmodule
