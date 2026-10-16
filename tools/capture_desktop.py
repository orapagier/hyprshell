#!/usr/bin/env python3
"""Capture reviewed live desktop screenshots and update the README gallery."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
START = '<!-- desktop-screenshots:start -->'
END = '<!-- desktop-screenshots:end -->'
VIEWS = (
    ('desktop', 'Hyprshell desktop and Hyprpane',
     'Show your wallpaper and Hyprpane on a workspace without open windows.'),
    ('launcher', 'Hyprshell application launcher',
     'Show the application launcher over your desktop.'),
    ('settings', 'Hyprshell desktop settings',
     'Show Settings on an appearance or bar layout page.'),
    ('tiled', 'Hyprshell tiled windows',
     'Show two or more tiled application windows with public content and Hyprpane visible.'),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--view', choices=[view[0] for view in VIEWS],
                        help='Capture only this view, keeping the other screenshots.')
    args = parser.parse_args()
    views = [view for view in VIEWS if not args.view or view[0] == args.view]
    if not shutil.which('grim'):
        raise SystemExit('grim is required. Run this from your Hyprland desktop terminal.')
    readme = REPO / 'README.md'
    original = readme.read_text()
    if original.count(START) != 1 or original.count(END) != 1:
        raise SystemExit('README screenshot gallery markers are missing or ambiguous.')
    before, remainder = original.split(START)
    _, after = remainder.split(END)
    with tempfile.TemporaryDirectory(prefix='hyprshell-screenshots-') as directory:
        staging = Path(directory)
        # Check display access before asking the user to arrange any views.
        subprocess.run(['grim', str(staging / 'display-check.png')], check=True)
        print('Capture only public content; close private windows and notification popups.')
        print('Each capture starts 8 seconds after Enter. Hide this terminal during that time.')
        print('Return to this terminal after each capture. Ctrl+C cancels without changing the repo.')
        for name, caption, instruction in views:
            input(f'\n{caption}: {instruction}\nPress Enter when ready, then hide this terminal: ')
            time.sleep(8)
            subprocess.run(['grim', str(staging / f'hyprshell-{name}.png')], check=True)
            print(f'Captured {caption}.')
        print(f'\nReview these images in your image viewer or file manager: {staging}')
        answer = input('Do the captured images show the intended views without private content? Type save: ')
        if answer.strip() != 'save':
            print('Cancelled; repository unchanged.')
            return
        if readme.read_text() != original:
            raise SystemExit('README changed during capture; rerun to preserve those edits.')
        destination = REPO / 'docs/assets'
        destination.mkdir(parents=True, exist_ok=True)
        for name, _, _ in views:
            filename = f'hyprshell-{name}.png'
            shutil.copyfile(staging / filename, destination / filename)
        gallery = ['Captured from a running Hyprshell desktop.\n']
        for name, caption, _ in VIEWS:
            filename = f'hyprshell-{name}.png'
            if not (destination / filename).is_file():
                continue
            gallery.append(f'### {caption}\n\n![{caption}](docs/assets/{filename})\n')
        readme.write_text(before + START + '\n' + '\n'.join(gallery) + END + after)
        print(f'Saved {len(views)} screenshot(s) to docs/assets/ and updated README.md.')


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit('\nCancelled; repository unchanged.')
    except subprocess.CalledProcessError:
        raise SystemExit('Capture failed; run this from a terminal in your live Hyprland session.')
