import QtQuick
import QtTest
import "../KeybindingsGuide.js" as Guide

TestCase {
    name: "KeybindingsGuide"
    function test_no_bindings_filtered_or_collapsed() {
        let rows = [
            {modmask: 64, key: "P", description: "Duplicate or extend displays"},
            {modmask: 64, key: "P", description: "Release action", release: true},
            {modmask: 64, key: "P", description: "Submap action", submap: "resize"},
            {modmask: 255, keycode: 38, description: "Every modifier"},
            {modmask: 64, key: "mouse:272", mouse: true, description: "Drag window"},
            {modmask: 0, key: "XF86AudioRaiseVolume", repeat: true, locked: true},
            {modmask: 0, key: "", catch_all: true, dispatcher: "submap", arg: "reset"}
        ];
        let entries = Guide.desktopBindings(rows);
        compare(entries.length, rows.length);
        verify(entries.some(e => e.context === "Desktop · submap resize"));
        verify(entries.some(e => e.details.includes("On release")));
        verify(entries.some(e => e.shortcut.includes("Mod5") && e.shortcut.includes("Keycode 38")));
        verify(entries.some(e => e.details.includes("Mouse drag")));
        verify(entries.some(e => e.details.includes("Repeats") && e.details.includes("locked")));
        verify(entries.some(e => e.action === "submap reset"));
    }
    function test_super_release_is_one_key_and_media_keys_remain_searchable() {
        compare(Guide.shortcut({modmask: 64, key: "Super_L", release: true}), "Super");
        let bindings = Guide.desktopBindings([{key: "XF86AudioRaiseVolume", modmask: 0}]);
        compare(Guide.matching(bindings, "xf86audioraisevolume").length, 1);
        compare(Guide.matching(bindings, "volume up").length, 1);
        compare(Guide.matching(bindings, "fn f3").length, 1);
    }
    function test_duplicate_actions_use_correct_key_badges() {
        for (let symbol of Object.keys(Guide.laptopMediaKeys)) {
            let fnKey = Guide.laptopMediaKeys[symbol];
            let key = fnKey.split(" + ")[1];
            let entries = Guide.desktopBindings([
                {key: key, modmask: 0, description: "Media action", repeat: true},
                {key: symbol, modmask: 0, description: "Media action", repeat: true, locked: true}
            ]);
            compare(entries.length, 1);
            compare(entries[0].variants.length, 2);
            compare(entries[0].keyLabels.join(" / "), key + " / " + fnKey);
            compare(Guide.matching(entries, key).length, 1);
            compare(Guide.matching(entries, symbol).length, 1);
            verify(entries[0].details.includes(fnKey + ": Repeats while held · Available while locked"));
            verify(!entries[0].shortcut.includes("XF86"));
        }
        let entries = Guide.desktopBindings([
            {key: "L", modmask: 64, description: "Lock screen"},
            {key: "L", modmask: 72, description: "Lock screen"},
            {key: "L", modmask: 64, description: "Lock screen", submap: "test", release: true},
            {key: "Print", modmask: 0, description: "Capture screenshot region"},
            {key: "Insert", modmask: 0, description: "Capture screenshot region"}
        ]);
        compare(entries.length, 3);
        let screenshot = entries.find(e => e.action === "Capture screenshot region");
        compare(screenshot.keyLabels.join(" / "), "Print Screen");
        compare(screenshot.variants.length, 2);
        compare(Guide.matching(entries, "insert").length, 1);
        verify(entries.some(e => e.context === "Desktop · submap test" && e.details === "On release"));
    }
    function test_function_keys_letters_and_named_keys() {
        for (let i = 1; i <= 35; ++i)
            compare(Guide.shortcut({key: "F" + i, modmask: 0}), "F" + i);
        compare(Guide.shortcut({key: "z", modmask: 64}), "Super + Z");
        compare(Guide.shortcut({key: "left", modmask: 65}), "Super + Shift + Left");
        compare(Guide.shortcut({key: "Return", modmask: 0}), "Enter");
        compare(Guide.shortcut({key: "Prior", modmask: 0}), "Page Up");
        compare(Guide.shortcut({key: "Print", modmask: 0}), "Print Screen");
        compare(Guide.shortcut({key: "", modmask: 0}), "Unknown key");
        compare(Guide.shortcut({key: "", modmask: 0, catch_all: true}), "Any key");
        let bindings = Guide.desktopBindings([{key: "XF86AudioMicMute", modmask: 0},
            {key: "F1", modmask: 0}, {key: "Insert", modmask: 0}]);
        compare(Guide.matching(bindings, "f1").length, 1);
        compare(Guide.matching(bindings, "print screen").length, 1);
    }
    function test_search_context_and_no_unimplemented_power_sequences() {
        compare(Guide.matching([], "kitty").length, 2);
        compare(Guide.matching([], "settings ctrl f").length, 1);
        compare(Guide.matching([], "launcher enter").length, 1);
        compare(Guide.matching([], "recording escape").length, 1);
        verify(!Guide.localBindings.some(e => e.shortcut.startsWith("Alt + P +")));
        verify(Guide.localBindings.every(e => !!e.context));
    }
}
