module vga_render (
    input               clk,          // 25MHz VGA pixel clock
    input               rst,
    input      [8:0]    row,          // VGA row (0-479)
    input      [9:0]    col,          // VGA col (0-639)
    input      [3:0]    canvas_data,  // data from canvas_ram
    input      [4:0]    cursor_x,     // cursor grid column (0-27)
    input      [4:0]    cursor_y,     // cursor grid row (0-27)
    input               pen_down,     // 1 = pen down (green cursor), 0 = pen up (red)
    output reg [9:0]    canvas_addr,  // address to canvas_ram
    output reg [11:0]   pixel_data    // 12-bit RGB444 output
);

    localparam OFFSET_X = 10'd180;
    localparam OFFSET_Y =  9'd100;
    localparam CELL_SZ  =  4'd10;
    localparam GRID_W   = 10'd280;
    localparam GRID_H   =  9'd280;

    // Stage 1: combinational cell-coordinate computation
    wire [9:0] s1_grid_col = col - OFFSET_X;
    wire [8:0] s1_grid_row = row - OFFSET_Y;
    wire s1_in_grid = (col >= OFFSET_X) && (col < OFFSET_X + GRID_W) &&
                      (row >= OFFSET_Y) && (row < OFFSET_Y + GRID_H);

    wire [4:0] s1_cell_x = s1_grid_col / CELL_SZ;
    wire [4:0] s1_cell_y = s1_grid_row / CELL_SZ;
    wire [3:0] s1_sub_x  = s1_grid_col % CELL_SZ;
    wire [3:0] s1_sub_y  = s1_grid_row % CELL_SZ;

    // Pipeline registers between stage 1 and stage 2
    reg         s2_in_grid;
    reg  [3:0]  s2_sub_x, s2_sub_y;
    reg  [4:0]  s2_cell_x, s2_cell_y;
    reg  [4:0]  s2_cursor_x, s2_cursor_y;
    reg         s2_pen_down;

    // Stage 1: latch address for canvas_ram and pipeline intermediate values
    always @(posedge clk) begin
        if (rst) begin
            canvas_addr  <= 10'd0;
            s2_in_grid   <= 1'b0;
            s2_sub_x     <= 4'd0;
            s2_sub_y     <= 4'd0;
            s2_cell_x    <= 5'd0;
            s2_cell_y    <= 5'd0;
            s2_cursor_x  <= 5'd0;
            s2_cursor_y  <= 5'd0;
            s2_pen_down  <= 1'b0;
        end else begin
            if (s1_in_grid)
                canvas_addr <= {5'd0, s1_cell_y} * 10'd28 + {5'd0, s1_cell_x};
            else
                canvas_addr <= 10'd0;

            s2_in_grid  <= s1_in_grid;
            s2_sub_x    <= s1_sub_x;
            s2_sub_y    <= s1_sub_y;
            s2_cell_x   <= s1_cell_x;
            s2_cell_y   <= s1_cell_y;
            s2_cursor_x <= cursor_x;
            s2_cursor_y <= cursor_y;
            s2_pen_down <= pen_down;
        end
    end

    // Stage 2: determine final pixel color from pipelined info + canvas data
    wire s2_is_cursor = (s2_cell_x == s2_cursor_x) && (s2_cell_y == s2_cursor_y);
    wire s2_cursor_edge = s2_is_cursor &&
        (s2_sub_x == 4'd0 || s2_sub_y == 4'd0 ||
         s2_sub_x == 4'd9 || s2_sub_y == 4'd9);

    always @(posedge clk) begin
        if (rst) begin
            pixel_data <= 12'h000;
        end else begin
            if (!s2_in_grid)
                pixel_data <= 12'h333;                                 // dark gray background
            else if (s2_cursor_edge)
                pixel_data <= s2_pen_down ? 12'h0F0 : 12'h00F;        // green : red (BGR format)
            else if (s2_sub_x == 4'd0 || s2_sub_y == 4'd0)
                pixel_data <= 12'h666;                                 // grid line
            else if (canvas_data > 4'd0)
                // Invert: canvas 4'hF (max ink) → black (12'h000), 4'h0 → white
                pixel_data <= {4'hF - canvas_data, 4'hF - canvas_data, 4'hF - canvas_data};
            else
                pixel_data <= 12'hFFF;                                 // white interior
        end
    end

endmodule
