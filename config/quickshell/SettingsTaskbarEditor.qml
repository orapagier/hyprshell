pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "style" as Style

SettingsCard {
    id: editor
    required property var settings
    signal edited(string key, var value)
    title: 'Hyprbar'
    subtitle: 'Classic window taskbar. Choose a free edge or disable another panel before enabling. Manage shared or separate pins from Apps & windows.'
    SettingsSwitch {
        Layout.fillWidth:true; text:'Enable Hyprbar'; checked:editor.settings.enabled === true
        onToggled:editor.edited('enabled',checked)
    }
    Text { text:'Hyprbar screen edge'; color:Style.Theme.text }
    SettingsComboBox {
        Layout.fillWidth:true; model:['Top','Bottom','Left','Right']
        currentIndex:['top','bottom','left','right'].indexOf(editor.settings.position || 'bottom')
        Accessible.name:'Hyprbar screen edge'
        onActivated:editor.edited('position',['top','bottom','left','right'][currentIndex])
    }
    SettingsSwitch {
        Layout.fillWidth:true; text:'Group Hyprbar windows by application'; checked:editor.settings.grouped !== false
        onToggled:editor.edited('grouped',checked)
    }
    SettingsSwitch {
        Layout.fillWidth:true; text:'Show Hyprbar window titles'; checked:editor.settings.showTitles !== false
        onToggled:editor.edited('showTitles',checked)
    }
    SettingsSlider {
        Layout.fillWidth:true; label:'Hyprbar button width'; settingValue:editor.settings.buttonWidth
        from:80; to:400; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('buttonWidth',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; label:'Hyprbar side panel width'; settingValue:editor.settings.verticalWidth
        from:80; to:400; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('verticalWidth',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; label:'Hyprbar row thickness'; settingValue:editor.settings.thickness
        from:28; to:160; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('thickness',value)
    }
    Text { text:'Hyprbar windows from workspaces'; color:Style.Theme.text }
    SettingsComboBox {
        Layout.fillWidth:true; model:['Current workspace','All workspaces']
        currentIndex:editor.settings.windowWorkspaceScope === 'current' ? 0 : 1
        Accessible.name:'Hyprbar windows from workspaces'
        onActivated:editor.edited('windowWorkspaceScope',['current','all'][currentIndex])
    }
    Text { text:'Hyprbar windows from monitors'; color:Style.Theme.text }
    SettingsComboBox {
        Layout.fillWidth:true; model:['Current monitor','All monitors']
        currentIndex:editor.settings.windowMonitorScope === 'all' ? 1 : 0
        Accessible.name:'Hyprbar windows from monitors'
        onActivated:editor.edited('windowMonitorScope',['current','all'][currentIndex])
    }
    Text { text:'Hyprbar monitors (empty means all)'; color:Style.Theme.text }
    SettingsTextField {
        Layout.fillWidth:true; text:(editor.settings.monitors || []).join(', ')
        Accessible.name:'Hyprbar monitors'; placeholderText:'eDP-1, HDMI-A-1'
        onEditingFinished:editor.edited('monitors',text.split(',').map(s => s.trim()).filter(Boolean))
    }
}
