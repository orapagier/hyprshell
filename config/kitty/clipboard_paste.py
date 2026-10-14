"""Keep one-handed text paste while forwarding image paste to terminal apps."""
from kittens.tui.handler import result_handler


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, result, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    try:
        formats = boss.clipboard.get_available_mime_types_for_paste()
    except RuntimeError:
        # If clipboard formats cannot be queried, keep the app's native key.
        window.send_key('ctrl+v')
        return
    if any(mime.lower().startswith('image/') for mime in formats):
        # Kitty encodes both press and release using the app's key protocol.
        # The app reads the image itself; no image data is saved here.
        window.send_key('ctrl+v')
    else:
        boss.paste_from_clipboard()
