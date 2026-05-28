module canvas_ram(
    // Port A: VGA read (25MHz domain)
    input           clk_a,
    input  [9:0]    addr_a,
    output [3:0]    dout_a,
    // Port B: draw write / matcher read (100MHz domain)
    input           clk_b,
    input  [9:0]    addr_b,
    input  [3:0]    din_b,
    input           we_b,
    output [3:0]    dout_b
);

    reg [3:0] mem [0:783];

    reg [3:0] dout_a_reg;
    reg [3:0] dout_b_reg;

    always @(posedge clk_a)
        dout_a_reg <= mem[addr_a];

    always @(posedge clk_b) begin
        if (we_b)
            mem[addr_b] <= din_b;
        dout_b_reg <= mem[addr_b];
    end

    assign dout_a = dout_a_reg;
    assign dout_b = dout_b_reg;

endmodule
