#!/usr/bin/env python3
"""Stream the fallback icon catalog from one inotify watch set.

The shell starts this helper lazily when a themed icon lookup misses. Each
stdout line is one JSON object: a revision, the complete catalog, and the
protocol version. Qt's FolderListModel ordering and fileUrl formatting are
reproduced so the fallback lookup keeps its existing priority semantics.
"""
import argparse
import ctypes
import errno
import json
import os
from pathlib import Path
import select
import struct
import sys
from urllib.parse import unquote, urlsplit

VERSION = 1
SUFFIXES = ('.svg', '.png', '.xpm')
# MODIFY, ATTRIB, CLOSE_WRITE, MOVED_FROM/TO, CREATE, DELETE, DELETE_SELF, MOVE_SELF.
MASK = 0x2 | 0x4 | 0x8 | 0x40 | 0x80 | 0x100 | 0x200 | 0x400 | 0x800
OVERFLOW, IGNORED = 0x4000, 0x8000


def file_url(path):
    """Format a local path like FolderListModel.fileUrl (Qt leaves space/UTF-8)."""
    escaped = ''.join(
        '%%%02X' % ord(character)
        if character in '%#?' or ord(character) < 0x20 or ord(character) == 0x7f
        else character
        for character in str(path))
    return 'file://' + escaped


def folders_from_json(value):
    rows = json.loads(value)
    if not isinstance(rows, list) or not 1 <= len(rows) <= 256:
        raise ValueError('Expected 1–256 icon folders')
    result = []
    for row in rows:
        if not isinstance(row, str):
            raise ValueError('Folder must be a local path or file URL')
        if row.startswith('file:'):
            url = urlsplit(row)
            if url.netloc not in ('', 'localhost') or url.query or url.fragment:
                raise ValueError('Expected a local file URL without query or fragment')
            row = unquote(url.path)
        path = Path(row)
        if not path.is_absolute():
            raise ValueError('Icon folders must be absolute')
        if path not in result:
            result.append(path)
    return result


def scan(folders):
    catalog = {}
    for folder in folders:
        try:
            with os.scandir(folder) as entries:
                names = []
                for entry in entries:
                    if entry.name.startswith('.') or not entry.name.endswith(SUFFIXES):
                        continue
                    try:
                        if entry.is_file():
                            names.append(entry.name)
                    except OSError:
                        continue  # A removed, inaccessible or looping symlink is not an icon.
                names.sort(key=lambda name: name.encode('utf-16-be', 'surrogatepass'))
        except (FileNotFoundError, NotADirectoryError, PermissionError):
            continue
        for name in names:
            key = name.rsplit('.', 1)[0]
            catalog.setdefault(key, file_url(folder / name))
    return catalog


class Watcher:
    """One inotify FD for configured folders and their recreation ancestors."""
    def __init__(self, folders):
        self.folders = folders
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.libc.inotify_init1.argtypes = [ctypes.c_int]
        self.libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        self.libc.inotify_rm_watch.argtypes = [ctypes.c_int, ctypes.c_int]
        self.fd = self.libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), 'inotify_init1')
        self.paths = {}
        try:
            self.refresh()
        except Exception:
            self.close()
            raise

    def close(self):
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1

    def refresh(self):
        # Retain lexical aliases: symlink replacement is observed at its parent,
        # while file changes are observed on the target inode's watch.
        desired = {p for folder in self.folders for p in (folder, *folder.parents) if p.is_dir()}
        next_paths = {}
        for path in sorted(desired):
            wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), MASK)
            if wd < 0:
                error = ctypes.get_errno()
                if error in (errno.ENOENT, errno.ENOTDIR, errno.EACCES):
                    continue  # Existing accessible ancestors cover recovery.
                raise OSError(error, 'inotify_add_watch', str(path))
            next_paths.setdefault(wd, set()).add(path)
        for wd in self.paths.keys() - next_paths.keys():
            self.libc.inotify_rm_watch(self.fd, wd)
        self.paths = next_paths

    def relevant(self, directory, name):
        if directory in self.folders:
            if not name or (not name.startswith('.') and name.endswith(SUFFIXES)):
                return True
        path = directory / name if name else directory
        return any(path == folder or path in folder.parents for folder in self.folders)

    def changed(self):
        changed = False
        # Drain the currently queued burst; do not impose a first-use debounce.
        for _ in range(256):
            try:
                data = os.read(self.fd, 65536)
            except BlockingIOError:
                break
            offset = 0
            while offset < len(data):
                wd, mask, cookie, size = struct.unpack_from('iIII', data, offset)
                name = os.fsdecode(data[offset + 16:offset + 16 + size].split(b'\0', 1)[0])
                offset += 16 + size
                if mask & OVERFLOW:
                    changed = True
                paths = self.paths.get(wd, set())
                if any(self.relevant(path, name) for path in paths):
                    changed = True
                if mask & IGNORED:
                    self.paths.pop(wd, None)
                    changed = True
        if changed:
            self.refresh()
        return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--folders-json', required=True)
    args = parser.parse_args()
    folders = folders_from_json(args.folders_json)
    watcher = Watcher(folders)
    revision = 0
    try:
        while True:
            # Emit even when a write preserves the filename: consumers must see
            # content invalidation. QML image-cache integration is still pending.
            print(json.dumps({'version': VERSION, 'revision': revision,
                              'catalog': scan(folders)}), flush=True)
            while True:
                select.select([watcher.fd], [], [])
                if watcher.changed():
                    break
            revision += 1
    finally:
        watcher.close()


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print('Icon catalog unavailable: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
