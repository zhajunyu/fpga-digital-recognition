# MLP Training and Verification

This project now includes a Python-trained MLP recognizer for the 28x28 digit canvas.

## Setup

Use `uv` from the repository root:

```sh
UV_CACHE_DIR=.uv-cache uv sync --python 3.11
```

The local `.uv-cache` keeps package-cache writes inside the project folder.

## Train

```sh
UV_CACHE_DIR=.uv-cache uv run python scripts/train_mlp.py --epochs 20 --hidden-dim 256 --batch-size 256
```

The trainer downloads MNIST, applies drawing-style augmentation, evaluates the test set each epoch, and writes artifacts to `artifacts/mlp/`.

Generated outputs:

- `mnist_mlp.pt`: PyTorch checkpoint used by verification tools
- `metrics.json`: training and MNIST test metrics
- `weights_float.npz`: floating-point weights and biases
- `weights_quantized.npz`: exported quantized weights
- `w1_int8.hex`, `b1_int32.hex`, `w2_int8.hex`, `b2_int32.hex`: FPGA-oriented hex exports
- `quantization.json`: scale metadata for later Verilog inference work

## Verify Fixed-Point Hardware Math

```sh
UV_CACHE_DIR=.uv-cache uv run python scripts/verify_fixed_point_mlp.py
```

This emulates the Verilog inference path from the exported hex files:

```text
x8 = canvas_data * 17
acc1 = b1_q + sum(x8 * w1_q)
h8 = clamp(ReLU(acc1) >>> HIDDEN_SHIFT, 0, 255)
logit = b2_hw_q + sum(h8 * w2_q)
```

Current fixed-point result:

```text
HIDDEN_SHIFT: 10
MNIST fixed-point accuracy: 97.91% (9791 / 10000)
```

Additional hardware artifacts:

- `b2_hw_int32.hex`: layer-2 biases rescaled for the 8-bit hidden activation path
- `fixed_point_metrics.json`: fixed-point verification report
- `test_vectors/`: 4-bit canvas vectors and expected fixed-point predictions for HDL simulation
- `source_1/mlp_hw_config.vh`: generated Verilog include with `MLP_HIDDEN_SHIFT`

## Evaluate MNIST Accuracy

```sh
UV_CACHE_DIR=.uv-cache uv run python scripts/evaluate_mlp.py
```

Current floating-point checkpoint:

```text
MNIST test accuracy: 97.98% (9798 / 10000)
```

## Predict One Image

```sh
UV_CACHE_DIR=.uv-cache uv run python scripts/evaluate_mlp.py --image path/to/digit.png --save-preprocessed artifacts/mlp/debug_28x28.png
```

The same crop, center, invert, and resize preprocessing is used by both the evaluator and the drawing verifier.

## Draw and Verify

```sh
UV_CACHE_DIR=.uv-cache uv run python scripts/draw_verify.py
```

This opens a small drawing window. Draw one digit with the mouse, then click `Predict`.

## HDL Integration

The top-level HDL now uses `source_1/mlp_engine.v` instead of the legacy `matcher.v`/`template_rom.v` path. The recognizer keeps the existing `start -> done + digit` handshake and reads the same 28x28 canvas RAM through Port B.

Run `sim_1/tb_mlp_engine.v` in Vivado XSim with the repository root as the simulation working directory so `$readmemh` can find `artifacts/mlp/*.hex`.
