module counter (
    input wire          sys_clk,
    input wire          sys_rst_n,
    input wire [63:0]   comp_val,
    input wire          timer_en,
    input wire          div_en,
    input wire [3:0]    div_val,
    input wire          halt_ack,
    input wire [63:0]   load_val,
    input wire          load_en,

    output wire [63:0]  count,
    output wire         int_st
);

reg [7:0] div_max;

always @(*) begin
    case(div_val)
        4'b0000: div_max = 8'd0;
        4'b0001: div_max = 8'd1;
        4'b0010: div_max = 8'd3;
        4'b0011: div_max = 8'd7;
        4'b0100: div_max = 8'd15;
        4'b0101: div_max = 8'd31;
        4'b0110: div_max = 8'd63;
        4'b0111: div_max = 8'd127;
        4'b1000: div_max = 8'd255;
        default: div_max = 8'd0;
    endcase
end

//Clock Tick Enable Logic
reg [7:0] prescaler_cnt;
wire      tick = (!div_en) || (prescaler_cnt == div_max);

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        prescaler_cnt <= 8'd0;
    end else if (load_en) begin
        // Reset prescaler when user loads a new start value
        prescaler_cnt <= 8'd0;
    end else if (timer_en && !halt_ack) begin
        if (tick) begin
            prescaler_cnt <= 8'd0;
        end else begin
            prescaler_cnt <= prescaler_cnt + 1'b1;
        end
    end else if (!timer_en) begin
        prescaler_cnt <= 8'd0;
    end
end

//Counter Logic
reg [63:0] count_reg;
assign     count = count_reg;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        count_reg <= 64'd0;
    end else if (load_en || !timer_en) begin
        count_reg <= load_val;
    end if (timer_en && !halt_ack && !load_en) begin
        if (tick) begin
            count_reg <= count_reg + 1'b1;
        end
    end
    // if timer_en low: hold current value (latch)
end

assign int_st = (count_reg == comp_val);

endmodule
