#!/usr/bin/env python3
"""Emit wallpaper cache/socket invalidations; never read cache contents.

awww has no subscription CLI. inotify accelerates the common image path; the
QML owner keeps a slow query fallback for clear, disabled caches and lost events.
"""
import ctypes
import os
from pathlib import Path
import select
import struct
import sys

MASK = 0x00000008 | 0x00000080 | 0x00000100 | 0x00000200 | 0x00000400 | 0x00000800
DIRECTORY = 0x40000000
OVERFLOW = 0x00004000
IGNORED = 0x00008000


class Watcher:
    def __init__(self, cache, runtime=None):
        self.cache = Path(cache)
        self.runtime = Path(runtime) if runtime else None
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
        os.close(self.fd)

    def refresh(self):
        # Watch the nearest existing ancestor too, so cache deletion/recreation
        # and first use work without restarting the shell.
        ancestor = self.cache.parent
        while not ancestor.is_dir() and ancestor != ancestor.parent:
            ancestor = ancestor.parent
        desired = {ancestor}
        if self.cache.is_dir():
            desired.add(self.cache)
            desired.update(p for p in self.cache.iterdir() if p.is_dir() and not p.is_symlink())
        if self.runtime and self.runtime.is_dir():
            desired.add(self.runtime)
        for wd, path in list(self.paths.items()):
            if path not in desired:
                self.libc.inotify_rm_watch(self.fd, wd)
                del self.paths[wd]
        for path in desired - set(self.paths.values()):
            wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), MASK)
            if wd < 0:
                raise OSError(ctypes.get_errno(), 'inotify_add_watch')
            self.paths[wd] = path

    def read_changes(self):
        changed = False
        refresh = False
        while True:
            try:
                data = os.read(self.fd, 65536)
            except BlockingIOError:
                break
            offset = 0
            while offset < len(data):
                wd, mask, cookie, size = struct.unpack_from('iIII', data, offset)
                name = os.fsdecode(data[offset + 16:offset + 16 + size].split(b'\0', 1)[0])
                offset += 16 + size
                directory = self.paths.get(wd)
                if mask & OVERFLOW:
                    changed = refresh = True
                if mask & IGNORED:
                    self.paths.pop(wd, None)
                    changed = refresh = True
                if directory is None:
                    continue
                path = directory / name
                relevant = (path == self.cache or self.cache in path.parents
                            or path in self.cache.parents
                            or (directory == self.runtime and 'awww' in name))
                if relevant:
                    changed = True
                    refresh |= bool(mask & (DIRECTORY | 0x400 | 0x800))
        if refresh:
            self.refresh()
        return changed


def main():
    cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'awww'
    watcher = Watcher(cache, os.environ.get('XDG_RUNTIME_DIR'))
    try:
        print('ready', flush=True)
        while True:
            select.select([watcher.fd], [], [])
            if watcher.read_changes():
                print('change', flush=True)
    finally:
        watcher.close()


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print('Wallpaper event watcher unavailable: ' + str(error), file=sys.stderr)
        sys.exit(1)
