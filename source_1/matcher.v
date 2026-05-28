module matcher (
    input           clk,            // 100MHz
    input           rst,
    input           start,          // pulse: begin matching
    input  [3:0]    canvas_data,    // from canvas_ram Port B
    input  [39:0]   template_data,  // from template_rom (10 templates packed)
    output reg [9:0] canvas_addr,   // to canvas_ram Port B
    output reg [9:0] template_addr, // to template_rom
    output reg       done,          // high when result is valid
    output reg [3:0] best_digit     // recognized digit 0..9
);

    // FSM states
    localparam IDLE    = 2'd0;
    localparam ACCUM   = 2'd1;
    localparam COMPARE = 2'd2;
    localparam DONE_S  = 2'd3;

    reg [1:0]  state;
    reg [9:0]  cell_cnt;           // 0..784
    reg [15:0] score [0:9];        // SAD accumulators

    // Unpack 40-bit template_data into 10× 4-bit values
    wire [3:0] tmpl_val [0:9];
    genvar g;
    generate
        for (g = 0; g < 10; g = g + 1) begin: tmpl_unpack
            assign tmpl_val[g] = template_data[g*4 +: 4];
        end
    endgenerate

    // Absolute difference: |canvas_data - tmpl_val[d]|
    wire [3:0] abs_diff [0:9];
    generate
        for (g = 0; g < 10; g = g + 1) begin: abs_gen
            assign abs_diff[g] = (canvas_data > tmpl_val[g])
                               ? (canvas_data - tmpl_val[g])
                               : (tmpl_val[g] - canvas_data);
        end
    endgenerate

    // Combinational comparator tree — finds digit with minimum SAD score
    wire [3:0] cmp_01 = (score[0] < score[1]) ? 4'd0 : 4'd1;
    wire [15:0] val_01 = (score[0] < score[1]) ? score[0] : score[1];

    wire [3:0] cmp_23 = (score[2] < score[3]) ? 4'd2 : 4'd3;
    wire [15:0] val_23 = (score[2] < score[3]) ? score[2] : score[3];

    wire [3:0] cmp_45 = (score[4] < score[5]) ? 4'd4 : 4'd5;
    wire [15:0] val_45 = (score[4] < score[5]) ? score[4] : score[5];

    wire [3:0] cmp_67 = (score[6] < score[7]) ? 4'd6 : 4'd7;
    wire [15:0] val_67 = (score[6] < score[7]) ? score[6] : score[7];

    wire [3:0] cmp_89 = (score[8] < score[9]) ? 4'd8 : 4'd9;
    wire [15:0] val_89 = (score[8] < score[9]) ? score[8] : score[9];

    wire [3:0] cmp_0123 = (val_01 < val_23) ? cmp_01 : cmp_23;
    wire [15:0] val_0123 = (val_01 < val_23) ? val_01 : val_23;

    wire [3:0] cmp_4567 = (val_45 < val_67) ? cmp_45 : cmp_67;
    wire [15:0] val_4567 = (val_45 < val_67) ? val_45 : val_67;

    wire [3:0] cmp_014567 = (val_0123 < val_4567) ? cmp_0123 : cmp_4567;
    wire [15:0] val_014567 = (val_0123 < val_4567) ? val_0123 : val_4567;

    wire [3:0] best = (val_014567 < val_89) ? cmp_014567 : cmp_89;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            cell_cnt  <= 10'd0;
            done      <= 1'b0;
            best_digit <= 4'd0;
            canvas_addr   <= 10'd0;
            template_addr <= 10'd0;
            for (i = 0; i < 10; i = i + 1)
                score[i] <= 16'd0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state     <= ACCUM;
                        cell_cnt  <= 10'd0;
                        // Reset scores
                        for (i = 0; i < 10; i = i + 1)
                            score[i] <= 16'd0;
                    end
                end

                ACCUM: begin
                    if (cell_cnt > 0) begin
                        // Accumulate SAD using data from previous cycle's addr
                        for (i = 0; i < 10; i = i + 1)
                            score[i] <= score[i] + {12'd0, abs_diff[i]};
                    end

                    if (cell_cnt == 10'd784) begin
                        state <= COMPARE;
                    end else begin
                        canvas_addr   <= cell_cnt;  // request next cell
                        template_addr <= cell_cnt;
                        cell_cnt <= cell_cnt + 10'd1;
                    end
                end

                COMPARE: begin
                    best_digit <= best;
                    state <= DONE_S;
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
