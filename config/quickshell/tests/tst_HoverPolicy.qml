import QtQuick
import QtTest
import ".."
import "../SettingsModel.js" as Settings

Item {
    SettingsBarEditor {
        id: editor; visible: false
        settings: ({hoverPopdowns:true, hoverPopdownOverrides:{}, adaptiveColors:true, clockFormat:"hh:mm"})
        onEdited: (key, value) => { let next = Settings.copy(settings); next[key] = value; settings = next; }
    }
    MenuController { id: menus }
    DockMenuController { id: dockMenus }
    TestCase {
        name: "HoverPolicy"; when: windowShown
        function cleanup() { menus.close(); dockMenus.close(); menus.hoverEnabled = true; dockMenus.hoverEnabled = true; }
        function test_editorSavesIndependentWorkspaceChoices() {
            editor.settings = {hoverPopdowns:true, hoverPopdownOverrides:{}, adaptiveColors:true, clockFormat:"hh:mm"};
            editor.hoverWorkspace = 2;
            let toggle = findChild(editor, "hoverPopdownWorkspaceEnabledControl");
            verify(toggle); compare(toggle.checked, true);
            toggle.checked = false; toggle.toggled();
            compare(editor.settings.hoverPopdownOverrides['2'], false);
            toggle.checked = Qt.binding(() => Settings.hoverPopdownsEnabled(editor.settings, editor.hoverWorkspace));
            editor.hoverWorkspace = 3; compare(toggle.checked, true);
            let defaults = findChild(editor, "hoverPopdownsDefaultControl");
            defaults.checked = false; defaults.toggled();
            compare(toggle.checked, false);
            toggle.checked = true; toggle.toggled();
            compare(editor.settings.hoverPopdownOverrides['3'], true);
            compare(editor.settings.hoverPopdownOverrides['2'], false);
        }
        function test_workspaceDefaultsAndOverrides() {
            compare(Settings.hoverPopdownsEnabled({}, 2), true);
            let bar = {hoverPopdowns:true, hoverPopdownOverrides:{'2':false}};
            compare(Settings.hoverPopdownsEnabled(bar, 2), false);
            compare(Settings.hoverPopdownsEnabled(bar, 3), true);
            bar.hoverPopdowns = false; bar.hoverPopdownOverrides['3'] = true;
            compare(Settings.hoverPopdownsEnabled(bar, 3), true);
            compare(Settings.hoverPopdownsEnabled(bar, 4), false);
            compare(Settings.hoverPopdownsEnabled(bar, null), false);
        }
        function test_workspaceChangeCancelsDelayedHover() {
            menus.hover('audio'); menus.hoverEnabled = false;
            wait(160); compare(menus.section, '');
            menus.activate('audio'); menus.hover('wifi');
            wait(160); compare(menus.section, 'audio');
            menus.activate('wifi'); compare(menus.section, 'wifi');
        }
        function test_dockPreviewRequiresClickWhenDisabled() {
            let rect = Qt.rect(10, 20, 30, 40);
            dockMenus.hoverEnabled = false;
            dockMenus.hoverItem('previews','app',rect);
            wait(160); compare(dockMenus.section, '');
            dockMenus.activateItem('previews','app',rect);
            compare(dockMenus.mode, 'previews'); compare(dockMenus.groupKey, 'app');
            dockMenus.hoverItem('launcher','',rect);
            wait(160); compare(dockMenus.mode, 'previews');
            dockMenus.activateItem('launcher','',rect); compare(dockMenus.mode, 'launcher');
        }
    }
}
