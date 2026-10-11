#!/usr/bin/env python3
"""Render Hyprlock's static card using the saved Hyprshell login artwork."""
import base64
from pathlib import Path
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[1]


def render():
    source = REPO / 'config/sddm/hyprshell-glass'
    target = REPO / 'config/hypr/lock-assets'
    target.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / 'background.png', target / 'background.png')
    layers = [('card', 0, 0, 900, 760),
              ('title-glow', 190, 108, 520, 140),
              ('title', 190, 108, 520, 140)]
    images = []
    for name, x, y, width, height in layers:
        data = base64.b64encode((source / (name + '.png')).read_bytes()).decode()
        images.append(f'<image x="{x}" y="{y}" width="{width}" height="{height}" '
                      f'href="data:image/png;base64,{data}"/>')
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="760">' + ''.join(images) + '</svg>'
    subprocess.run(['rsvg-convert', '-o', str(target / 'card.png')], input=svg.encode(), check=True)
    print('Rendered Hyprshell lock artwork.')


if __name__ == '__main__':
    render()
