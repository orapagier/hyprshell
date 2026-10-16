pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

SettingsCard {
    id: editor
    required property var settings
    signal edited(string key, var value)
    title: 'Hyprdock'
    subtitle: 'Pinned and running apps on a separate edge. Always visible in this phase; automatic hiding and utilities arrive next. Manage pins from the launcher or an app’s context menu. Targets stay at least 36 px; larger icons can increase thickness.'
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
}
