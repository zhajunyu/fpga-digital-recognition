from __future__ import annotations

import argparse
import json
import random
import time
from dataclasses import asdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
import torch
from torch import nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

from mlp_common import DigitMLP, MODEL_VERSION, ModelConfig, PreprocessToTensor, save_json


class RandomStroke:
    def __init__(self, p: float = 0.35) -> None:
        self.p = p

    def __call__(self, image: Image.Image) -> Image.Image:
        if random.random() >= self.p:
            return image
        return image.filter(ImageFilter.MaxFilter(3) if random.random() < 0.5 else ImageFilter.MinFilter(3))


class AddNoise:
    def __init__(self, p: float = 0.35, sigma: float = 0.035) -> None:
        self.p = p
        self.sigma = sigma

    def __call__(self, tensor: torch.Tensor) -> torch.Tensor:
        if random.random() >= self.p:
            return tensor
        return torch.clamp(tensor + torch.randn_like(tensor) * self.sigma, 0.0, 1.0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train an FPGA-friendly MLP digit recognizer.")
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--hidden-dim", type=int, default=128)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--data-dir", type=Path, default=Path("artifacts/data"))
    parser.add_argument("--out-dir", type=Path, default=Path("artifacts/mlp"))
    parser.add_argument("--limit-train", type=int, default=0, help="Use only N train samples for quick smoke tests.")
    parser.add_argument("--no-augment", action="store_true")
    return parser.parse_args()


def make_device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def make_loaders(args: argparse.Namespace) -> tuple[DataLoader, DataLoader]:
    train_steps: list[object] = []
    if not args.no_augment:
        train_steps.extend(
            [
                transforms.RandomAffine(
                    degrees=15,
                    translate=(0.10, 0.10),
                    scale=(0.85, 1.18),
                    shear=8,
                    fill=0,
                ),
                RandomStroke(),
            ]
        )
    train_steps.extend([PreprocessToTensor(), AddNoise() if not args.no_augment else transforms.Lambda(lambda x: x)])

    train_set = datasets.MNIST(
        root=str(args.data_dir),
        train=True,
        download=True,
        transform=transforms.Compose(train_steps),
    )
    test_set = datasets.MNIST(
        root=str(args.data_dir),
        train=False,
        download=True,
        transform=PreprocessToTensor(),
    )
    if args.limit_train > 0:
        train_set = torch.utils.data.Subset(train_set, range(min(args.limit_train, len(train_set))))

    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True, num_workers=0)
    test_loader = DataLoader(test_set, batch_size=args.batch_size * 2, shuffle=False, num_workers=0)
    return train_loader, test_loader


def evaluate(model: nn.Module, loader: DataLoader, device: torch.device) -> tuple[float, float]:
    model.eval()
    criterion = nn.CrossEntropyLoss()
    total_loss = 0.0
    total_correct = 0
    total_seen = 0
    with torch.no_grad():
        for x, y in loader:
            x = x.to(device)
            y = y.to(device)
            logits = model(x)
            loss = criterion(logits, y)
            total_loss += float(loss.item()) * y.numel()
            total_correct += int((logits.argmax(dim=1) == y).sum().item())
            total_seen += int(y.numel())
    return total_loss / total_seen, total_correct / total_seen


def train(args: argparse.Namespace) -> dict[str, object]:
    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    device = make_device()
    train_loader, test_loader = make_loaders(args)
    config = ModelConfig(hidden_dim=args.hidden_dim)
    model = DigitMLP(config).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    best_acc = 0.0
    best_state = None
    history: list[dict[str, float]] = []
    started = time.time()

    print(f"device={device} train_samples={len(train_loader.dataset)} test_samples={len(test_loader.dataset)}")
    for epoch in range(1, args.epochs + 1):
        model.train()
        running_loss = 0.0
        running_correct = 0
        running_seen = 0
        for x, y in train_loader:
            x = x.to(device)
            y = y.to(device)
            optimizer.zero_grad(set_to_none=True)
            logits = model(x)
            loss = criterion(logits, y)
            loss.backward()
            optimizer.step()

            running_loss += float(loss.item()) * y.numel()
            running_correct += int((logits.argmax(dim=1) == y).sum().item())
            running_seen += int(y.numel())

        scheduler.step()
        train_loss = running_loss / running_seen
        train_acc = running_correct / running_seen
        test_loss, test_acc = evaluate(model, test_loader, device)
        history.append(
            {
                "epoch": float(epoch),
                "train_loss": train_loss,
                "train_accuracy": train_acc,
                "test_loss": test_loss,
                "test_accuracy": test_acc,
                "lr": float(scheduler.get_last_lr()[0]),
            }
        )
        print(
            f"epoch={epoch:02d} train_loss={train_loss:.4f} train_acc={train_acc:.4%} "
            f"test_loss={test_loss:.4f} test_acc={test_acc:.4%}"
        )
        if test_acc > best_acc:
            best_acc = test_acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}

    assert best_state is not None
    model.load_state_dict(best_state)
    final_loss, final_acc = evaluate(model, test_loader, device)

    metadata = {
        "model_version": MODEL_VERSION,
        "trained_at_unix": time.time(),
        "train_seconds": time.time() - started,
        "best_test_accuracy": best_acc,
        "final_test_accuracy": final_acc,
        "final_test_loss": final_loss,
        "augment": not args.no_augment,
        "seed": args.seed,
    }
    checkpoint = {
        "model_state": model.cpu().state_dict(),
        "config": asdict(config),
        "metadata": metadata,
    }
    torch.save(checkpoint, args.out_dir / "mnist_mlp.pt")

    export_weights(model.cpu(), args.out_dir)
    save_json(args.out_dir / "metrics.json", {"metadata": metadata, "history": history})
    print(f"saved model to {args.out_dir / 'mnist_mlp.pt'}")
    print(f"best_test_accuracy={best_acc:.4%}")
    return {"accuracy": final_acc, "metadata": metadata}


def export_weights(model: DigitMLP, out_dir: Path) -> None:
    linear1 = model.net[1]
    linear2 = model.net[3]
    assert isinstance(linear1, nn.Linear)
    assert isinstance(linear2, nn.Linear)
    w1 = linear1.weight.detach().numpy().astype(np.float32)
    b1 = linear1.bias.detach().numpy().astype(np.float32)
    w2 = linear2.weight.detach().numpy().astype(np.float32)
    b2 = linear2.bias.detach().numpy().astype(np.float32)
    np.savez(out_dir / "weights_float.npz", w1=w1, b1=b1, w2=w2, b2=b2)

    q = quantize_for_export(w1, b1, w2, b2)
    np.savez(
        out_dir / "weights_quantized.npz",
        w1=q["w1_q"],
        b1=q["b1_q"],
        w2=q["w2_q"],
        b2=q["b2_q"],
    )
    write_int_hex(out_dir / "w1_int8.hex", q["w1_q"], bits=8)
    write_int_hex(out_dir / "b1_int32.hex", q["b1_q"], bits=32)
    write_int_hex(out_dir / "w2_int8.hex", q["w2_q"], bits=8)
    write_int_hex(out_dir / "b2_int32.hex", q["b2_q"], bits=32)
    quant_meta = {
        "input_scale": q["input_scale"],
        "w1_scale": q["w1_scale"],
        "w2_scale": q["w2_scale"],
        "format": "signed two's-complement hex, row-major weights by output neuron",
        "note": "These files are for the later Verilog inference engine; Python verifier uses float checkpoint.",
    }
    (out_dir / "quantization.json").write_text(json.dumps(quant_meta, indent=2) + "\n", encoding="utf-8")


def quantize_for_export(w1: np.ndarray, b1: np.ndarray, w2: np.ndarray, b2: np.ndarray) -> dict[str, object]:
    input_scale = 1.0 / 255.0
    w1_scale = max(float(np.max(np.abs(w1))) / 127.0, 1e-8)
    w2_scale = max(float(np.max(np.abs(w2))) / 127.0, 1e-8)
    w1_q = np.clip(np.round(w1 / w1_scale), -128, 127).astype(np.int8)
    w2_q = np.clip(np.round(w2 / w2_scale), -128, 127).astype(np.int8)
    b1_q = np.round(b1 / (input_scale * w1_scale)).astype(np.int32)
    b2_q = np.round(b2 / w2_scale).astype(np.int32)
    return {
        "input_scale": input_scale,
        "w1_scale": w1_scale,
        "w2_scale": w2_scale,
        "w1_q": w1_q,
        "b1_q": b1_q,
        "w2_q": w2_q,
        "b2_q": b2_q,
    }


def write_int_hex(path: Path, values: np.ndarray, bits: int) -> None:
    mask = (1 << bits) - 1
    width = bits // 4
    flat = values.reshape(-1)
    with path.open("w", encoding="utf-8") as f:
        for value in flat:
            f.write(f"{int(value) & mask:0{width}X}\n")


if __name__ == "__main__":
    train(parse_args())

