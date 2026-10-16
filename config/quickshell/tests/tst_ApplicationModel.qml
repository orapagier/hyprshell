import QtQuick
import QtTest
import "../ApplicationModel.js" as Apps

TestCase {
    name: 'ApplicationModel'
    function entries() {
        return [{id:'org.gnome.Nautilus',name:'Files',icon:'files',startupClass:'org.gnome.Nautilus'},
            {id:'kitty',name:'Kitty',icon:'kitty',startupClass:'kitty'},
            {id:'org.example.Editor',name:'Editor',startupClass:'EditorClass'}];
    }
    function window(address, cls, title, ws, active) {
        return {address:address,title:title,activated:!!active,workspace:{id:ws,name:String(ws)},
            monitor:{name:'eDP-1'},lastIpcObject:{class:cls,initialClass:cls}};
    }
    function test_matchingAndAmbiguity() {
        let apps=entries();
        compare(Apps.match(window('a','org.gnome.Nautilus','Files',1),apps,{}),'org.gnome.Nautilus.desktop');
        compare(Apps.match(window('b','KITTY','Terminal',1),apps,{}),'kitty.desktop');
        compare(Apps.match(window('c','EditorClass','Document',2),apps,{}),'org.example.Editor.desktop');
        compare(Apps.match(window('d','Editor','Document',2),apps,{}),'org.example.Editor.desktop');
        apps.push({id:'other.Editor',name:'Another editor'});
        compare(Apps.match(window('e','Editor','Editor',2),apps,{}),'');
        compare(Apps.match(window('e','Unknown','Kitty',2),apps,{}),'');
        compare(Apps.match(window('e','Unknown','Kitty',2),apps,{Unknown:'missing.desktop'}),'missing.desktop');
    }
    function test_groupLifecycleAndPins() {
        let windows=[window('a','kitty','one',1,true),window('b','kitty','two',2),window('c','Unknown','unknown',3)];
        let pins=['missing.desktop','kitty.desktop'];
        let groups=Apps.groups(entries(),windows,pins,{});
        compare(groups.length,3); compare(groups[0].installed,false); compare(groups[0].pinned,true);
        compare(groups[1].windows.length,2); compare(groups[1].active,true);
        compare(groups[1].windows[1].workspace,2); compare(groups[1].windows[0].output,'eDP-1');
        windows[0].activated=false; windows[1].activated=true; windows[1].title='changed';
        windows[1].workspace={id:4,name:'four'}; windows[1].monitor={name:'HDMI-A-1'};
        groups=Apps.groups(entries(),windows,pins,{});
        compare(groups[1].windows[1].title,'changed'); compare(groups[1].windows[1].workspace,4);
        compare(groups[1].windows[1].output,'HDMI-A-1'); compare(groups[1].windows[1].active,true);
        windows.splice(0,2);
        groups=Apps.groups(entries(),windows,pins,{Unknown:'kitty.desktop'});
        compare(groups.length,2); compare(groups[1].windows.length,1);
        compare(Apps.groups(entries(),[],pins,{}).length,2);
        let unknowns=Apps.groups([], [window('a','','one',1),window('b','','two',1)],[],{});
        compare(unknowns.length,2);
    }
    function test_launchAndActionArguments() {
        compare(Apps.launchCommand({id:'kitty'}),['uwsm','app','-t','service','--','kitty.desktop']);
        compare(Apps.launchCommand({id:'My App.desktop'}),[]);
        compare(Apps.launchCommand({id:'app+name.desktop'}),[]);
        verify(Apps.windowCommand('move','0xabcd',3,true).indexOf('follow = false')>=0);
        compare(Apps.windowCommand('move','0xabcd',3,false),'movetoworkspacesilent 3,address:0xabcd');
        compare(Apps.windowCommand('close','ab',0,true),'hl.dsp.window.close({ window = "address:ab" })');
        compare(Apps.windowCommand('focus','0xab',0,true),'hl.dsp.focus({ window = "address:0xab" })');
        for(let address of ['', '0xab" }); evil()', 'not-address']) compare(Apps.windowCommand('focus',address,1,true),'');
        for(let workspace of [0,100,1.5,'2']) compare(Apps.windowCommand('move','ab',workspace,true),'');
        compare(Apps.windowCommand('minimize','ab',1,true),'');
    }
    function test_cachedRowsAvoidReadingNativeWindows() {
        let apps = entries();
        let nativeWindow = window('a', 'kitty', 'Terminal', 1, true);
        let rows = [Apps.windowData(nativeWindow, apps, {})];
        Object.defineProperty(nativeWindow, 'title', {get: function() { throw new Error('Native window read during grouping'); }});
        let groups = Apps.groups(apps, [nativeWindow], ['kitty.desktop'], {}, rows);
        compare(groups.length, 1);
        verify(groups[0].entry === apps[1]);
        compare(groups[0].windows[0].title, 'Terminal');
        verify(groups[0].active);
        compare(Apps.groups(apps, [nativeWindow], ['kitty.desktop'], {}, [])[0].windows.length, 0);
    }
}
