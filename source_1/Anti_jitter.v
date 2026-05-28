module Anti_jitter(
    input clk,  // 100 MHz
    input BTN,
    output reg BTN_OK
);
 
    reg [19:0] count;
    
    initial begin
        count <= 20'd0;
        BTN_OK <= 1'b0;
    end
    
    always @(posedge clk) begin
        if (BTN == 1'b0) begin
            count <= 20'd0;
            BTN_OK <= 1'b0;
        end
        else begin
            if (count < 20'd1_000_000) begin
                count <= count + 1'b1;
                BTN_OK <= 1'b0;
            end
            else begin
                count <= count;
                BTN_OK <= 1'b1;
            end
        end
    end
endmodule