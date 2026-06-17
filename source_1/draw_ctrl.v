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

    // Next cursor position after this tick
    wire [4:0] next_x = move_l ? (cursor_x - 5'd1) :
                         move_r ? (cursor_x + 5'd1) : cursor_x;
    wire [4:0] next_y = move_u ? (cursor_y - 5'd1) :
                         move_d ? (cursor_y + 5'd1) : cursor_y;

    // 3x3 brush writer. The canvas RAM accepts one write per 100MHz cycle,
    // so one pen stroke is emitted over up to nine fast cycles.
    reg       brush_active;
    reg [3:0] brush_idx;
    reg [4:0] brush_cx, brush_cy;

    reg       brush_valid;
    reg [4:0] brush_x, brush_y;

    always @(*) begin
        brush_valid = 1'b1;
        brush_x = brush_cx;
        brush_y = brush_cy;

        case (brush_idx)
            4'd0: begin // -1, -1
                brush_valid = (brush_cx > 5'd0) && (brush_cy > 5'd0);
                brush_x = brush_cx - 5'd1;
                brush_y = brush_cy - 5'd1;
            end
            4'd1: begin //  0, -1
                brush_valid = (brush_cy > 5'd0);
                brush_y = brush_cy - 5'd1;
            end
            4'd2: begin // +1, -1
                brush_valid = (brush_cx < GRID_MAX) && (brush_cy > 5'd0);
                brush_x = brush_cx + 5'd1;
                brush_y = brush_cy - 5'd1;
            end
            4'd3: begin // -1,  0
                brush_valid = (brush_cx > 5'd0);
                brush_x = brush_cx - 5'd1;
            end
            4'd4: begin //  0,  0
                brush_valid = 1'b1;
            end
            4'd5: begin // +1,  0
                brush_valid = (brush_cx < GRID_MAX);
                brush_x = brush_cx + 5'd1;
            end
            4'd6: begin // -1, +1
                brush_valid = (brush_cx > 5'd0) && (brush_cy < GRID_MAX);
                brush_x = brush_cx - 5'd1;
                brush_y = brush_cy + 5'd1;
            end
            4'd7: begin //  0, +1
                brush_valid = (brush_cy < GRID_MAX);
                brush_y = brush_cy + 5'd1;
            end
            4'd8: begin // +1, +1
                brush_valid = (brush_cx < GRID_MAX) && (brush_cy < GRID_MAX);
                brush_x = brush_cx + 5'd1;
                brush_y = brush_cy + 5'd1;
            end
            default: begin
                brush_valid = 1'b0;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            cursor_x  <= 5'd14;
            cursor_y  <= 5'd14;
            pen_down  <= 1'b0;
            grid_we   <= 1'b0;
            grid_addr <= 10'd0;
            grid_din  <= 4'd0;
            brush_active <= 1'b0;
            brush_idx    <= 4'd0;
            brush_cx     <= 5'd14;
            brush_cy     <= 5'd14;
        end else begin
            grid_we <= 1'b0;  // default: no write

            if (pen_toggle)
                pen_down <= ~pen_down;

            if (clear) begin
                cursor_x <= 5'd14;
                cursor_y <= 5'd14;
                pen_down <= 1'b0;
                brush_active <= 1'b0;
                brush_idx <= 4'd0;
            end else if (brush_active) begin
                if (brush_valid) begin
                    grid_we   <= 1'b1;
                    grid_addr <= {5'd0, brush_y} * 10'd28 + {5'd0, brush_x};
                    grid_din  <= 4'hF;
                end

                if (brush_idx == 4'd8) begin
                    brush_active <= 1'b0;
                    brush_idx <= 4'd0;
                end else begin
                    brush_idx <= brush_idx + 4'd1;
                end
            end else if (tick) begin
                // Move cursor (clamped at edges)
                if (move_l) cursor_x <= cursor_x - 5'd1;
                if (move_r) cursor_x <= cursor_x + 5'd1;
                if (move_u) cursor_y <= cursor_y - 5'd1;
                if (move_d) cursor_y <= cursor_y + 5'd1;

                // Start a 3x3 brush stroke centered at the new (or current)
                // cursor position when pen is down.
                if (pen_down) begin
                    brush_active <= 1'b1;
                    brush_idx <= 4'd0;
                    brush_cx <= next_x;
                    brush_cy <= next_y;
                end
            end
        end
    end

endmodule
