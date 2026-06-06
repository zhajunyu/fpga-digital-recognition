# rst
set_property PACKAGE_PIN AF8 [get_ports rst]
set_property IOSTANDARD LVCMOS15 [get_ports rst]

# SW[6:0]

set_property PACKAGE_PIN AA10 [get_ports {SW[0]}]
set_property PACKAGE_PIN AB10 [get_ports {SW[1]}]
set_property PACKAGE_PIN AA13 [get_ports {SW[2]}]
set_property PACKAGE_PIN AA12 [get_ports {SW[3]}]
set_property PACKAGE_PIN Y13 [get_ports {SW[4]}]
set_property PACKAGE_PIN Y12 [get_ports {SW[5]}]
set_property PACKAGE_PIN AD11 [get_ports {SW[6]}]

set_property IOSTANDARD LVCMOS15 [get_ports {SW[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {SW[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {SW[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {SW[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {SW[4]}]
set_property IOSTANDARD LVCMOS15 [get_ports {SW[5]}]
set_property IOSTANDARD LVCMOS15 [get_ports {SW[6]}]

# clk
set_property PACKAGE_PIN AC18 [get_ports clk]
set_property IOSTANDARD LVCMOS18 [get_ports clk]

# ── 4×4 Button Matrix (5 rows on board, using rows 0–3) ─────────────
# Row inputs (pull-up on board, reads low when button pressed)
set_property PACKAGE_PIN V17 [get_ports {btn_row[0]}]
set_property PACKAGE_PIN W18 [get_ports {btn_row[1]}]
set_property PACKAGE_PIN W19 [get_ports {btn_row[2]}]
set_property PACKAGE_PIN W15 [get_ports {btn_row[3]}]

set_property IOSTANDARD LVCMOS18 [get_ports {btn_row[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {btn_row[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {btn_row[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {btn_row[3]}]

# Column outputs (FPGA drives one column low at a time to scan)
set_property PACKAGE_PIN V18 [get_ports {btn_col[0]}]
set_property PACKAGE_PIN V19 [get_ports {btn_col[1]}]
set_property PACKAGE_PIN V14 [get_ports {btn_col[2]}]
set_property PACKAGE_PIN W14 [get_ports {btn_col[3]}]

set_property IOSTANDARD LVCMOS18 [get_ports {btn_col[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {btn_col[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {btn_col[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {btn_col[3]}]

# K_ROW[4] (W16) — 5th matrix row, unused by design
# RSTN (W13) — active-low reset/CR button, unused (rst at AF8 used instead)

set_property PACKAGE_PIN AD21 [get_ports {AN[0]}]
set_property PACKAGE_PIN AC21 [get_ports {AN[1]}]
set_property PACKAGE_PIN AB21 [get_ports {AN[2]}]
set_property PACKAGE_PIN AC22 [get_ports {AN[3]}]
set_property PACKAGE_PIN AB22 [get_ports {Segment[0]}]
set_property PACKAGE_PIN AD24 [get_ports {Segment[1]}]
set_property PACKAGE_PIN AD23 [get_ports {Segment[2]}]
set_property PACKAGE_PIN Y21 [get_ports {Segment[3]}]
set_property PACKAGE_PIN W20 [get_ports {Segment[4]}]
set_property PACKAGE_PIN AC24 [get_ports {Segment[5]}]
set_property PACKAGE_PIN AC23 [get_ports {Segment[6]}]
set_property PACKAGE_PIN AA22 [get_ports {Segment[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {Segment[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {Segment[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {Segment[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {Segment[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {Segment[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {Segment[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {Segment[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {Segment[7]}]