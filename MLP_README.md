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

## Evaluate MNIST Accuracy

```sh
UV_CACHE_DIR=.uv-cache uv run python scripts/evaluate_mlp.py
```

Current trained checkpoint:

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
