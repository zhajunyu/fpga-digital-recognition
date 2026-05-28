module top (
    input           clk,            // 100MHz system clock
    input           rst,            // active-high reset
    input  [6:0]    SW,            // SW[3:0]=dir, SW[6:4]=pen/recog/clear (posedge)
    input  [3:0]    btn_row,       // button matrix row inputs
    output [3:0]    btn_col,       // button matrix column outputs
    output          seg_data,      // SEGDT  — 7-segment serial data
    output          seg_clk,       // SEGCLK — 7-segment shift clock
    output          seg_clr,       // SEGCLR — 7-segment active-low clear
    output          seg_en,        // SEGEN  — 7-segment latch enable
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
    wire        fsm_matcher_start;
    wire        fsm_matching;
    wire        fsm_clearing;
    wire        fsm_clear_we;
    wire [9:0]  fsm_clear_addr;
    wire [3:0]  fsm_result_digit;
    wire        fsm_result_valid;

    recognizer_fsm fsm_inst (
        .clk          (clk),
        .rst          (rst),
        .recog_btn    (sw5_posedge),
        .clear_btn    (sw6_posedge),
        .matcher_done (matcher_done),
        .matcher_digit(matcher_best),
        .freeze       (fsm_freeze),
        .matcher_start(fsm_matcher_start),
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
    // Port B: 100MHz — muxed between draw / matcher / clearing
    wire [9:0]  canvas_addr_a;
    wire [3:0]  canvas_dout_a;
    wire        canvas_we_b;
    wire [9:0]  canvas_addr_b;
    wire [3:0]  canvas_din_b;
    wire [3:0]  canvas_dout_b;

    // Port B arbitration
    assign canvas_we_b   = (~fsm_freeze && draw_grid_we) || fsm_clear_we;
    assign canvas_addr_b = fsm_clearing  ? fsm_clear_addr   :
                           fsm_matching  ? matcher_canv_addr : draw_grid_addr;
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

    // ── Template ROM ───────────────────────────────────────────────
    wire [9:0]  tmpl_addr;
    wire [39:0] tmpl_data;

    template_rom tmpl_inst (
        .clk (clk),
        .addr(tmpl_addr),
        .data(tmpl_data)
    );

    // ── Matcher (SAD engine) ───────────────────────────────────────
    wire        matcher_done;
    wire [3:0]  matcher_best;
    wire [9:0]  matcher_canv_addr;

    matcher matcher_inst (
        .clk           (clk),
        .rst           (rst),
        .start         (fsm_matcher_start),
        .canvas_data   (canvas_dout_b),
        .template_data (tmpl_data),
        .canvas_addr   (matcher_canv_addr),
        .template_addr (tmpl_addr),
        .done          (matcher_done),
        .best_digit    (matcher_best)
    );

    // ── 7-Segment display driver ───────────────────────────────────
    seg7_driver seg7_inst (
        .clk     (clk),
        .rst     (rst),
        .digit   (fsm_result_digit),
        .valid   (fsm_result_valid),
        .seg_data(seg_data),
        .seg_clk (seg_clk),
        .seg_clr (seg_clr),
        .seg_en  (seg_en)
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
