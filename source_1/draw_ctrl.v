module draw_ctrl (
    input           clk,            // 100MHz
    input           rst,
    input           tick,           // ~24Hz movement tick (e.g. clkdiv bit 22)
    input  [3:0]    dir,            // {down, up, right, left} — active high
    input           pen_toggle,     // single-cycle edge pulse: flip pen state
    input           clear,          // single-cycle edge pulse: reset cursor + pen
    output reg [4:0] cursor_x,      // 0..27
    output reg [4:0] cursor_y,      // 0..27
    output reg       pen_down,      // 1 = drawing
    output reg [9:0] grid_addr,     // canvas_ram write address
    output reg [3:0] grid_din,      // canvas_ram write data
    output reg       grid_we        // canvas_ram write enable
);

    localparam GRID_MAX = 5'd27;

    // Direction-qualified move flags (clamped at grid edges)
    wire move_l = dir[0] && cursor_x > 5'd0;
    wire move_r = dir[1] && cursor_x < GRID_MAX;
    wire move_u = dir[2] && cursor_y > 5'd0;
    wire move_d = dir[3] && cursor_y < GRID_MAX;

    wire moving = move_l || move_r || move_u || move_d;

    // Next cursor position after this tick
    wire [4:0] next_x = move_l ? (cursor_x - 5'd1) :
                         move_r ? (cursor_x + 5'd1) : cursor_x;
    wire [4:0] next_y = move_u ? (cursor_y - 5'd1) :
                         move_d ? (cursor_y + 5'd1) : cursor_y;

    always @(posedge clk) begin
        if (rst) begin
            cursor_x  <= 5'd14;
            cursor_y  <= 5'd14;
            pen_down  <= 1'b0;
            grid_we   <= 1'b0;
            grid_addr <= 10'd0;
            grid_din  <= 4'd0;
        end else begin
            grid_we <= 1'b0;  // default: no write

            if (pen_toggle)
                pen_down <= ~pen_down;

            if (clear) begin
                cursor_x <= 5'd14;
                cursor_y <= 5'd14;
                pen_down <= 1'b0;
            end

            if (tick) begin
                // Move cursor (clamped at edges)
                if (move_l) cursor_x <= cursor_x - 5'd1;
                if (move_r) cursor_x <= cursor_x + 5'd1;
                if (move_u) cursor_y <= cursor_y - 5'd1;
                if (move_d) cursor_y <= cursor_y + 5'd1;

                // Write cell at the new (or current) position when pen is down.
                // next_x / next_y already reflect where the cursor will land,
                // or the current cell if no direction is pressed.
                if (pen_down) begin
                    grid_we   <= 1'b1;
                    grid_addr <= {5'd0, next_y} * 10'd28 + {5'd0, next_x};
                    grid_din  <= 4'hF;
                end
            end
        end
    end

endmodule
