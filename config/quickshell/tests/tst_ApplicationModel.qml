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
    function test_launchAndActionArguments() {
        compare(Apps.launchCommand({id:'kitty'}),['uwsm','app','-t','service','--','kitty.desktop']);
        compare(Apps.launchCommand({id:'My App.desktop'}),[]);
        compare(Apps.launchCommand({id:'app+name.desktop'}),[]);
        verify(Apps.windowCommand('move','0xabcd',3,true).indexOf('follow = false')>=0);
        compare(Apps.windowCommand('move','0xabcd',3,false),'movetoworkspacesilent 3,address:0xabcd');
        compare(Apps.windowCommand('close','ab',0,true),'hl.dsp.window.close({ window = "address:0xab" })');
        compare(Apps.windowCommand('focus','0xab',0,true),'hl.dsp.focus({ window = "address:0xab" })');
        for (let lua of [false, true]) {
            for (let action of ['focus', 'close', 'move']) {
                compare(Apps.windowCommand(action,'555ef619df90',3,lua),
                        Apps.windowCommand(action,'0x555ef619df90',3,lua));
            }
        }
        for(let address of ['', '0xab" }); evil()', 'not-address']) compare(Apps.windowCommand('focus',address,1,true),'');
        for(let workspace of [0,100,1.5,'2']) compare(Apps.windowCommand('move','ab',workspace,true),'');
        compare(Apps.windowCommand('minimize','ab',1,true),'');
    }
}
