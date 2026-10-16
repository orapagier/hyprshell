pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "style" as Style
import "TaskbarModel.js" as Tasks
import "SettingsModel.js" as Model

SettingsCard {
    id: editor
    objectName: component + 'Editor'
    required property var settings
    property string component: 'hyprdock'
    property int currentWorkspace: 1
    property int selectedWorkspace: currentWorkspace >= 1 && currentWorkspace <= 99 ? currentWorkspace : 1
    property var paneItems: []
    property real paneSpacing: 3
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
    signal visibilityEdited(var settings)
    title: component === 'hyprbar' ? 'Hyprbar' : 'Hyprdock'
    subtitle: 'Shared app and window controls. Hyprdock fits its contents; Hyprbar fills the edge. Icons fit inside the chosen pill thickness. Manage shared or separate pins from Apps & windows.'
    SettingsSwitch {
        objectName:'dockEnabledControl'
        Layout.fillWidth:true
        text:editor.component === 'hyprbar' ? 'Enable Hyprbar' : 'Enable Hyprdock'
        checked:editor.settings.enabled === true
        onToggled:editor.edited('enabled',checked)
    }
    SettingsComboBox {
        objectName:'dockEdgeControl'
        Layout.fillWidth:true
        model:['Top','Bottom','Left','Right']
        currentIndex:['top','bottom','left','right'].indexOf(editor.settings.position || 'bottom')
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar screen edge' : 'Dock screen edge'
        onActivated:editor.edited('position',['top','bottom','left','right'][currentIndex])
    }
    Text {
        Layout.fillWidth:true
        text:editor.component === 'hyprbar' ? 'Hyprbar workspace visibility' : 'Hyprdock workspace visibility'
        color:Style.Theme.text
    }
    Text {
        Layout.fillWidth:true
        text:'Panels can share an edge on separate workspaces. Hide on all, then turn on the workspaces where this panel should appear. The Enable switch above remains the master switch.'
        color:Style.Theme.muted
        wrapMode:Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth:true
        SettingsButton {
            objectName:editor.component + 'ShowAllControl'
            Layout.fillWidth:true
            text:'Show on all'
            onClicked:editor.visibilityEdited(Model.withAllBarVisibility(editor.settings,true))
        }
        SettingsButton {
            objectName:editor.component + 'HideAllControl'
            Layout.fillWidth:true
            text:'Hide on all'
            onClicked:editor.visibilityEdited(Model.withAllBarVisibility(editor.settings,false))
        }
    }
    SettingsComboBox {
        objectName:editor.component + 'WorkspaceControl'
        Layout.fillWidth:true
        model:Array.from({length:99},(_,i) => 'Workspace ' + (i+1))
        currentIndex:editor.selectedWorkspace-1
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar individual workspace' : 'Hyprdock individual workspace'
        onActivated:index => editor.selectedWorkspace=index+1
    }
    SettingsSwitch {
        objectName:editor.component + 'WorkspaceVisibleControl'
        Layout.fillWidth:true
        text:(editor.component === 'hyprbar' ? 'Show Hyprbar on workspace ' : 'Show Hyprdock on workspace ') + editor.selectedWorkspace
        checked:Model.barVisible(editor.settings,editor.selectedWorkspace)
        onToggled:editor.visibilityEdited(Model.withWorkspaceVisibility(editor.settings,editor.selectedWorkspace,checked))
    }
    Text {
        Layout.fillWidth:true
        text: {
            let choices=Object.keys(editor.settings.workspaceOverrides || {}).sort((a,b) => Number(a)-Number(b));
            let baseline=editor.settings.visible === false ? 'Hidden by default.' :
                editor.settings.workspaceScope === 'selected' ? 'Shown by default on workspaces ' + (editor.settings.workspaceList || []).join(', ') + '.' : 'Shown by default on all workspaces.';
            return baseline + (choices.length ? ' Individual choices: ' + choices.map(w => w + (editor.settings.workspaceOverrides[w] ? ' on' : ' off')).join(', ') + '.' : '');
        }
        color:Style.Theme.muted
        wrapMode:Text.WordWrap
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockTransparencyControl'
        label:editor.component === 'hyprbar' ? 'Hyprbar transparency' : 'Dock transparency'; description:'Fades the panel background while keeping app icons readable.'
        settingValue:editor.settings.backgroundOpacity ?? (230 / 255); inverted:true
        from:0; to:100; suffix:'%'; allowReset:false
        onEdited:value => editor.edited('backgroundOpacity',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockEdgeMarginControl'
        label:editor.component === 'hyprbar' ? 'Hyprbar distance from screen edge' : 'Dock distance from screen edge'; description:'Space between the dock and its selected screen edge.'
        settingValue:editor.settings.marginEdge; from:0; to:100; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('marginEdge',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockThicknessControl'
        label:editor.component === 'hyprbar' ? 'Hyprbar thickness' : 'Dock thickness'; settingValue:editor.settings.thickness; from:28; to:160; allowReset:false
        onEdited:value => editor.edited('thickness',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockIconSizeControl'
        label:editor.component === 'hyprbar' ? 'Hyprbar icon size' : 'Dock icon size'; settingValue:editor.settings.iconSize; from:8; to:96; allowReset:false
        onEdited:value => editor.edited('iconSize',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockSpacingControl'
        label:editor.component === 'hyprbar' ? 'Hyprbar left item spacing' : 'Dock spacing'; settingValue:editor.settings.spacing; from:0; to:30; allowReset:false
        onEdited:value => editor.edited('spacing',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'taskbarRightSpacingControl'
        visible:editor.component === 'hyprbar'
        label:'Hyprbar right item spacing'; settingValue:editor.settings.spacingRight ?? editor.paneSpacing
        from:0; to:30; allowReset:false
        onEdited:value => editor.edited('spacingRight',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockStartPaddingControl'
        label:editor.settings.position === 'left' || editor.settings.position === 'right' ? 'Top inside padding' : 'Left inside padding'
        description:'Space inside the pill before the first item.'
        settingValue:editor.settings.paddingStart ?? 6
        from:0; to:100; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('paddingStart',value)
    }
    SettingsSlider {
        Layout.fillWidth:true; objectName:'dockEndPaddingControl'
        label:editor.settings.position === 'left' || editor.settings.position === 'right' ? 'Bottom inside padding' : 'Right inside padding'
        description:'Space inside the pill after the last item.'
        settingValue:editor.settings.paddingEnd ?? (editor.selectedItems.length ? 4 : 6)
        from:0; to:100; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('paddingEnd',value)
    }
    Text { Layout.fillWidth:true; text:editor.component === 'hyprbar' ? 'Hyprbar visibility' : 'Dock visibility'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockHideControl'; Layout.fillWidth:true
        model:["Always visible", "Auto-hide", "Hide when overlapped"]
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar visibility' : 'Dock visibility'
        currentIndex:["always", "auto-hide", "dodge"].indexOf(editor.settings.hideMode || 'always')
        onActivated:editor.edited('hideMode',["always", "auto-hide", "dodge"][currentIndex])
    }

    Text { Layout.fillWidth:true; text:editor.component === 'hyprbar' ? 'Hyprbar in fullscreen' : 'Dock in fullscreen'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockFullscreenControl'; Layout.fillWidth:true
        model:["Hide during fullscreen", "Show over fullscreen"]
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar in fullscreen' : 'Dock in fullscreen'
        currentIndex:["hide", "show"].indexOf(editor.settings.fullscreenPolicy || 'hide')
        onActivated:editor.edited('fullscreenPolicy',["hide", "show"][currentIndex])
    }

    Text { Layout.fillWidth:true; text:editor.component === 'hyprbar' ? 'Hyprbar alignment' : 'Dock alignment'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockAlignmentControl'; Layout.fillWidth:true
        model:["Start", "Center", "End"]
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar alignment' : 'Dock alignment'
        currentIndex:["start", "center", "end"].indexOf(editor.settings.alignment || 'center')
        onActivated:editor.edited('alignment',["start", "center", "end"][currentIndex])
    }

    Text { Layout.fillWidth:true; text:editor.component === 'hyprbar' ? 'Hyprbar background' : 'Dock background'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockBackgroundControl'; Layout.fillWidth:true
        model:["Follow Hyprpane", "On", "Off"]
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar background' : 'Dock background'
        currentIndex:["inherit", "on", "off"].indexOf(editor.settings.background || 'inherit')
        onActivated:editor.edited('background',["inherit", "on", "off"][currentIndex])
    }

    Text { Layout.fillWidth:true; text:editor.component === 'hyprbar' ? 'Hyprbar workspace scope' : 'Dock workspace scope'; color:Style.Theme.text }
    SettingsComboBox {
        objectName:'dockWorkspaceScopeControl'; Layout.fillWidth:true
        model:["All workspaces", "Selected workspaces"]
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar workspace scope' : 'Dock workspace scope'
        currentIndex:["all", "selected"].indexOf(editor.settings.workspaceScope || 'all')
        onActivated:editor.edited('workspaceScope',["all", "selected"][currentIndex])
    }

    SettingsSlider {
        Layout.fillWidth:true; label:editor.component === 'hyprbar' ? 'Hyprbar end margins' : 'Dock end margins'; settingValue:editor.settings.marginEnds
        from:0; to:200; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('marginEnds',value)
    }

    SettingsSlider {
        Layout.fillWidth:true; label:editor.component === 'hyprbar' ? 'Hyprbar window gap' : 'Dock window gap'; settingValue:editor.settings.windowGap
        from:0; to:100; suffix:' px'; allowReset:false
        onEdited:value => editor.edited('windowGap',value)
    }

    SettingsSwitch {
        Layout.fillWidth:true; text:'Show running indicators'; checked:editor.settings.indicators === true
        onToggled:editor.edited('indicators',checked)
    }

    SettingsSwitch {
        Layout.fillWidth:true; text:editor.component === 'hyprbar' ? 'Animate Hyprbar visibility' : 'Animate dock visibility'; checked:editor.settings.animations === true
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

    Text { Layout.fillWidth:true; text:editor.component === 'hyprbar' ? 'Hyprbar monitors (empty means all)' : 'Dock monitors (empty means all)'; color:Style.Theme.text }
    SettingsTextField {
        objectName:'dockMonitorsControl'; Layout.fillWidth:true
        text:(editor.settings.monitors || []).join(', ')
        placeholderText:'eDP-1, HDMI-A-1'
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar monitors' : 'Dock monitors'
        onEditingFinished:editor.edited('monitors', text.split(',').map(s => s.trim()).filter(Boolean))
    }
    Text { Layout.fillWidth:true; text:editor.component === 'hyprbar' ? 'Hyprbar selected workspaces (1–99)' : 'Dock selected workspaces (1–99)'; color:Style.Theme.text }
    SettingsTextField {
        objectName:'dockWorkspacesControl'; Layout.fillWidth:true
        text:(editor.settings.workspaceList || []).join(', ')
        placeholderText:'1, 2, 3'
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar selected workspaces' : 'Dock selected workspaces'
        onEditingFinished:editor.edited('workspaceList', text.split(',').map(s => s.trim()).filter(Boolean).map(Number))
    }

    SettingsSwitch {
        Layout.fillWidth:true; text:'Group windows by application'; checked:editor.settings.grouped !== false
        onToggled:editor.edited('grouped',checked)
    }
    Text { Layout.fillWidth:true; text:'Right-side items'; color:Style.Theme.text }
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
    Text { text:'Windows from workspaces'; color:Style.Theme.text }
    SettingsComboBox {
        Layout.fillWidth:true; model:['Current workspace','All workspaces']
        currentIndex:editor.settings.windowWorkspaceScope === 'current' ? 0 : 1
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar windows from workspaces' : 'Dock windows from workspaces'
        onActivated:editor.edited('windowWorkspaceScope',['current','all'][currentIndex])
    }
    Text { text:'Windows from monitors'; color:Style.Theme.text }
    SettingsComboBox {
        Layout.fillWidth:true; model:['Current monitor','All monitors']
        currentIndex:editor.settings.windowMonitorScope === 'all' ? 1 : 0
        Accessible.name:editor.component === 'hyprbar' ? 'Hyprbar windows from monitors' : 'Dock windows from monitors'
        onActivated:editor.edited('windowMonitorScope',['current','all'][currentIndex])
    }
}
