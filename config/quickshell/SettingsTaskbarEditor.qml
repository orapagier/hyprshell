pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "style" as Style
import "TaskbarModel.js" as Tasks

SettingsCard {
    id: editor
    required property var settings
    property var paneItems: []
    readonly property var inheritedItems: Tasks.rightItems({items:paneItems,panels:{hyprbar:{rightItems:null}}})
    readonly property var selectedItems: Array.isArray(settings.rightItems) ? settings.rightItems : inheritedItems
    readonly property var availableItems: [
        {id:'launcher',name:'Applications'}, {id:'settings',name:'Settings'},
        {id:'workspaces',name:'Workspaces'}, {id:'media',name:'Media'},
        {id:'calendar',name:'Clock and calendar'}, {id:'tray',name:'System tray'},
        {id:'notifications',name:'Notifications'}, {id:'audio',name:'Audio'},
        {id:'wifi',name:'Network'}, {id:'bluetooth',name:'Bluetooth'},
        {id:'battery',name:'Battery'}, {id:'power',name:'Power'}]
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
    Text { Layout.fillWidth:true; text:'Hyprbar right-side items'; color:Style.Theme.text }
    SettingsSwitch {
        Layout.fillWidth:true; text:'Use current Hyprpane right-side items'
        checked:editor.settings.rightItems === null || editor.settings.rightItems === undefined
        onToggled:editor.edited('rightItems',checked ? null : editor.inheritedItems.slice())
    }
    Repeater {
        model:editor.availableItems
        delegate: SettingsSwitch {
            required property var modelData
            Layout.fillWidth:true
            text:modelData.name
            checked:editor.selectedItems.indexOf(modelData.id) >= 0
            onToggled: {
                let selected=editor.selectedItems.slice();
                if (checked && selected.indexOf(modelData.id) < 0) selected.push(modelData.id);
                if (!checked) selected=selected.filter(id => id !== modelData.id);
                editor.edited('rightItems',selected);
            }
        }
    }
    SettingsSlider {
        Layout.fillWidth:true; label:'Hyprbar row thickness'; settingValue:editor.settings.thickness
        from:28; to:160; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('thickness',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; label:'Hyprbar icon size'; settingValue:editor.settings.iconSize
        from:8; to:96; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('iconSize',value)
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
