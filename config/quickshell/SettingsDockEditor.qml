pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "style" as Style

SettingsCard {
    id: editor
    required property var settings
    signal edited(string key, var value)
    title: 'Hyprdock'
    subtitle: 'Pinned and running apps on a separate edge. Choose visibility, utilities and placement below. Manage pins from the launcher or an app’s context menu. Targets stay at least 36 px; larger icons can increase thickness.'
    SettingsSwitch {
        objectName:'dockEnabledControl'
        Layout.fillWidth:true
        text:'Enable Hyprdock'
        checked:editor.settings.enabled === true
        onToggled:editor.edited('enabled',checked)
    }
    SettingsComboBox {
        objectName:'dockEdgeControl'
        Layout.fillWidth:true
        model:['Top','Bottom','Left','Right']
        currentIndex:['top','bottom','left','right'].indexOf(editor.settings.position || 'bottom')
        Accessible.name:'Hyprdock screen edge'
        onActivated:editor.edited('position',['top','bottom','left','right'][currentIndex])
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockTransparencyControl'
        label:'Dock transparency'; description:'Fades the dock background while keeping app icons readable.'
        settingValue:editor.settings.backgroundOpacity ?? (230 / 255); inverted:true
        from:0; to:100; suffix:'%'; allowReset:false
        onEdited:value => editor.edited('backgroundOpacity',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockEdgeMarginControl'
        label:'Dock distance from screen edge'; description:'Space between the dock and its selected screen edge.'
        settingValue:editor.settings.marginEdge; from:0; to:100; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('marginEdge',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockThicknessControl'
        label:'Dock thickness'; settingValue:editor.settings.thickness; from:28; to:160; allowReset:false
        onEdited:value => editor.edited('thickness',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockIconSizeControl'
        label:'Dock icon size'; settingValue:editor.settings.iconSize; from:8; to:96; allowReset:false
        onEdited:value => editor.edited('iconSize',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockSpacingControl'
        label:'Dock spacing'; settingValue:editor.settings.spacing; from:0; to:30; allowReset:false
        onEdited:value => editor.edited('spacing',value)
    }
    Text { Layout.fillWidth:true; text:'Dock visibility'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockHideControl'; Layout.fillWidth:true
        model:["Always visible", "Auto-hide", "Hide when overlapped"]
        Accessible.name:'Dock visibility'
        currentIndex:["always", "auto-hide", "dodge"].indexOf(editor.settings.hideMode || 'always')
        onActivated:editor.edited('hideMode',["always", "auto-hide", "dodge"][currentIndex])
    }

    Text { Layout.fillWidth:true; text:'Dock in fullscreen'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockFullscreenControl'; Layout.fillWidth:true
        model:["Hide during fullscreen", "Show over fullscreen"]
        Accessible.name:'Dock in fullscreen'
        currentIndex:["hide", "show"].indexOf(editor.settings.fullscreenPolicy || 'hide')
        onActivated:editor.edited('fullscreenPolicy',["hide", "show"][currentIndex])
    }

    Text { Layout.fillWidth:true; text:'Dock alignment'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockAlignmentControl'; Layout.fillWidth:true
        model:["Start", "Center", "End"]
        Accessible.name:'Dock alignment'
        currentIndex:["start", "center", "end"].indexOf(editor.settings.alignment || 'center')
        onActivated:editor.edited('alignment',["start", "center", "end"][currentIndex])
    }

    Text { Layout.fillWidth:true; text:'Dock background'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockBackgroundControl'; Layout.fillWidth:true
        model:["Follow Hyprpane", "On", "Off"]
        Accessible.name:'Dock background'
        currentIndex:["inherit", "on", "off"].indexOf(editor.settings.background || 'inherit')
        onActivated:editor.edited('background',["inherit", "on", "off"][currentIndex])
    }

    Text { Layout.fillWidth:true; text:'Dock workspace scope'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockWorkspaceScopeControl'; Layout.fillWidth:true
        model:["All workspaces", "Selected workspaces"]
        Accessible.name:'Dock workspace scope'
        currentIndex:["all", "selected"].indexOf(editor.settings.workspaceScope || 'all')
        onActivated:editor.edited('workspaceScope',["all", "selected"][currentIndex])
    }

    SettingsSlider {
        Layout.fillWidth:true; label:'Dock end margins'; settingValue:editor.settings.marginEnds
        from:0; to:200; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('marginEnds',value)
    }

    SettingsSlider {
        Layout.fillWidth:true; label:'Dock window gap'; settingValue:editor.settings.windowGap
        from:0; to:100; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('windowGap',value)
    }

    SettingsSwitch {
        Layout.fillWidth:true; text:'Show running indicators'; checked:editor.settings.indicators === true
        onToggled:editor.edited('indicators',checked)
    }

    SettingsSwitch {
        Layout.fillWidth:true; text:'Animate dock visibility'; checked:editor.settings.animations === true
        onToggled:editor.edited('animations',checked)
    }

    SettingsSwitch {
        Layout.fillWidth:true; text:'Show Files shortcut'; checked:editor.settings.showFiles === true
        onToggled:editor.edited('showFiles',checked)
    }

    SettingsSwitch {
        Layout.fillWidth:true; text:'Show Settings shortcut'; checked:editor.settings.showSettings === true
        onToggled:editor.edited('showSettings',checked)
    }

    SettingsSwitch {
        Layout.fillWidth:true; text:'Show Trash'; checked:editor.settings.showTrash === true
        onToggled:editor.edited('showTrash',checked)
    }

    Text { Layout.fillWidth:true; text:'Dock monitors (empty means all)'; color:Style.Theme.text }
    SettingsTextField {
        objectName:'dockMonitorsControl'; Layout.fillWidth:true
        text:(editor.settings.monitors || []).join(', ')
        placeholderText:'eDP-1, HDMI-A-1'
        Accessible.name:'Dock monitors'
        onEditingFinished:editor.edited('monitors', text.split(',').map(s => s.trim()).filter(Boolean))
    }
    Text { Layout.fillWidth:true; text:'Dock selected workspaces (1–99)'; color:Style.Theme.text }
    SettingsTextField {
        objectName:'dockWorkspacesControl'; Layout.fillWidth:true
        text:(editor.settings.workspaceList || []).join(', ')
        placeholderText:'1, 2, 3'
        Accessible.name:'Dock selected workspaces'
        onEditingFinished:editor.edited('workspaceList', text.split(',').map(s => s.trim()).filter(Boolean).map(Number))
    }

}
