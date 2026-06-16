from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
import torch
from torch.utils.data import DataLoader
from torchvision import datasets

from mlp_common import PreprocessToTensor, load_checkpoint, predict_array, preprocess_pil_digit


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate or use the trained MLP digit recognizer.")
    parser.add_argument("--model", type=Path, default=Path("artifacts/mlp/mnist_mlp.pt"))
    parser.add_argument("--data-dir", type=Path, default=Path("artifacts/data"))
    parser.add_argument("--image", type=Path, help="Predict one user-supplied image instead of MNIST test accuracy.")
    parser.add_argument("--save-preprocessed", type=Path, help="Save the 28x28 preprocessed image for inspection.")
    parser.add_argument("--batch-size", type=int, default=512)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model, metadata = load_checkpoint(args.model)
    print(f"loaded {args.model}")
    if metadata:
        print(f"metadata={metadata}")

    if args.image:
        arr = preprocess_pil_digit(Image.open(args.image))
        if args.save_preprocessed:
            Image.fromarray(np.uint8(arr * 255), mode="L").save(args.save_preprocessed)
            print(f"saved preprocessed image to {args.save_preprocessed}")
        digit, probs = predict_array(model, arr)
        ranked = sorted(enumerate(probs), key=lambda item: item[1], reverse=True)
        print(f"prediction={digit} confidence={probs[digit]:.2%}")
        print("top3=" + ", ".join(f"{d}:{p:.2%}" for d, p in ranked[:3]))
        return

    test_set = datasets.MNIST(
        root=str(args.data_dir),
        train=False,
        download=True,
        transform=PreprocessToTensor(),
    )
    loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False, num_workers=0)
    correct = 0
    total = 0
    with torch.no_grad():
        for x, y in loader:
            logits = model(x)
            correct += int((logits.argmax(dim=1) == y).sum().item())
            total += int(y.numel())
    print(f"mnist_test_accuracy={correct / total:.4%} correct={correct} total={total}")


if __name__ == "__main__":
    main()

