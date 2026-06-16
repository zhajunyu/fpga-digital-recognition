`timescale 1ns / 1ps

module tb_mlp_engine;

    localparam NUM_VECTORS = 16;
    localparam CELLS       = 784;
    localparam TIMEOUT_CYCLES = 300000;

    reg         clk;
    reg         rst;
    reg         start;
    reg  [3:0]  canvas_data;
    wire [9:0]  canvas_addr;
    wire        done;
    wire [3:0]  best_digit;

    mlp_engine dut (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .canvas_data(canvas_data),
        .canvas_addr(canvas_addr),
        .done       (done),
        .best_digit (best_digit)
    );

    reg [3:0] canvas_mem [0:CELLS-1];
    reg [3:0] vector_mem [0:NUM_VECTORS*CELLS-1];
    reg [3:0] expected_digit [0:NUM_VECTORS-1];

    always #5 clk = ~clk;

    always @(posedge clk) begin
        canvas_data <= canvas_mem[canvas_addr];
    end

    task do_reset;
        begin
            rst = 1'b1;
            start = 1'b0;
            canvas_data = 4'd0;
            repeat (5) @(posedge clk);
            rst = 1'b0;
            repeat (5) @(posedge clk);
        end
    endtask

    task load_vector;
        input integer vector_idx;
        integer i;
        begin
            for (i = 0; i < CELLS; i = i + 1)
                canvas_mem[i] = vector_mem[vector_idx*CELLS + i];
        end
    endtask

    task fill_canvas;
        input [3:0] value;
        integer i;
        begin
            for (i = 0; i < CELLS; i = i + 1)
                canvas_mem[i] = value;
        end
    endtask

    task run_inference;
        integer cycles;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            cycles = 0;
            while (!done && cycles < TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (!done) begin
                $display("FAIL: timeout waiting for mlp_engine done");
                $finish;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    integer t;

    initial begin
        clk = 1'b0;
        $readmemh("artifacts/mlp/test_vectors/canvas_nibbles.hex", vector_mem);
        $readmemh("artifacts/mlp/test_vectors/expected_digits.hex", expected_digit);

        do_reset();

        for (t = 0; t < NUM_VECTORS; t = t + 1) begin
            load_vector(t);
            run_inference();
            if (best_digit !== expected_digit[t]) begin
                $display("FAIL: vector %0d best_digit=%0d expected=%0d", t, best_digit, expected_digit[t]);
                $finish;
            end else begin
                $display("PASS: vector %0d best_digit=%0d", t, best_digit);
            end
        end

        fill_canvas(4'd0);
        run_inference();
        if (best_digit > 4'd9) begin
            $display("FAIL: blank canvas produced invalid digit %0d", best_digit);
            $finish;
        end
        $display("PASS: blank canvas smoke best_digit=%0d", best_digit);

        fill_canvas(4'hF);
        run_inference();
        if (best_digit > 4'd9) begin
            $display("FAIL: full canvas produced invalid digit %0d", best_digit);
            $finish;
        end
        $display("PASS: full canvas smoke best_digit=%0d", best_digit);

        $display("All mlp_engine tests complete.");
        $finish;
    end

endmodule
