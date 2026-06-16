module top (
    input           clk,            // 100MHz system clock
    input           rst,            // active-high reset
    input  [6:0]    SW,            // SW[3:0]=dir, SW[6:4]=pen/recog/clear (posedge)
    input  [3:0]    btn_row,       // button matrix row inputs
    output [3:0]    btn_col,       // button matrix column outputs
    output [3:0]    AN,            // Arduino 7-segment anode select (active-low)
    output [7:0]    Segment,       // Arduino 7-segment {dp,g,f,e,d,c,b,a} (active-low)
    output [3:0]    R, G, B,       // VGA color
    output          HS, VS         // VGA sync
);

    // ── Clock divider ──────────────────────────────────────────────
    wire [31:0] div_res;

    clkdiv clkdiv_inst (
        .clk(clk),
        .rst(rst),
        .div_res(div_res)
    );

    wire clk_25m = div_res[1];    // 25 MHz — VGA pixel clock

    // Rising-edge detect on a slow divider bit — produces one-cycle pulse at ~6 Hz.
    // div_res[24] toggles at 100M / 2^24 ≈ 5.96 Hz (168 ms period).
    // Edge detection prevents the cursor from moving every 10ns while the bit is high.
    reg tick_raw_d;
    always @(posedge clk) tick_raw_d <= div_res[24];
    wire draw_tick_raw = div_res[24] & ~tick_raw_d;    // rising edge, 1 cycle wide

    // ── VGA interface ──────────────────────────────────────────────
    wire [8:0]  vga_row;
    wire [9:0]  vga_col;
    wire [11:0] vga_pixel;

    // ── Button matrix ──────────────────────────────────────────────
    wire [15:0] btn;
    wire [15:0] btn_edge;

    button_matrix btn_inst (
        .clk     (clk),
        .rst     (rst),
        .row_in  (btn_row),
        .col_out (btn_col),
        .btn     (btn),
        .btn_edge(btn_edge)
    );

    // ── SW[6:4] posedge detection (switch flip = one-shot pulse) ────
    reg [6:0] sw_prev;
    always @(posedge clk) sw_prev <= SW;
    wire sw4_posedge = SW[4] & ~sw_prev[4];
    wire sw5_posedge = SW[5] & ~sw_prev[5];
    wire sw6_posedge = SW[6] & ~sw_prev[6];

    // ── Recognition FSM ────────────────────────────────────────────
    wire        fsm_freeze;
    wire        fsm_recognizer_start;
    wire        fsm_matching;
    wire        fsm_clearing;
    wire        fsm_clear_we;
    wire [9:0]  fsm_clear_addr;
    wire [3:0]  fsm_result_digit;
    wire        fsm_result_valid;
    wire        recognizer_done;
    wire [3:0]  recognizer_best;
    wire [9:0]  recognizer_canv_addr;

    recognizer_fsm fsm_inst (
        .clk          (clk),
        .rst          (rst),
        .recog_btn    (sw5_posedge),
        .clear_btn    (sw6_posedge),
        .matcher_done (recognizer_done),
        .matcher_digit(recognizer_best),
        .freeze       (fsm_freeze),
        .matcher_start(fsm_recognizer_start),
        .matching     (fsm_matching),
        .clearing     (fsm_clearing),
        .clear_we     (fsm_clear_we),
        .clear_addr   (fsm_clear_addr),
        .result_digit (fsm_result_digit),
        .result_valid (fsm_result_valid)
    );

    // ── Drawing controller ─────────────────────────────────────────
    wire        draw_tick = draw_tick_raw & ~fsm_freeze;
    wire [4:0]  cursor_x, cursor_y;
    wire        pen_down;
    wire        draw_grid_we;
    wire [9:0]  draw_grid_addr;
    wire [3:0]  draw_grid_din;

    draw_ctrl draw_inst (
        .clk       (clk),
        .rst       (rst),
        .tick      (draw_tick),
        .dir       (SW[3:0]),
        .pen_toggle(sw4_posedge),
        .clear     (sw6_posedge),
        .cursor_x  (cursor_x),
        .cursor_y  (cursor_y),
        .pen_down  (pen_down),
        .grid_addr (draw_grid_addr),
        .grid_din  (draw_grid_din),
        .grid_we   (draw_grid_we)
    );

    // ── Canvas RAM (dual-port BRAM) ────────────────────────────────
    // Port A: 25MHz — VGA rendering reads
    // Port B: 100MHz — muxed between draw / MLP recognizer / clearing
    wire [9:0]  canvas_addr_a;
    wire [3:0]  canvas_dout_a;
    wire        canvas_we_b;
    wire [9:0]  canvas_addr_b;
    wire [3:0]  canvas_din_b;
    wire [3:0]  canvas_dout_b;

    // Port B arbitration
    assign canvas_we_b   = (~fsm_freeze && draw_grid_we) || fsm_clear_we;
    assign canvas_addr_b = fsm_clearing  ? fsm_clear_addr   :
                           fsm_matching  ? recognizer_canv_addr : draw_grid_addr;
    assign canvas_din_b  = fsm_clearing  ? 4'd0             : draw_grid_din;

    canvas_ram canvas_inst (
        .clk_a (clk_25m),
        .addr_a(canvas_addr_a),
        .dout_a(canvas_dout_a),
        .clk_b (clk),
        .addr_b(canvas_addr_b),
        .din_b (canvas_din_b),
        .we_b  (canvas_we_b),
        .dout_b(canvas_dout_b)
    );

    // ── MLP recognizer (784 → 256 → 10 fixed-point inference) ─────
    mlp_engine recognizer_inst (
        .clk        (clk),
        .rst        (rst),
        .start      (fsm_recognizer_start),
        .canvas_data(canvas_dout_b),
        .canvas_addr(recognizer_canv_addr),
        .done       (recognizer_done),
        .best_digit (recognizer_best)
    );

    // ── Arduino 4-digit 7-segment display ──────────────────────────
    DisplayNumber display_inst (
        .clk    (clk),
        .RST    (rst),
        .Hexs   ({12'd0, fsm_result_digit}),
        .Points (4'd0),
        .LES    ({3'b111, ~fsm_result_valid}),  // blank unused digits
        .Segment(Segment),
        .AN     (AN)
    );

    // ── CDC synchronizers: cursor signals 100MHz → 25MHz ──────────
    reg [4:0] cur_x_s1, cur_x_s2;
    reg [4:0] cur_y_s1, cur_y_s2;
    reg       pen_s1, pen_s2;

    always @(posedge clk_25m) begin
        {cur_x_s2, cur_x_s1} <= {cur_x_s1, cursor_x};
        {cur_y_s2, cur_y_s1} <= {cur_y_s1, cursor_y};
        {pen_s2, pen_s1}     <= {pen_s1, pen_down};
    end

    // ── VGA grid renderer ──────────────────────────────────────────
    vga_render render_inst (
        .clk        (clk_25m),
        .rst        (rst),
        .row        (vga_row),
        .col        (vga_col),
        .canvas_data(canvas_dout_a),
        .cursor_x   (cur_x_s2),
        .cursor_y   (cur_y_s2),
        .pen_down   (pen_s2),
        .canvas_addr(canvas_addr_a),
        .pixel_data (vga_pixel)
    );

    // ── VGA timing controller ──────────────────────────────────────
    VGA vga_inst (
        .clk(clk_25m),
        .rst(rst),
        .Din(vga_pixel),
        .row(vga_row),
        .col(vga_col),
        .rdn(),
        .R(R),
        .G(G),
        .B(B),
        .HS(HS),
        .VS(VS)
    );

endmodule
