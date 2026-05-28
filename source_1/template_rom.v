module template_rom (
    input           clk,
    input  [9:0]    addr,       // cell address 0..783
    output [39:0]   data        // {t9[3:0], t8[3:0], ..., t0[3:0]}
);

    reg [39:0] mem [0:783];
    reg [39:0] data_reg;

    initial begin
        $readmemh("templates.hex", mem);
    end

    always @(posedge clk)
        data_reg <= mem[addr];

    assign data = data_reg;

endmodule