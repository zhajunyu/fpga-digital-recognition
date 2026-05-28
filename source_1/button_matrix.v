module button_matrix (
    input           clk,        // 100MHz system clock
    input           rst,        // reset
    input  [3:0]    row_in,     // row inputs from button matrix
    output [3:0]    col_out,    // column outputs to button matrix (active low scan)
    output [15:0]   btn,        // debounced button states (active high)
    output [15:0]   btn_edge    // rising edge detect on btn
);

    // Scan timing: 100M / 100k = 1kHz per column = 250Hz full scan
    localparam SCAN_MAX = 17'd99_999;

    reg [16:0] scan_cnt;
    reg [1:0]  col_idx;

    // Column scan counter
    always @(posedge clk) begin
        if (rst) begin
            scan_cnt <= 17'd0;
            col_idx  <= 2'd0;
        end else if (scan_cnt == SCAN_MAX) begin
            scan_cnt <= 17'd0;
            col_idx  <= col_idx + 2'd1;
        end else begin
            scan_cnt <= scan_cnt + 17'd1;
        end
    end

    // One-hot-low column drive
    assign col_out = (col_idx == 2'd0) ? 4'b1110 :
                     (col_idx == 2'd1) ? 4'b1101 :
                     (col_idx == 2'd2) ? 4'b1011 :
                                         4'b0111;

    // Latch raw button state when its column is being scanned.
    // row_in is active-low (pulled low when button connects to driven-low column),
    // so we invert to get active-high latched_btn.
    reg [15:0] latched_btn;

    always @(posedge clk) begin
        if (rst) begin
            latched_btn <= 16'd0;
        end else begin
            case (col_idx)
                2'd0: latched_btn[3:0]   <= ~row_in;
                2'd1: latched_btn[7:4]   <= ~row_in;
                2'd2: latched_btn[11:8]  <= ~row_in;
                2'd3: latched_btn[15:12] <= ~row_in;
            endcase
        end
    end

    // 16 Anti_jitter instances — one per button
    genvar k;
    generate
        for (k = 0; k < 16; k = k + 1) begin: debounce
            Anti_jitter aj (
                .clk   (clk),
                .BTN   (latched_btn[k]),
                .BTN_OK(btn[k])
            );
        end
    endgenerate

    // Rising-edge detection on debounced outputs
    reg [15:0] btn_prev;
    always @(posedge clk) begin
        if (rst)
            btn_prev <= 16'd0;
        else
            btn_prev <= btn;
    end

    assign btn_edge = btn & ~btn_prev;

endmodule
