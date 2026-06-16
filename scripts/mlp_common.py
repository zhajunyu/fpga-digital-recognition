from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image
import torch
from torch import nn


MODEL_VERSION = 1
IMAGE_SIZE = 28
INPUT_DIM = IMAGE_SIZE * IMAGE_SIZE


@dataclass(frozen=True)
class ModelConfig:
    input_dim: int = INPUT_DIM
    hidden_dim: int = 128
    output_dim: int = 10


class DigitMLP(nn.Module):
    def __init__(self, config: ModelConfig) -> None:
        super().__init__()
        self.config = config
        self.net = nn.Sequential(
            nn.Flatten(),
            nn.Linear(config.input_dim, config.hidden_dim),
            nn.ReLU(),
            nn.Linear(config.hidden_dim, config.output_dim),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


def preprocess_pil_digit(image: Image.Image) -> np.ndarray:
    """Return a 28x28 float32 array where 1.0 means ink and 0.0 means background."""
    gray = image.convert("L")
    arr = np.asarray(gray, dtype=np.float32) / 255.0

    # User drawings are normally dark ink on a bright background; MNIST is the reverse.
    if arr.mean() > 0.5:
        arr = 1.0 - arr

    arr[arr < 0.03] = 0.0
    ys, xs = np.nonzero(arr > 0.05)
    if len(xs) == 0 or len(ys) == 0:
        return np.zeros((IMAGE_SIZE, IMAGE_SIZE), dtype=np.float32)

    pad = 2
    x0 = max(int(xs.min()) - pad, 0)
    x1 = min(int(xs.max()) + pad + 1, arr.shape[1])
    y0 = max(int(ys.min()) - pad, 0)
    y1 = min(int(ys.max()) + pad + 1, arr.shape[0])
    crop = arr[y0:y1, x0:x1]

    crop_img = Image.fromarray(np.uint8(np.clip(crop, 0.0, 1.0) * 255.0), mode="L")
    width, height = crop_img.size
    if width >= height:
        new_w = 20
        new_h = max(1, round(height * 20 / width))
    else:
        new_h = 20
        new_w = max(1, round(width * 20 / height))

    resized = crop_img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("L", (IMAGE_SIZE, IMAGE_SIZE), 0)
    canvas.paste(resized, ((IMAGE_SIZE - new_w) // 2, (IMAGE_SIZE - new_h) // 2))

    centered = np.asarray(canvas, dtype=np.float32) / 255.0
    total = float(centered.sum())
    if total > 0.0:
        yy, xx = np.indices(centered.shape)
        cy = float((yy * centered).sum() / total)
        cx = float((xx * centered).sum() / total)
        shift_y = int(round((IMAGE_SIZE - 1) / 2 - cy))
        shift_x = int(round((IMAGE_SIZE - 1) / 2 - cx))
        centered = shift_array(centered, shift_y, shift_x)

    return np.clip(centered, 0.0, 1.0).astype(np.float32)


def shift_array(arr: np.ndarray, shift_y: int, shift_x: int) -> np.ndarray:
    out = np.zeros_like(arr)
    src_y0 = max(0, -shift_y)
    src_y1 = min(arr.shape[0], arr.shape[0] - shift_y)
    src_x0 = max(0, -shift_x)
    src_x1 = min(arr.shape[1], arr.shape[1] - shift_x)
    dst_y0 = max(0, shift_y)
    dst_y1 = dst_y0 + (src_y1 - src_y0)
    dst_x0 = max(0, shift_x)
    dst_x1 = dst_x0 + (src_x1 - src_x0)
    if src_y1 > src_y0 and src_x1 > src_x0:
        out[dst_y0:dst_y1, dst_x0:dst_x1] = arr[src_y0:src_y1, src_x0:src_x1]
    return out


class PreprocessToTensor:
    def __call__(self, image: Image.Image) -> torch.Tensor:
        arr = preprocess_pil_digit(image)
        return torch.from_numpy(arr).view(1, IMAGE_SIZE, IMAGE_SIZE)


def load_checkpoint(path: Path, map_location: str | torch.device = "cpu") -> tuple[DigitMLP, dict[str, Any]]:
    checkpoint = torch.load(path, map_location=map_location, weights_only=False)
    metadata = checkpoint.get("metadata", {})
    config = ModelConfig(**checkpoint.get("config", asdict(ModelConfig())))
    model = DigitMLP(config)
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    return model, metadata


@torch.no_grad()
def predict_array(model: nn.Module, arr: np.ndarray, device: torch.device | str = "cpu") -> tuple[int, np.ndarray]:
    x = torch.from_numpy(arr.astype(np.float32)).view(1, 1, IMAGE_SIZE, IMAGE_SIZE).to(device)
    logits = model(x)
    probs = torch.softmax(logits, dim=1).detach().cpu().numpy()[0]
    return int(probs.argmax()), probs


def save_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")

