// Arduino 4-digit 7-segment display driver.
// Stripped from Lab10_RevCounter — clkdiv removed (uses project clkdiv.v).
// MyMC14495: gate-level hex-to-7-segment decoder (active-low, common anode).
// DisplaySync: time-multiplexed digit scanner.
// DisplayNumber: top-level wrapper.

module MyMC14495 (
    input D0, D1, D2, D3, LE, point,
    output a, b, c, d, e, f, g, p
);
    wire N0, N1, N2, N3;
    wire A1, A2, A3, A4, A5, A6, A7, A8, A9,
        A10, A11, A12, A13, A14, A15, A16, A17, A18, A19, A20, A21;
    wire O1, O2, O3, O4, O5, O6, O7;

    not
        not0(N0, D0),
        not1(N1, D1),
        not2(N2, D2),
        not3(N3, D3),
        not4(p, point);

    and
        and1(A1, D2, D3, N0, N1),
        and2(A2, D0, D1, D2, N3),
        and3(A3, N1, N2, N3),
        and4(A4, D0, D1, N3),
        and5(A5, D1, N2, N3),
        and6(A6, D0, N2, N3),
        and7(A7, D0, N1, N2),
        and8(A8, D2, N1, N3),
        and9(A9, D0, N3),
        and10(A10, D1, D3, N0, N2),
        and11(A11, D0, D1, D2),
        and12(A12, D1, D2, D3),
        and13(A13, D1, N0, N2, N3),
        and14(A14, D0, D1, D3),
        and15(A15, D2, D3, N0),
        and16(A16, D1, D2, N0),
        and17(A17, D0, D2, N1, N3),
        and18(A18, D0, D1, D3, N2),
        and19(A19, D0, D2, D3, N1),
        and20(A20, D2, N0, N1, N3),
        and21(A21, D0, N1, N2, N3);

    or
        or1_1(O1, A1, A2, A3),
        or1_2(O2, A4, A5, A6, A19),
        or1_3(O3, A7, A8, A9),
        or1_4(O4, A10, A11, A20, A21),
        or1_5(O5, A12, A13, A15),
        or1_6(O6, A14, A15, A16, A17),
        or1_7(O7, A18, A19, A20, A21),
        or2_1(g, LE, O1),
        or2_2(f, LE, O2),
        or2_3(e, LE, O3),
        or2_4(d, LE, O4),
        or2_5(c, LE, O5),
        or2_6(b, LE, O6),
        or2_7(a, LE, O7);
endmodule

module DisplaySync(Hexs, Scan, Points, LES, HEX, AN, P, LE);
    input [15:0] Hexs;
    input [1:0] Scan;
    input [3:0] Points;
    input [3:0] LES;

    output reg [3:0] HEX;
    output reg [3:0] AN;
    output reg P, LE;

    always @(*) begin
        case (Scan)
            2'b00: begin
                HEX <= Hexs[3:0];
                AN <= 4'b1110;
                P <= Points[0];
                LE <= LES[0];
            end
            2'b01: begin
                HEX <= Hexs[7:4];
                AN <= 4'b1101;
                P <= Points[1];
                LE <= LES[1];
            end
            2'b10: begin
                HEX <= Hexs[11:8];
                AN <= 4'b1011;
                P <= Points[2];
                LE <= LES[2];
            end
            2'b11: begin
                HEX <= Hexs[15:12];
                AN <= 4'b0111;
                P <= Points[3];
                LE <= LES[3];
            end
        endcase
    end
endmodule

module DisplayNumber(
    input clk,
    input RST,
    input [15:0] Hexs,
    input [3:0] Points,
    input [3:0] LES,
    output [7:0] Segment,
    output [3:0] AN
);
    wire [31:0] div_res;
    wire [3:0] HEX;
    wire P, LE;
    wire a, b, c, d, e, f, g, p;

    // Uses project-global clkdiv module (clkdiv.v in source_1)
    clkdiv c1(
        .clk(clk),
        .rst(RST),
        .div_res(div_res)
    );

    DisplaySync d1(
        .Hexs(Hexs),
        .Scan(div_res[18:17]),
        .Points(Points),
        .LES(LES),
        .HEX(HEX),
        .AN(AN),
        .P(P),
        .LE(LE)
    );

    MyMC14495 m1(
        .D0(HEX[0]),
        .D1(HEX[1]),
        .D2(HEX[2]),
        .D3(HEX[3]),
        .point(P),
        .LE(LE),
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g), .p(p)
    );

    assign Segment = {p, g, f, e, d, c, b, a};
endmodule
