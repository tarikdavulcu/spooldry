#!/usr/bin/env python3
"""Render HTML/SVG files to PNG with headless Chromium (Playwright).

Usage:
  python3 tools/render.py <input.html|svg> <output.png> <width> <height> [--scale N]
"""
import pathlib
import sys

from playwright.sync_api import sync_playwright


def render_many(jobs, scale=1):
    """jobs: list of (input_path, output_path, width, height)."""
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for src, out, w, h in jobs:
            page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=scale)
            page.goto(pathlib.Path(src).resolve().as_uri())
            page.wait_for_timeout(250)
            page.evaluate("document.fonts && document.fonts.ready")
            pathlib.Path(out).parent.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(out), clip={"x": 0, "y": 0, "width": w, "height": h}, omit_background=False)
            page.close()
        browser.close()


if __name__ == "__main__":
    src, out, w, h = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    scale = int(sys.argv[sys.argv.index("--scale") + 1]) if "--scale" in sys.argv else 1
    render_many([(src, out, w, h)], scale)
    print(f"rendered {out}")
