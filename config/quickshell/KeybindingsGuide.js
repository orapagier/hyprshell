.pragma library

// Local controls do not appear in Hyprland's global binding registry.
const localBindings = [
    {shortcut: "Ctrl + F", action: "Focus Settings search", context: "Settings"},
    {shortcut: "Up / Down", action: "Select a Settings search result", context: "Settings search"},
    {shortcut: "Enter", action: "Open the selected Settings search result", context: "Settings search"},
    {shortcut: "Escape", action: "Clear the Settings search", context: "Settings search with text"},
    {shortcut: "Up / Down", action: "Select an application", context: "Application launcher"},
    {shortcut: "Enter", action: "Launch the selected application", context: "Application launcher"},
    {shortcut: "Escape", action: "Close the open menu", context: "Bar menus and application launcher"},
    {shortcut: "Up / Down", action: "Browse shortcuts", context: "Shortcut guide"},
    {shortcut: "Escape", action: "Close the shortcut guide", context: "Shortcut guide"},
    {shortcut: "Escape", action: "Cancel shortcut recording", context: "Settings · recording a shortcut"},
    {shortcut: "Tab / Shift + Tab", action: "Focus the next / previous control", context: "Shell controls"},
    {shortcut: "Space / Enter", action: "Activate the focused button", context: "Shell buttons"},
    {shortcut: "Left / Right", action: "Adjust the focused slider", context: "Settings sliders"},
    {shortcut: "Up / Down", action: "Change the focused number or list selection", context: "Settings numeric fields and lists"},
    {shortcut: "Home / End", action: "Move to the start / end of the text", context: "Shell text fields"},
    {shortcut: "Ctrl + A", action: "Select all text", context: "Shell text fields"},
    {shortcut: "Ctrl + C / Ctrl + X / Ctrl + V", action: "Copy / cut / paste text", context: "Shell text fields"},
    {shortcut: "Ctrl + Z / Ctrl + Shift + Z", action: "Undo / redo text editing", context: "Shell text fields"},
    {shortcut: "Shift + Left / Right / Home / End", action: "Extend the text selection", context: "Shell text fields"},
    {shortcut: "Ctrl + Left / Right", action: "Move by word", context: "Shell text fields"},
    {shortcut: "Backspace / Delete", action: "Delete text before / after the cursor", context: "Shell text fields"},
    {shortcut: "Ctrl + C", action: "Copy selection, or interrupt if nothing is selected", context: "Kitty terminal · configured mapping"},
    {shortcut: "Ctrl + V", action: "Paste text or let the terminal application handle an image attachment", context: "Kitty terminal · configured mapping"}
];

// Function-row alternatives documented in this desktop's shortcuts.lua.
const laptopMediaKeys = {
    XF86AudioMicMute: "Fn + F1", XF86AudioLowerVolume: "Fn + F2",
    XF86AudioRaiseVolume: "Fn + F3", XF86AudioMute: "Fn + F4",
    XF86MonBrightnessDown: "Fn + F6", XF86MonBrightnessUp: "Fn + F7"
};
const mediaKeyNames = {
    XF86AudioMicMute: "Microphone mute", XF86AudioLowerVolume: "Volume down",
    XF86AudioRaiseVolume: "Volume up", XF86AudioMute: "Speaker mute",
    XF86MonBrightnessDown: "Brightness down", XF86MonBrightnessUp: "Brightness up"
};

function shortcut(binding) {
    let parts = [];
    for (let modifier of [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"],
                           [2, "Caps Lock"], [16, "Mod2"], [32, "Mod3"], [128, "Mod5"]])
        if (binding.modmask & modifier[0]) parts.push(modifier[1]);
    let unknown = (binding.modmask || 0) & ~255;
    if (unknown) parts.push("Modifier " + unknown);
    let key = binding.key || (binding.keycode ? "Keycode " + binding.keycode : binding.catch_all ? "Any key" : "Unknown key");
    if ((key === "Super_L" || key === "Super_R") && binding.modmask === 64)
        return key === "Super_R" ? "Right Super" : "Super";
    key = laptopMediaKeys[key] || ({"Super_L":"Left Super", "Super_R":"Right Super", "left":"Left", "right":"Right",
        "up":"Up", "down":"Down", "BackSpace":"Backspace", "Prior":"Page Up", "Next":"Page Down",
        "Print":"Print Screen", "Insert":"Print Screen", "Caps_Lock":"Caps Lock", "Num_Lock":"Num Lock", "Scroll_Lock":"Scroll Lock",
        "KP_Enter":"Numpad Enter", "mouse:272":"Left mouse",
        "mouse:273":"Right mouse", "mouse:274":"Middle mouse", "mouse_down":"Scroll down",
        "mouse_up":"Scroll up", "mouse_left":"Scroll left", "mouse_right":"Scroll right",
        "Return":"Enter", "space":"Space", "XF86AudioNext":"Next track key",
        "XF86AudioPrev":"Previous track key", "XF86AudioPlay":"Play key",
        "XF86AudioPause":"Pause key"})[key] || key;
    parts.push(key.length === 1 ? key.toUpperCase() : key);
    return parts.join(" + ");
}

function desktopBindings(rows) {
    // One card per action and context, with all registrations retained as variants.
    let groups = [];
    rows.forEach(b => {
        let details = [];
        if (b.key === "Insert") details.push("This laptop's Print Screen key sends Insert");
        if (b.release) details.push("On release");
        if (b.repeat || b.repeating) details.push("Repeats while held");
        if (b.mouse) details.push("Mouse drag");
        if (b.locked) details.push("Available while locked");
        if (b.non_consuming) details.push("Also passes to the application");
        if (b.longPress || b.longpress) details.push("Long press");
        if (b.catch_all) details.push("Any key");
        let action = b.description || [b.dispatcher, b.arg].filter(Boolean).join(" ") || "Custom action";
        let context = b.submap ? "Desktop · submap " + b.submap : "Desktop";
        let group = groups.find(g => g.action === action && g.context === context);
        if (!group) {
            group = {action: action, context: context, variants: []};
            groups.push(group);
        }
        group.variants.push({shortcut: shortcut(b), details: details.join(" · "), key: b.key || ""});
    });
    return groups.map(group => {
        group.keyLabels = [...new Set(group.variants.map(v => v.shortcut))].sort((a, b) => a.localeCompare(b));
        group.shortcut = group.keyLabels.join(" / ");
        group.searchTerms = group.variants.map(v => v.key + " " + (mediaKeyNames[v.key] || "")).join(" ");
        let descriptions = [...new Set(group.variants.map(v => v.details))];
        if (descriptions.length === 1) group.details = descriptions[0];
        else group.details = [...new Set(group.variants.map(v => v.shortcut + ": " + (v.details || "On press")))].join(" · ");
        return group;
    }).sort((a, b) => a.shortcut.localeCompare(b.shortcut) || a.context.localeCompare(b.context));
}

function matching(bindings, query) {
    let words = query.toLowerCase().trim().split(/\s+/);
    return bindings.concat(localBindings).filter(b => {
        let haystack = [b.shortcut, b.action, b.context, b.details || "", b.searchTerms || ""].join(" ").toLowerCase();
        return words.every(word => haystack.includes(word));
    });
}
