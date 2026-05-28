"""
Generate MNIST-averaged digit templates for FPGA template matching.

Outputs:
  templates.hex  — 784 lines of 10-hex-digit values (40-bit packed: one nibble per digit)
  templates.png  — visual preview of all 10 templates

Usage:
  python gen_templates.py
"""

import numpy as np
import matplotlib.pyplot as plt
from tensorflow.keras.datasets import mnist


def main():
    (x_train, y_train), _ = mnist.load_data()

    # Average all training images per digit, normalize to 4-bit (0–15)
    templates = np.zeros((10, 28, 28), dtype=np.uint8)
    for d in range(10):
        imgs = x_train[y_train == d]
        avg = imgs.astype(np.float32).mean(axis=0)          # 0–255 float
        avg = np.clip(avg / 16.0, 0, 15).round().astype(np.uint8)  # -> 0–15
        # Invert: MNIST is white-on-black; our canvas is dark-on-white
        avg = 15 - avg
        templates[d] = avg

    # Write templates.hex: 784 lines, each a 40-bit hex word
    with open("templates.hex", "w") as f:
        for cell in range(784):
            row, col = divmod(cell, 28)
            # Templates stored column-major: iterate through grid rows then cols
            # Actually canvas_ram uses row-major: cell_y * 28 + cell_x
            row_idx, col_idx = divmod(cell, 28)
            packed = 0
            for d in range(10):
                packed |= int(templates[d, row_idx, col_idx]) << (d * 4)
            f.write(f"{packed:010X}\n")  # 10 hex digits, zero-padded

    print("Generated templates.hex — 784 lines, 40-bit packed")

    # Save visual preview: 2 rows × 5 columns of 28×28 templates
    fig, axes = plt.subplots(2, 5, figsize=(10, 5))
    for d in range(10):
        ax = axes[d // 5][d % 5]
        ax.imshow(templates[d], cmap="gray", vmin=0, vmax=15)
        ax.set_title(f"Digit {d}")
        ax.axis("off")
    fig.suptitle("MNIST-Averaged Templates (4-bit, inverted)")
    plt.tight_layout()
    plt.savefig("templates.png", dpi=150)
    plt.close()
    print("Saved templates.png — visual preview")


if __name__ == "__main__":
    main()