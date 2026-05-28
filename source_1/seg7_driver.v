module seg7_driver (
    input           clk,            // 100MHz
    input           rst,
    input  [3:0]    digit,          // digit to display (0-9)
    input           valid,          // high = digit is valid, low = blank
    output reg      seg_data,       // SEGDT  — serial data (L24)
    output reg      seg_clk,        // SEGCLK — shift clock (M24)
    output reg      seg_clr,        // SEGCLR — active-low clear (M20)
    output reg      seg_en          // SEGEN  — latch enable (R18)
);

    // 7-segment LUT (common anode, active-low): {dp, g, f, e, d, c, b, a}
    function [7:0] seg_encode;
        input [3:0] d;
        begin
            case (d)
                4'd0:    seg_encode = 8'b11000000;
                4'd1:    seg_encode = 8'b11111001;
                4'd2:    seg_encode = 8'b10100100;
                4'd3:    seg_encode = 8'b10110000;
                4'd4:    seg_encode = 8'b10011001;
                4'd5:    seg_encode = 8'b10010010;
                4'd6:    seg_encode = 8'b10000010;
                4'd7:    seg_encode = 8'b11111000;
                4'd8:    seg_encode = 8'b10000000;
                4'd9:    seg_encode = 8'b10010000;
                default: seg_encode = 8'b11111111;  // blank
            endcase
        end
    endfunction

    // Shift out 64 bits: 8 digits × 8 bits. Shift clock ~1MHz (div by 100).
    reg [6:0]  clk_div;
    wire       shift_tick = (clk_div == 7'd99);

    reg [5:0]  bit_cnt;     // 0..63
    reg [63:0] shift_reg;

    always @(posedge clk) begin
        if (rst) begin
            clk_div   <= 7'd0;
            bit_cnt   <= 6'd0;
            shift_reg <= 64'hFFFFFFFFFFFFFFFF;
            seg_data  <= 1'b1;
            seg_clk   <= 1'b0;
            seg_clr   <= 1'b0;   // clear shift registers during reset
            seg_en    <= 1'b0;
        end else begin
            seg_clr <= 1'b1;     // release clear during normal operation

            // ~1MHz tick generator
            if (clk_div == 7'd99)
                clk_div <= 7'd0;
            else
                clk_div <= clk_div + 7'd1;

            if (shift_tick) begin
                // Reload shift register at start of each 64-bit frame
                if (bit_cnt == 6'd0) begin
                    shift_reg[7:0]   <= valid ? seg_encode(digit) : 8'hFF;
                    shift_reg[15:8]  <= 8'hBF;   // dash (placeholder)
                    shift_reg[23:16] <= 8'hFF;   // blank
                    shift_reg[31:24] <= 8'hFF;
                    shift_reg[39:32] <= 8'hFF;
                    shift_reg[47:40] <= 8'hFF;
                    shift_reg[55:48] <= 8'hFF;
                    shift_reg[63:56] <= 8'hFF;
                end

                // Shift out LSB-first (SN74LV164 shifts on rising edge of CLK)
                seg_data <= shift_reg[0];
                seg_clk  <= 1'b1;

                // Latch enable: pulse after the last bit of each frame
                seg_en <= (bit_cnt == 6'd63);

                if (bit_cnt == 6'd63)
                    bit_cnt <= 6'd0;
                else begin
                    shift_reg <= {1'b0, shift_reg[63:1]};
                    bit_cnt <= bit_cnt + 6'd1;
                end

            end else begin
                seg_clk <= 1'b0;
                seg_en  <= 1'b0;
            end
        end
    end

endmodule
