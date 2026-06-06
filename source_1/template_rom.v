module template_rom (
    input           clk,
    input  [9:0]    addr,       // cell address 0..783
    output [39:0]   data        // {t9[3:0], t8[3:0], ..., t0[3:0]}
);

    reg [39:0] mem [0:783];
    reg [39:0] data_reg;

    // Vivado resolves $readmemh relative to the project directory (.xpr location).
    // Copy templates.hex to D:/Vivado_Projects/Digital/ or adjust path as needed.
    initial begin
        $readmemh("D:/VSCode/MNIST/templates.hex", mem);
    end

    always @(posedge clk)
        data_reg <= mem[addr];

    assign data = data_reg;

endmodule