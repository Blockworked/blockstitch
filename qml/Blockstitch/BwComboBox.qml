import QtQuick
import QtQuick.Controls

ComboBox {
    id:control
    implicitHeight:34;leftPadding:10;rightPadding:32;font.pixelSize:13
    contentItem:Text { text:control.displayText;color:control.enabled?Theme.text:Theme.textDim;font:control.font;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight }
    indicator:LucideIcon { name:control.popup.visible?"chevron-up":"chevron-down";color:Theme.textDim;width:15;height:15;x:control.width-width-9;y:(control.height-height)/2 }
    background:Rectangle { radius:5;color:control.down?"#292a2d":Theme.panelRaised;border.color:control.activeFocus?Theme.accent:Theme.border }
    popup:Popup {
        y:control.height+3;width:Math.max(control.width,implicitWidth);height:Math.min(264,control.count*32+8);padding:4
        contentItem:ListView { clip:true;model:control.popup.visible?control.delegateModel:null;currentIndex:control.highlightedIndex;boundsBehavior:Flickable.StopAtBounds;ScrollBar.vertical:ScrollBar{policy:control.count*32>256?ScrollBar.AsNeeded:ScrollBar.AlwaysOff} }
        background:Rectangle { radius:6;color:Theme.menu;border.color:Theme.border }
    }
    delegate:ItemDelegate {
        width:ListView.view.width;implicitHeight:32;highlighted:control.highlightedIndex===index
        contentItem:Text { text:control.textRole?model[control.textRole]:modelData;color:Theme.text;font:control.font;verticalAlignment:Text.AlignVCenter }
        background:Rectangle { radius:4;color:parent.highlighted?"#424348":"transparent" }
    }
}
