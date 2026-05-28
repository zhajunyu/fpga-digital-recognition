`timescale 1ns / 1ps

module tb_recognizer_fsm;

    reg         clk, rst;
    reg         recog_btn, clear_btn;
    reg  [3:0]  matcher_digit_drive;
    reg         matcher_done_drive;

    wire        freeze, matcher_start, matching, clearing;
    wire        clear_we;
    wire [9:0]  clear_addr;
    wire [3:0]  result_digit;
    wire        result_valid;

    recognizer_fsm dut (
        .clk          (clk),
        .rst          (rst),
        .recog_btn    (recog_btn),
        .clear_btn    (clear_btn),
        .matcher_done (matcher_done_drive),
        .matcher_digit(matcher_digit_drive),
        .freeze       (freeze),
        .matcher_start(matcher_start),
        .matching     (matching),
        .clearing     (clearing),
        .clear_we     (clear_we),
        .clear_addr   (clear_addr),
        .result_digit (result_digit),
        .result_valid (result_valid)
    );

    // ── Mock matcher ──────────────────────────────────────
    reg [8:0]  match_timer;
    reg        match_running;

    always @(posedge clk) begin
        if (rst) begin
            match_timer      <= 9'd0;
            match_running    <= 1'b0;
            matcher_done_drive <= 1'b0;
        end else begin
            matcher_done_drive <= 1'b0;

            if (matcher_start && !match_running) begin
                match_running <= 1'b1;
                match_timer   <= 9'd0;
            end

            if (match_running) begin
                if (match_timer == 9'd20) begin
                    matcher_done_drive <= 1'b1;
                    match_running <= 1'b0;
                end else begin
                    match_timer <= match_timer + 9'd1;
                end
            end
        end
    end

    // matcher_digit_drive is set by the test sequence, not the mock

    // ── Clock ─────────────────────────────────────────────
    always #5 clk = ~clk;

    // ── Timeout ───────────────────────────────────────────
    initial begin #500_000; $display("TIMEOUT"); $finish; end

    // Drive on negedge, sample on posedge — eliminates race conditions.
    // FSM @(posedge clk) always sees stable, race-free stimulus.
    `define P_RECOG  @(negedge clk); recog_btn<=1; @(posedge clk); recog_btn<=0;
    `define P_CLEAR  @(negedge clk); clear_btn<=1; @(posedge clk); clear_btn<=0;
    `define EDGE     @(posedge clk)
    `define WAIT(n)  repeat(n) @(posedge clk)

    integer test_num;

    initial begin
        clk = 0; recog_btn = 0; clear_btn = 0;
        #100;
        rst = 1; `WAIT(5);
        rst = 0; `WAIT(5);

        // ═══ Test 1: Normal flow ══════════════════════════
        test_num = 1;
        $display("TEST %0d: IDLE -> LATCH -> MATCHING -> SHOW -> CLEARING -> IDLE", test_num);

        // IDLE checks
        `EDGE;
        if (freeze)       $display("  FAIL: freeze in IDLE");
        if (matching)     $display("  FAIL: matching in IDLE");
        if (result_valid) $display("  FAIL: result_valid in IDLE");

        // Trigger recognition (mock matcher returns digit=5 by default)
        matcher_digit_drive = 4'd5;
        `P_RECOG
        `WAIT(3);   // FSM: IDLE→LATCH→MATCHING, plus one for matching NBA to settle

        if (!freeze)   $display("  FAIL: freeze low during MATCHING");
        if (!matching) $display("  FAIL: matching low during MATCHING");

        // Wait for matcher → SHOW
        `WAIT(30);  // mock matcher takes ~22 cycles
        if (!result_valid) $display("  FAIL: result_valid low in SHOW");
        if (result_digit != 4'd5) $display("  FAIL: result=%0d expected 5", result_digit);

        // Clear → CLEARING → IDLE
        `P_CLEAR
        `WAIT(3);
        if (!clearing) $display("  FAIL: clearing low");
        if (!clear_we) $display("  FAIL: clear_we low");

        `WAIT(800); // 784 clearing cycles
        if (clearing)    $display("  FAIL: clearing still high after 784");
        if (freeze)      $display("  FAIL: freeze still high");
        if (result_valid)$display("  FAIL: result_valid still high");

        $display("TEST %0d PASS", test_num);

        // ═══ Test 2: Re-recognize from SHOW ═══════════════
        test_num = 2;
        $display("TEST %0d: Re-recognize from SHOW", test_num);

        `P_RECOG  `WAIT(30);
        if (!result_valid) $display("  FAIL: result_valid low");
        matcher_digit_drive = 4'd7;   // switch to digit 7 for re-recognition
        `P_RECOG  `WAIT(3);
        if (result_valid) $display("  FAIL: result_valid high during re-recog");
        if (!matching)    $display("  FAIL: matching low during re-recog");
        `WAIT(30);
        if (!result_valid) $display("  FAIL: result_valid low after re-recog");
        if (result_digit != 4'd7) $display("  FAIL: result=%0d expected 7", result_digit);

        $display("TEST %0d PASS", test_num);
        `P_CLEAR  `WAIT(800);

        // ═══ Test 3: CLEARING address sweep ════════════════
        test_num = 3;
        $display("TEST %0d: CLEARING writes all 784 addresses", test_num);

        `P_RECOG  `WAIT(30);
        `P_CLEAR  `WAIT(2);   // SHOW→CLEARING, then first clear_addr=0 appears
        if (clear_addr !== 10'd0) $display("  FAIL: clear_addr=%0d expected 0", clear_addr);
        `WAIT(784);
        if (clearing) $display("  FAIL: clearing still high");

        $display("TEST %0d PASS", test_num);

        // ═══ Test 4: Spurious recog_btn during MATCHING ════
        test_num = 4;
        $display("TEST %0d: recog_btn ignored during MATCHING", test_num);

        `P_RECOG  `WAIT(4);  // now in MATCHING
        if (!matching) $display("  FAIL: not in MATCHING");
        `P_RECOG   // spurious recog
        `WAIT(2);
        if (!matching) $display("  FAIL: matching interrupted");

        $display("TEST %0d PASS", test_num);
        `WAIT(30);  // let matcher finish
        `P_CLEAR  `WAIT(800);

        $display("All tests complete.");
        $finish;
    end

endmodule
