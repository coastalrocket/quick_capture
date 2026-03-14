import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.qfield 1.0

Item {
    id: quickCaptureRoot
    parent: iface.mapCanvas()
    anchors.fill: parent
    z: 9999

    // --- CONFIGURATION ---
    property string targetLayerName: "Quick_Survey" // Change this to match your layer name exactly
    property bool panelVisible: true
    property var buttonList: ["Pothole", "Signage", "Debris"]
    // Add this to your Settings section or use a hardcoded toggle for now
    property bool useCamera: true

    // --- SETTINGS BUTTON (Top Right) ---
    Button {
        id: settingsBtn
        width: 60; height: 60
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        anchors.topMargin: 40 

        onClicked: panelVisible = !panelVisible
        onPressAndHold: settingsPopup.open()

        background: Rectangle { 
            color: "white"; radius: 30; 
            border.color: "#333"; border.width: 2
            opacity: 0.8
        }
        contentItem: Text { 
            text: "⚙️"; font.pixelSize: 32; 
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter 
        }
    }

    // --- CAPTURE BUTTONS (Left Side) ---
    Column {
        visible: panelVisible
        spacing: 20
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 30

        Repeater {
            model: buttonList
            Button {
                width: 180; height: 90
                text: modelData
                
                onClicked: captureFeature(modelData)

                background: Rectangle { 
                    color: "#2ecc71"; radius: 15; 
                    border.color: "white"; border.width: 3 
                    // Visual feedback when pressed
                    opacity: parent.pressed ? 0.7 : 1.0
                }
                contentItem: Text { 
                    text: parent.text; color: "white"; 
                    font.bold: true; font.pixelSize: 22;
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter 
                }
            }
        }
    }

    // --- POPUP TO CHANGE LAYER NAME ---
    Popup {
        id: settingsPopup
        parent: Overlay.overlay
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 300; height: 150
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle { radius: 10; color: "white"; border.color: "#999"; border.width: 2 }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 15
            Label { text: "Target Layer Name:"; font.bold: true }
            TextField {
                id: layerInput
                Layout.fillWidth: true
                text: targetLayerName
                onTextChanged: targetLayerName = text
            }
            Button { 
                text: "Close"; Layout.alignment: Qt.AlignHCenter
                onClicked: settingsPopup.close() 
            }
        }
    }

    // --- CAPTURE LOGIC ---
    function captureFeature(typeValue) {
        // Since we can't 'see' the project, we use the Global Action Trigger
        // This simulates the user clicking 'Add Feature' at the crosshair
        
        try {
            // 1. Tell QField to start a new feature at the current center
            // This bypasses the 'Project is Hidden' lockout
            iface.digitizeFeature(); 

            // 2. We use a 'Delayed Toast' to tell you what to do next
            // In a sandboxed AppImage, this is the most reliable workflow
            iface.vibrate(100);
            iface.mainWindow().displayToast("📍 Dropped " + typeValue + ". Please Save.");

            // 3. Optional: If your build supports 'setItemAttribute', we can try to 
            // auto-fill the form that just popped up.
            try {
                iface.setItemAttribute("type", typeValue);
            } catch(e) {
                // If auto-fill is also locked, the user just taps the 'type' in the form
            }

        } catch(err) {
            // If even 'digitizeFeature' is blocked, the AppImage is 100% read-only for QML
            iface.mainWindow().displayToast("❌ Hardware Lock: Use manual 'Add Feature' button.");
        }
    }
}
