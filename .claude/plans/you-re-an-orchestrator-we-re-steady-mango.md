# FPGA Handwritten Digit Recognition — Implementation Plans

## Context

The project aims to build an interactive handwritten digit recognition system on the SWORD board (Xilinx Kintex-7 XC7K160T). Users draw digits on a VGA pixel canvas using buttons/switches, and the FPGA recognizes the digit via template matching, displaying the result on a 7-segment display.

**Existing infrastructure:** Working VGA controller (`VGA.v`), clock divider (`clkdiv.v`), and a demo top module that draws a movable circle. These will be reused.

**Target platform:** SWORD board — 100MHz clock, 16 switches, 16 buttons (4×4 matrix), VGA RGB444 output.
**Display:** Arduino sub-board 4-digit 7-segment (parallel time-multiplexed) — replaces unavailable onboard SN74LV164 serial display.

---

## Plan 1: Concise (Conceptual Overview)

### Basic Idea

Replace the circle demo with a 28×28 pixel canvas displayed on VGA. Users navigate a cursor with switches, toggle a "pen" with a button, and draw digits. Pressing "Recognize" runs template matching (SAD) against 10 pre-stored digit templates in ROM. The best match is shown on the 7-segment display.

### Necessary Modules (10 total)

| # | Module | Purpose |
|---|--------|---------|
| 1 | `grid_bram` | Dual-port BRAM storing the 28×28 canvas (784×4-bit) |
| 2 | `draw_ctrl` | Cursor movement, pen state, writes to grid_bram |
| 3 | `vga_render` | Maps grid to VGA pixels with grid lines & cursor highlight |
| 4 | `template_rom` | ROM holding 10 digit templates (784×4-bit each, init from file) |
| 5 | `matcher` | Parallel SAD engine comparing input against all 10 templates |
| 6 | `recognizer_fsm` | State machine: IDLE → LATCH → MATCHING → SHOW → CLEARING |
| 7 | `DisplayNumber` | Arduino 4-digit 7-segment (parallel, time-multiplexed) |
| 8 | `debounce` | Button debounce filter |
| 9 | `button_matrix` | 4×4 matrix scanner for 16 buttons |
| 10 | `top` | Top-level integration (replaces current circle-drawing top.v) |

**Reused unchanged:** `clkdiv.v`, `VGA.v`, `VGA.xdc` (extended with new pin constraints).

---

## Plan 2: Detailed (Concrete Implementation Steps)

### Architecture Overview

```
Buttons ──> debounce ──> draw_ctrl ──> grid_bram (Port B: write)
Switches ──> draw_ctrl                   │
                                          ├──> grid_bram (Port A: read) ──> vga_render ──> VGA.v
                                          │
recognizer_fsm ──> matcher ──> template_rom
                    │              ^
                    └──> grid_bram (Port B: read)
                         │
                    DisplayNumber <── recognizer_fsm
```

### Module Specifications

#### 1. grid_bram — Dual-Port Canvas Memory
- 784 addresses × 4-bit grayscale (one 36Kb BRAM)
- Port A: VGA read (25MHz domain). Port B: draw writes + matcher reads (100MHz domain)
- Address = `grid_y × 28 + grid_x`
- Initial state: all zeros (blank)

#### 2. draw_ctrl — Drawing Controller
- **Inputs:** debounced direction buttons, pen_toggle, clear
- **State:** `cursor_x[4:0]` (0–27), `cursor_y[4:0]` (0–27), `pen_down`
- Movement sampled at ~24Hz (clkdiv bit 22) to prevent cursor teleporting
- On directional edge: update cursor (clamped to bounds); if pen_down, write `4'b1111` to cell
- On clear: assert clear signal to recognizer_fsm

#### 3. vga_render — VGA Grid Renderer
- Grid: 28×28 cells, each 10×10 VGA pixels = 280×280 pixel region
- Centered on 640×480 screen: offset_x=180, offset_y=100
- Avoids hardware division by using pixel-within-cell counters
- 2-stage pipeline: Stage 1 computes grid address → Stage 2 reads BRAM, applies color
- Color priority: outside grid (dark gray) > grid lines (medium gray) > cursor (red/green) > inked cell (grayscale) > empty (white)

#### 4. template_rom — Template Storage (Phase A; swappable for MLP weight_rom)
- 10 templates × 784 cells × 4 bits = 31,360 bits (two 18Kb BRAMs)
- Initialized via `$readmemh("templates.hex")` at synthesis
- Templates generated offline by Python script averaging MNIST training images per digit
- Interface: `addr[13:0]` in, `data[3:0]` out — kept narrow, easy to replace with MLP weight ROM

#### 5. matcher — Template Matching Engine (Phase A; swappable for mlp_engine)
- 10 parallel SAD accumulators (|input − template[d]| summed over 784 cells)
- Each cycle: read canvas_ram + all 10 template BRAMs, compute abs diff, accumulate
- Total latency: ~788 cycles ≈ 7.88 μs at 100MHz
- Comparator tree (3 cycles) finds minimum-score digit
- Handshake: `start` in, `done` out, `best_digit[3:0]` out — same contract an MLP engine would use

#### 6. recognizer_fsm — Recognition State Machine
- **IDLE:** drawing enabled, wait for recognize button edge
- **LATCH:** freeze canvas (1 cycle)
- **MATCHING:** run matcher, wait for done (~788 cycles)
- **SHOW:** latch result, drive 7-segment, wait for clear or re-recognize
- **CLEARING:** write zeros to all 784 grid addresses, return to IDLE

#### 7. DisplayNumber — Arduino 4-Digit 7-Segment (reused from Lab10)

Reuse `DisplayNumber.v` from `D:\Vivado_Projects\Lab10_RevCounter\...` — proven on this board. Parallel time-multiplexed interface (AN[3:0] + Segment[7:0]) replaces the unavailable SN74LV164 serial display.

- **Modify copied file:** strip internal `clkdiv` definition (conflicts with our `clkdiv.v`). Keep `MyMC14495`, `DisplaySync`, `DisplayNumber`
- **Interface:** `Hexs[15:0]`, `Points[3:0]`, `LES[3:0]` in; `AN[3:0]`, `Segment[7:0]` out
- **Wiring:** `Hexs = {12'd0, fsm_result_digit}`, `LES = {3'b111, ~fsm_result_valid}` (blanks unused digits), `Points = 4'd0`
- **Scanning:** ~190Hz via our `clkdiv`'s `div_res[18:17]`
- **Replaces:** `seg7_driver.v` — deleted

#### 8. button_matrix — integrated scanner + debounce
- Single module: 4×4 matrix scanner + 16× Anti_jitter instances in one unit
- Scans columns sequentially at ~250Hz, reads rows, feeds each button through Anti_jitter (10ms hold-off)
- Outputs clean 16-bit debounced button states + edge-detect pulses
- Button mapping: 0–3=direction, 4=pen toggle, 5=recognize, 6=clear, 7–15=reserved

#### 9. top — Top-Level Integration
- Instantiates all modules; wires clock domains with 2-flop synchronizers
- VGA pins in `vga.xdc`; SW/clk/rst in `K7.xdc`; Arduino seg7 pins TBD
- SW[6:4] posedge for pen/recognize/clear (replaces buttons via btn_edge)
- Ports: `AN[3:0]`, `Segment[7:0]` (Arduino parallel) replace `seg_data/clk/clr/en`

### Recognition Algorithm: Two-Phase Strategy

**Phase A — Template Matching (SAD) — implemented first**

Zero DSP slices, ~788 cycle latency, 0.05% of a VGA frame. Compares the 28×28 canvas against 10 averaged MNIST templates via sum of absolute differences. ~75-80% accuracy on clean drawings. Intuitive and debuggable: each template is a visible fuzzy digit.

**SAD formula:** `score[t] = Σ|input[i] − template[t][i]|` for t ∈ {0…9}, i ∈ {0…783}. Minimum score wins.

**Phase B — MLP (784→128→10) — optional upgrade, drop-in replacement**

If higher accuracy is desired later, replace only 3 files at the module boundary:

| Replace | With | Reason |
|---------|------|--------|
| `template_rom.v` | `weight_rom.v` | Stores W1/b1/W2/b2 (~100K×8-bit) instead of 10 templates |
| `matcher.v` | `mlp_engine.v` | MAC sequencer + ReLU LUT + argmax instead of SAD |
| `gen_templates.py` | `train_mlp.py` | PyTorch training + quantized weight export |

All other modules untouched — same handshake (`start` → `done` + `digit[3:0]`), same `canvas_ram` data source, same `recognizer_fsm`/`DisplayNumber`/VGA pipeline.

### Canvas-to-VGA Mapping

```
640×480 VGA screen
┌────────────────────────────────────────────┐
│                                            │
│     offset_x=180                           │
│     ┌──────────────────────────┐           │
│     │ 28×28 grid               │ offset_y │
│     │ each cell = 10×10 px     │ =100     │
│     │ total = 280×280 px       │          │
│     │                          │          │
│     │ grid lines = 1px wide    │          │
│     └──────────────────────────┘           │
│                                            │
└────────────────────────────────────────────┘
```

### Implementation Phases (8 days)

**Phase 1 — VGA Grid Display**
1. Create `grid_bram.v` (784×4 dual-port BRAM wrapper)
2. Create `vga_render.v` (grid rendering with pixel-within-cell counters, 2-stage pipeline)
3. Modify `top.v` to instantiate grid_bram + vga_render alongside clkdiv + VGA
4. Verify: blank 28×28 grid visible on monitor

**Phase 2 — Drawing Interaction**
5. Create `button_matrix.v` (4×4 scanner + 16× Anti_jitter integrated)
6. Create `draw_ctrl.v` (cursor, pen state, grid writes, movement rate limiting)
7. Extend vga_render to show cursor (red=pen up, green=pen down)
8. Map SW[3:0] to direction, buttons to pen/clear
9. Verify: can draw on VGA by moving cursor with pen down

**Phase 3 — Recognition Engine**
10. Run Python script to generate `templates.hex` from MNIST
11. Create `template_rom.v` (init via `$readmemh`)
12. Create `matcher.v` (10 parallel SAD + comparator tree)
13. Create `recognizer_fsm.v` (5-state FSM)
14. Import `DisplayNumber.v` from Lab10 (Arduino 7-seg), strip internal `clkdiv`
15. Wire everything into top.v

**Phase 4 — Integration & Polish**
16. Full-system testbench simulation
17. Add cross-clock-domain synchronizers
18. Tune cursor speed, add result overlay on VGA
19. On-chip verification with ILA cores
20. Manual acceptance testing (draw digits 0–9, verify recognition)

### Resource Estimates

| Resource | Used | Available | % |
|----------|------|-----------|-----|
| Logic cells | ~2,500 | 162,240 | 1.5% |
| BRAM (36Kb) | ~4 | 325 | 1.2% |
| DSP slices | 0 | 600 | 0% |
| I/O pins | ~30 | 400 | 7.5% |

### Verification Plan

- **Module-level testbenches:** canvas_ram, draw_ctrl, vga_render, matcher, recognizer_fsm, button_matrix
- **Matcher integration testbench:** [`sim_1/tb_matcher.v`](sim_1/tb_matcher.v) — instantiates template_rom + matcher with a mock canvas_ram. Verifies exact-match recognition for digits 0,3,7,9 plus blank-canvas smoke test. Run in Vivado XSim with `templates.hex` accessible
- **Top-level simulation:** Full system with simulated button presses and VGA timing
- **On-chip (ILA):** Capture FSM state transitions, accumulator values, VGA pixel output
- **Manual tests:** Draw each digit 0–9, verify recognition; test edge cases (blank canvas, partial strokes)

### Files to Modify/Create

| File | Action | Purpose |
|------|--------|---------|
| `source_1/top.v` | Rewrite | New top-level integration |
| `source_1/VGA.xdc` | Extend | Add button matrix + 7-segment pins |
| `source_1/canvas_ram.v` | Create | Canvas BRAM |
| `source_1/vga_render.v` | Create | Grid renderer |
| `source_1/draw_ctrl.v` | Create | Drawing controller |
| `source_1/button_matrix.v` | Create | 4×4 matrix scanner + 16× Anti_jitter debounce |
| `source_1/template_rom.v` | Create | Template storage |
| `source_1/matcher.v` | Create | SAD matching engine |
| `source_1/recognizer_fsm.v` | Create | Recognition FSM |
| `source_1/seg7_driver.v` | Delete | Replaced by DisplayNumber.v |
| `source_1/DisplayNumber.v` | Import | Arduino 4-digit 7-seg (from Lab10, clkdiv stripped) |
| `scripts/gen_templates.py` | Create | Offline template generator |
| `source_1/clkdiv.v` | Unchanged | Clock divider |
| `source_1/VGA.v` | Unchanged | VGA timing controller |
| `sim_1/tb_matcher.v` | Create | Matcher + template_rom integration testbench |
