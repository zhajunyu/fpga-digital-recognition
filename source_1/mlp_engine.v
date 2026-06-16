`include "mlp_hw_config.vh"

module mlp_engine (
    input            clk,          // 100MHz
    input            rst,
    input            start,        // pulse: begin inference
    input      [3:0] canvas_data,  // from canvas_ram Port B, 0=blank, 15=max ink
    output reg [9:0] canvas_addr,  // to canvas_ram Port B
    output reg       done,         // high when result is valid
    output reg [3:0] best_digit    // recognized digit 0..9
);

    localparam INPUT_DIM  = 10'd784;
    localparam HIDDEN_DIM = 9'd256;
    localparam OUTPUT_DIM = 4'd10;

    localparam W1_SIZE = 18'd200704; // 256 * 784
    localparam W2_SIZE = 12'd2560;   // 10 * 256

    localparam IDLE         = 4'd0;
    localparam CACHE_PRIME  = 4'd1;
    localparam CACHE_READ   = 4'd2;
    localparam HIDDEN_SETUP = 4'd3;
    localparam HIDDEN_MAC   = 4'd4;
    localparam HIDDEN_STORE = 4'd5;
    localparam OUT_SETUP    = 4'd6;
    localparam OUT_MAC      = 4'd7;
    localparam OUT_STORE    = 4'd8;
    localparam ARGMAX_INIT  = 4'd9;
    localparam ARGMAX       = 4'd10;
    localparam DONE_S       = 4'd11;

    reg [3:0] state;

    reg [7:0] input_buf [0:783];
    reg [7:0] hidden    [0:255];

    reg signed [7:0]  w1 [0:200703];
    reg signed [7:0]  w2 [0:2559];
    reg signed [31:0] b1 [0:255];
    reg signed [31:0] b2 [0:9];

    reg signed [31:0] score [0:9];

    reg [9:0] cache_idx;
    reg [8:0] hidden_idx;
    reg [9:0] input_idx;
    reg [3:0] output_idx;
    reg [8:0] out_hidden_idx;
    reg [3:0] compare_idx;

    reg signed [31:0] acc;
    reg signed [31:0] best_score;

    wire [17:0] w1_addr = hidden_idx * 18'd784 + input_idx;
    wire [11:0] w2_addr = output_idx * 12'd256 + out_hidden_idx;

    wire signed [31:0] input_term =
        $signed({24'd0, input_buf[input_idx]}) * $signed(w1[w1_addr]);

    wire signed [31:0] hidden_term =
        $signed({24'd0, hidden[out_hidden_idx]}) * $signed(w2[w2_addr]);

    function [7:0] relu_shift_sat;
        input signed [31:0] value;
        reg signed [31:0] shifted;
        begin
            if (value <= 32'sd0) begin
                relu_shift_sat = 8'd0;
            end else begin
                shifted = value >>> `MLP_HIDDEN_SHIFT;
                if (shifted > 32'sd255)
                    relu_shift_sat = 8'd255;
                else
                    relu_shift_sat = shifted[7:0];
            end
        end
    endfunction

    initial begin
        $readmemh("artifacts/mlp/w1_int8.hex", w1);
        $readmemh("artifacts/mlp/b1_int32.hex", b1);
        $readmemh("artifacts/mlp/w2_int8.hex", w2);
        $readmemh("artifacts/mlp/b2_hw_int32.hex", b2);
    end

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state          <= IDLE;
            done           <= 1'b0;
            best_digit     <= 4'd0;
            canvas_addr    <= 10'd0;
            cache_idx      <= 10'd0;
            hidden_idx     <= 9'd0;
            input_idx      <= 10'd0;
            output_idx     <= 4'd0;
            out_hidden_idx <= 9'd0;
            compare_idx    <= 4'd0;
            acc            <= 32'sd0;
            best_score     <= 32'sd0;
            for (i = 0; i < 10; i = i + 1)
                score[i] <= 32'sd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        canvas_addr <= 10'd0;
                        cache_idx   <= 10'd0;
                        state       <= CACHE_PRIME;
                    end
                end

                CACHE_PRIME: begin
                    // Give the top-level Port-B mux and synchronous RAM one cycle
                    // before sampling canvas_data.
                    canvas_addr <= 10'd0;
                    cache_idx   <= 10'd0;
                    state       <= CACHE_READ;
                end

                CACHE_READ: begin
                    // canvas_data is 4-bit ink. Expand to the 8-bit domain used by
                    // the fixed-point verifier: x8 = canvas_data * 17.
                    input_buf[cache_idx] <= {canvas_data, 4'd0} + {4'd0, canvas_data};

                    if (cache_idx == 10'd783) begin
                        hidden_idx <= 9'd0;
                        input_idx  <= 10'd0;
                        acc        <= b1[0];
                        state      <= HIDDEN_MAC;
                    end else begin
                        cache_idx   <= cache_idx + 10'd1;
                        canvas_addr <= cache_idx + 10'd1;
                    end
                end

                HIDDEN_SETUP: begin
                    input_idx <= 10'd0;
                    acc       <= b1[hidden_idx];
                    state     <= HIDDEN_MAC;
                end

                HIDDEN_MAC: begin
                    acc <= acc + input_term;
                    if (input_idx == 10'd783)
                        state <= HIDDEN_STORE;
                    else
                        input_idx <= input_idx + 10'd1;
                end

                HIDDEN_STORE: begin
                    hidden[hidden_idx] <= relu_shift_sat(acc);
                    if (hidden_idx == 9'd255) begin
                        output_idx     <= 4'd0;
                        out_hidden_idx <= 9'd0;
                        acc            <= b2[0];
                        state          <= OUT_MAC;
                    end else begin
                        hidden_idx <= hidden_idx + 9'd1;
                        state      <= HIDDEN_SETUP;
                    end
                end

                OUT_SETUP: begin
                    out_hidden_idx <= 9'd0;
                    acc            <= b2[output_idx];
                    state          <= OUT_MAC;
                end

                OUT_MAC: begin
                    acc <= acc + hidden_term;
                    if (out_hidden_idx == 9'd255)
                        state <= OUT_STORE;
                    else
                        out_hidden_idx <= out_hidden_idx + 9'd1;
                end

                OUT_STORE: begin
                    score[output_idx] <= acc;
                    if (output_idx == 4'd9) begin
                        compare_idx <= 4'd1;
                        state       <= ARGMAX_INIT;
                    end else begin
                        output_idx <= output_idx + 4'd1;
                        state      <= OUT_SETUP;
                    end
                end

                ARGMAX_INIT: begin
                    best_digit <= 4'd0;
                    best_score <= score[0];
                    state      <= ARGMAX;
                end

                ARGMAX: begin
                    if (score[compare_idx] > best_score) begin
                        best_score <= score[compare_idx];
                        best_digit <= compare_idx;
                    end

                    if (compare_idx == 4'd9)
                        state <= DONE_S;
                    else
                        compare_idx <= compare_idx + 4'd1;
                end

                DONE_S: begin
                    done <= 1'b1;
                    if (!start)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
