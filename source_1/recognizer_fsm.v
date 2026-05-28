module recognizer_fsm (
    input           clk,            // 100MHz
    input           rst,
    input           recog_btn,      // edge pulse: start recognition
    input           clear_btn,      // edge pulse: clear canvas
    input           matcher_done,   // from matcher
    input  [3:0]    matcher_digit,  // from matcher
    output reg       freeze,        // high = stop draw_ctrl writes
    output reg       matcher_start, // pulse to start matcher
    output reg       matching,      // high during MATCHING (matcher reads canvas_ram)
    output reg       clearing,      // high during CLEARING (fsm writes canvas_ram)
    output reg       clear_we,      // canvas_ram write enable during CLEARING
    output reg [9:0] clear_addr,    // canvas_ram addr during CLEARING
    output reg [3:0] result_digit,  // latched recognition result
    output reg       result_valid   // high in SHOW state
);

    localparam IDLE     = 3'd0;
    localparam LATCH    = 3'd1;
    localparam MATCHING = 3'd2;
    localparam SHOW     = 3'd3;
    localparam CLEARING = 3'd4;

    reg [2:0] state;
    reg [9:0] clear_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            freeze      <= 1'b0;
            matcher_start <= 1'b0;
            matching     <= 1'b0;
            clearing     <= 1'b0;
            clear_we    <= 1'b0;
            clear_addr  <= 10'd0;
            clear_cnt   <= 10'd0;
            result_digit <= 4'd0;
            result_valid <= 1'b0;
        end else begin
            // Defaults
            matcher_start <= 1'b0;
            matching      <= 1'b0;
            clearing      <= 1'b0;
            clear_we      <= 1'b0;

            case (state)

                IDLE: begin
                    freeze       <= 1'b0;
                    result_valid <= 1'b0;
                    if (recog_btn) begin
                        freeze <= 1'b1;
                        state  <= LATCH;
                    end
                end

                LATCH: begin
                    // 1-cycle state: freeze the canvas, start matcher next
                    matcher_start <= 1'b1;
                    state <= MATCHING;
                end

                MATCHING: begin
                    matching <= 1'b1;
                    if (matcher_done) begin
                        result_digit <= matcher_digit;
                        result_valid <= 1'b1;
                        state <= SHOW;
                    end
                end

                SHOW: begin
                    if (clear_btn) begin
                        result_valid <= 1'b0;
                        clear_cnt    <= 10'd0;
                        state <= CLEARING;
                    end else if (recog_btn) begin
                        // Re-recognize without clearing
                        result_valid <= 1'b0;
                        matcher_start <= 1'b1;
                        state <= MATCHING;
                    end
                end

                CLEARING: begin
                    clearing <= 1'b1;
                    clear_we   <= 1'b1;
                    clear_addr <= clear_cnt;
                    clear_cnt  <= clear_cnt + 10'd1;
                    if (clear_cnt == 10'd783) begin
                        freeze <= 1'b0;
                        state  <= IDLE;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
