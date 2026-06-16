from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
import torch
from torch.utils.data import DataLoader
from torchvision import datasets

from mlp_common import PreprocessToTensor, preprocess_pil_digit


INPUT_DIM = 784
HIDDEN_DIM = 256
OUTPUT_DIM = 10
MIN_ACCURACY = 0.965


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify the hardware-exact fixed-point MLP path.")
    parser.add_argument("--data-dir", type=Path, default=Path("artifacts/data"))
    parser.add_argument("--artifact-dir", type=Path, default=Path("artifacts/mlp"))
    parser.add_argument("--source-dir", type=Path, default=Path("source_1"))
    parser.add_argument("--user-dir", type=Path, default=Path("artifacts/user_digits"))
    parser.add_argument("--batch-size", type=int, default=512)
    parser.add_argument("--max-train-batches", type=int, default=0)
    parser.add_argument("--max-test-batches", type=int, default=0)
    parser.add_argument("--vector-count", type=int, default=16)
    parser.add_argument("--min-accuracy", type=float, default=MIN_ACCURACY)
    return parser.parse_args()


def read_hex_signed(path: Path, bits: int, shape: tuple[int, ...]) -> np.ndarray:
    values: list[int] = []
    sign = 1 << (bits - 1)
    full = 1 << bits
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        raw = int(stripped, 16)
        values.append(raw - full if raw & sign else raw)
    arr = np.asarray(values, dtype=np.int64)
    expected = int(np.prod(shape))
    if arr.size != expected:
        raise ValueError(f"{path} has {arr.size} values, expected {expected}")
    return arr.reshape(shape)


def write_hex_signed(path: Path, values: np.ndarray, bits: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mask = (1 << bits) - 1
    width = bits // 4
    with path.open("w", encoding="utf-8") as f:
        for value in values.reshape(-1):
            f.write(f"{int(value) & mask:0{width}X}\n")


def load_weights(artifact_dir: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, dict[str, float]]:
    w1 = read_hex_signed(artifact_dir / "w1_int8.hex", 8, (HIDDEN_DIM, INPUT_DIM)).astype(np.int32)
    b1 = read_hex_signed(artifact_dir / "b1_int32.hex", 32, (HIDDEN_DIM,)).astype(np.int64)
    w2 = read_hex_signed(artifact_dir / "w2_int8.hex", 8, (OUTPUT_DIM, HIDDEN_DIM)).astype(np.int32)
    _b2_old = read_hex_signed(artifact_dir / "b2_int32.hex", 32, (OUTPUT_DIM,)).astype(np.int64)
    quant = json.loads((artifact_dir / "quantization.json").read_text(encoding="utf-8"))
    return w1, b1, w2, _b2_old, quant


def batch_to_x8(batch: torch.Tensor) -> np.ndarray:
    arr = batch.numpy()
    nibbles = np.clip(np.rint(arr.reshape(arr.shape[0], -1) * 15.0), 0, 15).astype(np.int32)
    return nibbles * 17


def choose_hidden_shift(
    train_loader: DataLoader,
    w1: np.ndarray,
    b1: np.ndarray,
    max_batches: int,
) -> tuple[int, dict[str, float]]:
    best_shift = 0
    stats_by_shift: dict[int, dict[str, float]] = {}
    for shift in range(0, 24):
        clipped = 0
        total = 0
        batches = 0
        max_h = 0
        for batch, _label in train_loader:
            x8 = batch_to_x8(batch).astype(np.int32)
            acc1 = x8 @ w1.T + b1
            relu = np.maximum(acc1, 0)
            shifted = relu >> shift
            clipped += int(np.count_nonzero(shifted > 255))
            total += int(shifted.size)
            max_h = max(max_h, int(shifted.max(initial=0)))
            batches += 1
            if max_batches and batches >= max_batches:
                break
        clip_rate = clipped / total
        stats_by_shift[shift] = {"clip_rate": clip_rate, "max_hidden": float(max_h)}
        if clip_rate <= 0.01:
            best_shift = shift
            break
    else:
        raise RuntimeError("Could not find a hidden shift with <=1% clipping")
    return best_shift, stats_by_shift[best_shift]


def make_b2_hw(artifact_dir: Path, quant: dict[str, float], hidden_shift: int) -> np.ndarray:
    float_weights = np.load(artifact_dir / "weights_float.npz")
    b2 = float_weights["b2"].astype(np.float64)
    input_scale = float(quant["input_scale"])
    w1_scale = float(quant["w1_scale"])
    w2_scale = float(quant["w2_scale"])
    hidden_scale = input_scale * w1_scale * (1 << hidden_shift)
    return np.rint(b2 / (hidden_scale * w2_scale)).astype(np.int64)


def infer_fixed(
    x8: np.ndarray,
    w1: np.ndarray,
    b1: np.ndarray,
    w2: np.ndarray,
    b2_hw: np.ndarray,
    hidden_shift: int,
) -> tuple[np.ndarray, np.ndarray]:
    acc1 = x8.astype(np.int32) @ w1.T + b1
    hidden = np.clip(np.maximum(acc1, 0) >> hidden_shift, 0, 255).astype(np.int32)
    logits = hidden @ w2.T + b2_hw
    return logits.argmax(axis=1).astype(np.int64), logits


def evaluate_mnist(
    test_loader: DataLoader,
    w1: np.ndarray,
    b1: np.ndarray,
    w2: np.ndarray,
    b2_hw: np.ndarray,
    hidden_shift: int,
    max_batches: int,
) -> tuple[float, int, int]:
    correct = 0
    total = 0
    batches = 0
    for batch, labels in test_loader:
        x8 = batch_to_x8(batch)
        pred, _ = infer_fixed(x8, w1, b1, w2, b2_hw, hidden_shift)
        y = labels.numpy()
        correct += int(np.count_nonzero(pred == y))
        total += int(y.size)
        batches += 1
        if max_batches and batches >= max_batches:
            break
    return correct / total, correct, total


def evaluate_user_images(
    user_dir: Path,
    w1: np.ndarray,
    b1: np.ndarray,
    w2: np.ndarray,
    b2_hw: np.ndarray,
    hidden_shift: int,
) -> list[dict[str, object]]:
    if not user_dir.exists():
        return []
    results: list[dict[str, object]] = []
    for path in sorted(user_dir.iterdir()):
        if path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".bmp"}:
            continue
        expected = int(path.stem[0]) if path.stem and path.stem[0].isdigit() else None
        arr = preprocess_pil_digit(Image.open(path))
        nibble = np.clip(np.rint(arr.reshape(1, -1) * 15.0), 0, 15).astype(np.int32)
        pred, logits = infer_fixed(nibble * 17, w1, b1, w2, b2_hw, hidden_shift)
        results.append(
            {
                "path": str(path),
                "expected": expected,
                "prediction": int(pred[0]),
                "correct": None if expected is None else bool(pred[0] == expected),
                "logits": [int(x) for x in logits[0]],
            }
        )
    return results


def export_test_vectors(
    artifact_dir: Path,
    test_set: datasets.MNIST,
    w1: np.ndarray,
    b1: np.ndarray,
    w2: np.ndarray,
    b2_hw: np.ndarray,
    hidden_shift: int,
    count: int,
) -> None:
    vector_dir = artifact_dir / "test_vectors"
    vector_dir.mkdir(parents=True, exist_ok=True)
    with (vector_dir / "canvas_nibbles.hex").open("w", encoding="utf-8") as canvas_f, (
        vector_dir / "expected_digits.hex"
    ).open("w", encoding="utf-8") as expected_f, (vector_dir / "labels.hex").open("w", encoding="utf-8") as label_f:
        for idx in range(count):
            tensor, label = test_set[idx]
            nibble = np.clip(np.rint(tensor.numpy().reshape(-1) * 15.0), 0, 15).astype(np.int32)
            pred, _ = infer_fixed((nibble.reshape(1, -1) * 17), w1, b1, w2, b2_hw, hidden_shift)
            for value in nibble:
                canvas_f.write(f"{int(value):X}\n")
            expected_f.write(f"{int(pred[0]):X}\n")
            label_f.write(f"{int(label):X}\n")


def write_hw_config(source_dir: Path, artifact_dir: Path, hidden_shift: int) -> None:
    text = (
        "// Generated by scripts/verify_fixed_point_mlp.py.\n"
        "// Fixed-point MLP hardware parameters.\n"
        f"`define MLP_HIDDEN_SHIFT {hidden_shift}\n"
    )
    source_dir.mkdir(parents=True, exist_ok=True)
    (source_dir / "mlp_hw_config.vh").write_text(text, encoding="utf-8")
    (artifact_dir / "mlp_hw_config.vh").write_text(text, encoding="utf-8")


def main() -> None:
    args = parse_args()
    w1, b1, w2, _b2_old, quant = load_weights(args.artifact_dir)

    train_set = datasets.MNIST(root=str(args.data_dir), train=True, download=True, transform=PreprocessToTensor())
    test_set = datasets.MNIST(root=str(args.data_dir), train=False, download=True, transform=PreprocessToTensor())
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=False, num_workers=0)
    test_loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False, num_workers=0)

    hidden_shift, shift_stats = choose_hidden_shift(train_loader, w1, b1, args.max_train_batches)
    b2_hw = make_b2_hw(args.artifact_dir, quant, hidden_shift)
    accuracy, correct, total = evaluate_mnist(test_loader, w1, b1, w2, b2_hw, hidden_shift, args.max_test_batches)
    user_results = evaluate_user_images(args.user_dir, w1, b1, w2, b2_hw, hidden_shift)

    write_hex_signed(args.artifact_dir / "b2_hw_int32.hex", b2_hw, 32)
    write_hw_config(args.source_dir, args.artifact_dir, hidden_shift)
    export_test_vectors(args.artifact_dir, test_set, w1, b1, w2, b2_hw, hidden_shift, args.vector_count)

    metrics = {
        "hidden_shift": hidden_shift,
        "hidden_shift_stats": shift_stats,
        "mnist_fixed_point_accuracy": accuracy,
        "mnist_correct": correct,
        "mnist_total": total,
        "min_accuracy": args.min_accuracy,
        "user_image_count": len(user_results),
        "user_results": user_results,
        "math": {
            "input": "x8 = canvas_data * 17",
            "layer1": "acc1 = b1_q + sum(x8 * w1_q)",
            "hidden": "h8 = clamp(ReLU(acc1) >>> HIDDEN_SHIFT, 0, 255)",
            "layer2": "logit = b2_hw_q + sum(h8 * w2_q)",
        },
    }
    (args.artifact_dir / "fixed_point_metrics.json").write_text(
        json.dumps(metrics, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(f"hidden_shift={hidden_shift} clip_rate={shift_stats['clip_rate']:.4%}")
    print(f"mnist_fixed_point_accuracy={accuracy:.4%} correct={correct} total={total}")
    print(f"user_images={len(user_results)}")
    if accuracy < args.min_accuracy:
        raise SystemExit(f"fixed-point accuracy {accuracy:.4%} is below required {args.min_accuracy:.4%}")


if __name__ == "__main__":
    main()
