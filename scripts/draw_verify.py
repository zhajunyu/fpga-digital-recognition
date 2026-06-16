from __future__ import annotations

import argparse
from pathlib import Path
import tkinter as tk
from tkinter import messagebox

import numpy as np
from PIL import Image, ImageDraw

from mlp_common import load_checkpoint, predict_array, preprocess_pil_digit


CANVAS_SIZE = 280
BRUSH_SIZE = 22


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Draw a digit and verify it with the trained MLP.")
    parser.add_argument("--model", type=Path, default=Path("artifacts/mlp/mnist_mlp.pt"))
    return parser.parse_args()


class DrawVerifier:
    def __init__(self, root: tk.Tk, model_path: Path) -> None:
        self.root = root
        self.root.title("FPGA Digit MLP Verifier")
        self.model, self.metadata = load_checkpoint(model_path)
        self.last_x: int | None = None
        self.last_y: int | None = None
        self.image = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), 255)
        self.draw = ImageDraw.Draw(self.image)

        self.canvas = tk.Canvas(root, width=CANVAS_SIZE, height=CANVAS_SIZE, bg="white", cursor="crosshair")
        self.canvas.grid(row=0, column=0, columnspan=4, padx=12, pady=12)
        self.canvas.bind("<ButtonPress-1>", self.start_stroke)
        self.canvas.bind("<B1-Motion>", self.paint)
        self.canvas.bind("<ButtonRelease-1>", self.end_stroke)

        self.result = tk.StringVar(value="Draw a digit, then Predict")
        tk.Label(root, textvariable=self.result, font=("Helvetica", 18)).grid(row=1, column=0, columnspan=4, pady=(0, 8))
        tk.Button(root, text="Predict", command=self.predict, width=10).grid(row=2, column=0, padx=6, pady=8)
        tk.Button(root, text="Clear", command=self.clear, width=10).grid(row=2, column=1, padx=6, pady=8)
        tk.Button(root, text="Save PNG", command=self.save, width=10).grid(row=2, column=2, padx=6, pady=8)
        tk.Button(root, text="Quit", command=root.destroy, width=10).grid(row=2, column=3, padx=6, pady=8)

    def start_stroke(self, event: tk.Event) -> None:
        self.last_x = int(event.x)
        self.last_y = int(event.y)
        self.paint(event)

    def end_stroke(self, _event: tk.Event) -> None:
        self.last_x = None
        self.last_y = None

    def paint(self, event: tk.Event) -> None:
        x = int(event.x)
        y = int(event.y)
        if self.last_x is None or self.last_y is None:
            self.last_x = x
            self.last_y = y
        self.canvas.create_line(
            self.last_x,
            self.last_y,
            x,
            y,
            width=BRUSH_SIZE,
            fill="black",
            capstyle=tk.ROUND,
            smooth=True,
        )
        self.draw.line((self.last_x, self.last_y, x, y), fill=0, width=BRUSH_SIZE)
        radius = BRUSH_SIZE // 2
        self.draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=0)
        self.last_x = x
        self.last_y = y

    def predict(self) -> None:
        arr = preprocess_pil_digit(self.image)
        if float(arr.sum()) < 1.0:
            messagebox.showinfo("No digit", "Draw a digit first.")
            return
        digit, probs = predict_array(self.model, arr)
        top3 = sorted(enumerate(probs), key=lambda item: item[1], reverse=True)[:3]
        self.result.set(f"Prediction: {digit}   confidence: {probs[digit]:.1%}   top3: " + " ".join(f"{d}:{p:.0%}" for d, p in top3))

    def clear(self) -> None:
        self.canvas.delete("all")
        self.image = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), 255)
        self.draw = ImageDraw.Draw(self.image)
        self.result.set("Draw a digit, then Predict")

    def save(self) -> None:
        out = Path("artifacts/mlp/user_digit.png")
        out.parent.mkdir(parents=True, exist_ok=True)
        self.image.save(out)
        self.result.set(f"Saved {out}")


def main() -> None:
    args = parse_args()
    if not args.model.exists():
        raise SystemExit(f"Missing model: {args.model}. Run `uv run python scripts/train_mlp.py` first.")
    root = tk.Tk()
    DrawVerifier(root, args.model)
    root.mainloop()


if __name__ == "__main__":
    main()

