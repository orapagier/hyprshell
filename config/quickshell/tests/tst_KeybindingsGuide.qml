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
