import QtQuick
import QtQuick.Controls.Basic
import QtTest
import ".."

Item {
    id: scene
    width: 900; height: 1400
    property int destination: 0
    property int searches: 0
    SettingsHome {
        id: home
        width: scene.width
        firstRunPending: true
        navigation: [
            {group:'Desktop',pages:[{section:-8,title:'Appearance',symbol:'A'},{section:-21,title:'Printing & scanning',symbol:'P'}]},
            {group:'Devices',pages:[{section:-7,title:'Displays',symbol:'D'},{section:-9,title:'Mouse & keyboard',symbol:'K'}]},
            {group:'System',pages:[{section:-14,title:'Updates & recovery',symbol:'U'},{section:-23,title:'Backup & restore',symbol:'B'}]}]
        onNavigate: section => scene.destination=section
        onSearchRequested: scene.searches++
    }
    TestCase {
        name:'SettingsHome'; when:windowShown
        function test_linksSearchAndGuide() {
            mouseClick(findChild(home,'settingsHomePage-8')); compare(scene.destination,-8);
            mouseClick(findChild(home,'settingsHomePage-23')); compare(scene.destination,-23);
            mouseClick(findChild(home,'settingsHomeSearch')); compare(scene.searches,1);
            mouseClick(findChild(home,'settingsHomeGuide')); compare(scene.destination,-18);
        }
        function test_responsiveCategories() {
            for(let width of [380,660,840]) {
                home.width=width; wait(30);
                for(let section of [-8,-21,-7,-9,-14,-23]) {
                    let button=findChild(home,'settingsHomePage'+section);
                    verify(button.visible);
                    let point=button.mapToItem(home,0,0);
                    verify(point.x>=0 && point.x+button.width<=home.width+1);
                    verify(button.width>=140);
                }
            }
        }
    }
}
