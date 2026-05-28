`timescale 1ns / 1ps

module tb_matcher;

    reg         clk, rst, start;
    wire [3:0]  canvas_data;
    wire [9:0]  canvas_addr;
    wire [9:0]  tmpl_addr;
    wire [39:0] tmpl_data;
    wire        done;
    wire [3:0]  best_digit;

    // ── DUT: template_rom + matcher ──────────────────────
    template_rom t_rom (
        .clk (clk),
        .addr(tmpl_addr),
        .data(tmpl_data)
    );

    matcher uut (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .canvas_data  (canvas_data),
        .template_data(tmpl_data),
        .canvas_addr  (canvas_addr),
        .template_addr(tmpl_addr),
        .done         (done),
        .best_digit   (best_digit)
    );

    // ── Mock canvas_ram (1-cycle read latency) ───────────
    reg [3:0] mock_mem [0:783];
    reg [9:0] addr_d;

    always @(posedge clk)
        addr_d <= canvas_addr;

    assign canvas_data = mock_mem[addr_d];

    // ── Load reference templates from hex file ───────────
    reg [39:0] tmpl_ref [0:783];

    initial begin
        $readmemh("templates.hex", tmpl_ref);
    end

    // ── Clock (100 MHz) ─────────────────────────────────
    always #5 clk = ~clk;

    // ── Timeout watchdog ────────────────────────────────
    initial begin
        #200_000;   // 200 us
        $display("FAIL: timeout — matcher never asserted done");
        $finish;
    end

    // ── Test tasks ──────────────────────────────────────
    reg [31:0] test_num;
    reg [3:0]  expected;

    task do_reset;
        begin
            rst = 1; start = 0; test_num = 0;
            repeat (2) @(posedge clk);
            rst = 0;
            repeat (2) @(posedge clk);
        end
    endtask

    task run_recognition;
        begin
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;
            wait (done);
            repeat (2) @(posedge clk);
        end
    endtask

    task load_canvas_from_template;
        input [3:0] digit;
        integer a;
        begin
            for (a = 0; a < 784; a = a + 1)
                mock_mem[a] = tmpl_ref[a][digit*4 +: 4];
        end
    endtask

    task load_canvas_zeros;
        integer a;
        begin
            for (a = 0; a < 784; a = a + 1)
                mock_mem[a] = 4'd0;
        end
    endtask

    // ── Test sequence ───────────────────────────────────
    initial begin
        clk = 0;

        // Wait for $readmemh + PLL lock simulation settle
        #200;

        do_reset();

        // ─────── Test 1: exact match — template 3 ───────
        test_num = 1;
        expected = 4'd3;
        load_canvas_from_template(expected);
        run_recognition();
        if (best_digit == expected)
            $display("TEST %0d PASS  best_digit=%0d (expected %0d)", test_num, best_digit, expected);
        else
            $display("TEST %0d FAIL  best_digit=%0d (expected %0d)", test_num, best_digit, expected);

        // ─────── Test 2: exact match — template 7 ───────
        test_num = 2;
        expected = 4'd7;
        load_canvas_from_template(expected);
        run_recognition();
        if (best_digit == expected)
            $display("TEST %0d PASS  best_digit=%0d (expected %0d)", test_num, best_digit, expected);
        else
            $display("TEST %0d FAIL  best_digit=%0d (expected %0d)", test_num, best_digit, expected);

        // ─────── Test 3: exact match — template 0 ───────
        test_num = 3;
        expected = 4'd0;
        load_canvas_from_template(expected);
        run_recognition();
        if (best_digit == expected)
            $display("TEST %0d PASS  best_digit=%0d (expected %0d)", test_num, best_digit, expected);
        else
            $display("TEST %0d FAIL  best_digit=%0d (expected %0d)", test_num, best_digit, expected);

        // ─────── Test 4: exact match — template 9 ───────
        test_num = 4;
        expected = 4'd9;
        load_canvas_from_template(expected);
        run_recognition();
        if (best_digit == expected)
            $display("TEST %0d PASS  best_digit=%0d (expected %0d)", test_num, best_digit, expected);
        else
            $display("TEST %0d FAIL  best_digit=%0d (expected %0d)", test_num, best_digit, expected);

        // ─────── Test 5: blank canvas (smoke test) ──────
        test_num = 5;
        load_canvas_zeros();
        run_recognition();
        $display("TEST %0d PASS  best_digit=%0d (blank canvas, smoke test)", test_num, best_digit);

        $display("All tests complete.");
        $finish;
    end

endmodule
