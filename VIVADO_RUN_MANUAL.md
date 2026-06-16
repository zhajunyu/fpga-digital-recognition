# Vivado Run Manual

This project does not currently include a Vivado `.xpr` file, so create a new RTL project and import the repository sources.

## Create the Project

1. Open Vivado and choose `Create Project`.
2. Use this repository as the project location:

   ```text
   /Users/zhajunyu/Developer/fpga-digital-recognition
   ```

3. Select `RTL Project`.
4. Select the SWORD board FPGA part:

   ```text
   xc7k160tffg676-1
   ```

5. Set the top module to:

   ```text
   top
   ```

## Add Design Sources

Add these files from `source_1/`:

```text
top.v
mlp_engine.v
mlp_hw_config.vh
canvas_ram.v
draw_ctrl.v
vga_render.v
vga.v
recognizer_fsm.v
button_matrix.v
Anti_jitter.v
clkdiv.v
DisplayNumber.v
```

`matcher.v` and `template_rom.v` are legacy template-matching files and are not used by the current MLP recognition path.

## Add Constraints

Add:

```text
constrs_1/Kintex-7.xdc
constrs_1/vga.xdc
```

If Vivado reports duplicate constraints for `clk`, `rst`, or `SW[3:0]`, keep `Kintex-7.xdc` and merge only the VGA pin constraints from `vga.xdc` into the active constraint set.

## MLP Weight Files

`source_1/mlp_engine.v` loads the trained MLP weights with relative paths:

```verilog
$readmemh("artifacts/mlp/w1_int8.hex", w1);
$readmemh("artifacts/mlp/b1_int32.hex", b1);
$readmemh("artifacts/mlp/w2_int8.hex", w2);
$readmemh("artifacts/mlp/b2_hw_int32.hex", b2);
```

Run Vivado/XSim from the repository root, or copy `artifacts/mlp/` into the simulation/synthesis working directory so these paths resolve.

## Simulation

Add this simulation source:

```text
sim_1/tb_mlp_engine.v
```

Run behavioral simulation. The testbench reads:

```text
artifacts/mlp/test_vectors/canvas_nibbles.hex
artifacts/mlp/test_vectors/expected_digits.hex
```

If `$readmemh` cannot find files, set the simulation working directory to the repository root or copy the `artifacts/mlp/` folder into the XSim run directory.

## Synthesis and Bitstream

After sources and constraints are imported:

1. Run `Synthesis`.
2. Run `Implementation`.
3. Generate the bitstream.
4. Open Hardware Manager.
5. Program the SWORD board through JTAG.

## Optional Python Verification

Before running Vivado, verify the trained fixed-point model:

```sh
UV_CACHE_DIR=.uv-cache uv run python scripts/verify_fixed_point_mlp.py
```

Expected result:

```text
mnist_fixed_point_accuracy=97.9100%
```

