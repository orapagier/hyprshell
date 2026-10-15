"""Exercise slideshow routing with compositor events and inert dispatchers."""
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PresentationRoutingTests(unittest.TestCase):
    def test_slideshow_lifecycle_and_display_modes(self):
        result = subprocess.run(['lua', '-', str(ROOT / 'config/hyprshell/hyprland/windows.lua')],
                                input=r'''
local events, moves, states, timers = {}, {}, {}, {}
local laptop = { name = 'eDP-1', is_mirror = false }
local hdmi = { name = 'HDMI-A-2', is_mirror = false }
local dp = { name = 'DP-1', is_mirror = false }
local workspace = { id = 2, monitor = laptop }
local monitors = { laptop, dp, hdmi }
local windows = {}
hl = {
    window_rule = function() end, layer_rule = function() end,
    on = function(event, callback) events[event] = callback end,
    get_monitors = function() return monitors end,
    get_windows = function() return windows end,
    get_window = function(selector)
        for _, w in ipairs(windows) do if selector == 'address:' .. w.address then return w end end
    end,
    timer = function(callback, options)
        assert(options.type == 'oneshot' and options.timeout > 0)
        local timer = { callback = callback, enabled = true }
        timer.set_enabled = function(self, enabled) self.enabled = enabled end
        table.insert(timers, timer)
        return timer
    end,
    get_monitor = function(name)
        for _, m in ipairs(monitors) do if m.name == name then return m end end
    end,
    get_workspace = function(id) if id == workspace.id then return workspace end end,
    dsp = { window = {
        move = function(args) args.kind = 'move'; return args end,
        fullscreen_state = function(args) args.kind = 'state'; return args end,
    } },
    dispatch = function(args)
        if args.kind == 'move' then table.insert(moves, args)
        else table.insert(states, args) end
    end,
}
local function settle()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do if timer.enabled then timer.callback() end end
end
dofile(arg[1])
local w = { address = '0x123', class = 'ONLYOFFICE',
    title = 'Example.pptx — ONLYOFFICE', fullscreen = 0, fullscreen_client = 0,
    monitor = laptop, workspace = workspace }
windows = { w }
events['window.open'](w)
assert(#moves == 0, 'editor must stay on laptop')
w.fullscreen, w.fullscreen_client = 2, 2
events['window.fullscreen'](w)
assert(#moves == 0, 'wait for initial X11 fullscreen request to settle')
settle()
assert(#moves == 1 and moves[1].monitor == hdmi and not moves[1].follow,
    'slideshow must follow the detected HDMI connector')
assert(#states == 2 and states[1].internal == 0 and states[2].internal == 2
    and states[1].client == 2 and states[2].client == 2,
    'recompute fullscreen geometry without ending the client slideshow')
w.monitor = hdmi
events['window.title'](w)
events['monitor.layout_changed']()
assert(#moves == 1, 'repeated events must not move again')
w.fullscreen, w.fullscreen_client = 0, 0
events['window.fullscreen'](w)
assert(#moves == 2 and moves[2].workspace == workspace, 'restore original workspace')
w.monitor = laptop
w.fullscreen, w.fullscreen_client = 2, 2
monitors = { laptop }
events['window.fullscreen'](w)
assert(#moves == 2, 'single display must be unchanged')
hdmi.is_mirror = true
monitors = { laptop, hdmi }
events['window.fullscreen'](w)
assert(#moves == 2, 'duplicate must be unchanged')
hdmi.is_mirror = false
events['monitor.layout_changed']()
settle()
assert(#moves == 3 and moves[3].monitor == hdmi, 'extend while already presenting')
-- A workspace can disappear after its only window moves away.
workspace = { id = 99, monitor = laptop }
w.fullscreen, w.fullscreen_client = 0, 0
events['window.fullscreen'](w)
assert(#moves == 4 and moves[4].monitor == laptop, 'restore to surviving monitor')
w.fullscreen, w.fullscreen_client = 2, 2
for _, title in ipairs({ 'Example.docx — ONLYOFFICE', 'Example.xlsx — ONLYOFFICE', 'ONLYOFFICE' }) do
    w.title = title
    events['window.fullscreen'](w)
end
w.title, w.class = 'Example.pptx — browser', 'firefox'
events['window.fullscreen'](w)
assert(#moves == 4, 'other documents and apps must stay untouched')
w.class, w.title, w.fullscreen_client = 'ONLYOFFICE', 'Example.pptx — ONLYOFFICE', 0
events['window.fullscreen'](w)
assert(#moves == 4, 'compositor-only fullscreen must stay untouched')
w.fullscreen_client = 2
events['window.open'](w)
settle()
events['window.close'](w)
w.fullscreen = 0
events['window.fullscreen'](w)
assert(#moves == 5, 'closed windows must not retain a return destination')
w.fullscreen = 2
events['window.open'](w)
events['window.close'](w)
settle()
assert(#moves == 5, 'closing before deferred placement must cancel the move')
''', text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
