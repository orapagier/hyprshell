-- Personalized Hyprshell desktop. Edit the sections in hyprshell/hyprland/.
-- Resolve relative to this file so installed and checkout configs both work.
local source = debug.getinfo(1, "S").source:sub(2)
local directory = assert(source:match("^(.*)/"), "Expected a Hyprland config path")
local sections = directory .. "/../hyprshell/hyprland/"
local function load(name)
    return dofile(sections .. name .. ".lua")
end

load("monitors")
local programs = load("programs")
load("environment")
load("appearance")
load("layouts")
load("input")

-- Capture original Lua actions before applying Settings shortcut edits.
local hyprshellKeybindings = dofile(directory .. "/keybindings.lua")
hyprshellKeybindings.capture()
load("shortcuts")(programs)
load("windows")
load("startup")

-- Generated GUI settings apply after the editable defaults.
dofile(directory .. "/hyprland-gui.lua")
local config = os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config"
local function optional(name)
    local path = config .. "/hyprshell/" .. name .. ".lua"
    local file = io.open(path, "r")
    if file then
        file:close()
        dofile(path)
    end
end

-- Hyprshell settings override
optional("overrides")
hyprshellKeybindings.apply()
-- Confirmed display preferences override the automatic monitor fallback.
optional("displays")

-- Hyprshell behavior rules
optional("behavior")
