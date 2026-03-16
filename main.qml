import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.qfield 1.0
import Theme
import "qrc:/qml" as QFieldItems

Item {
    id: quickCaptureRoot
    parent: iface.mapCanvas()
    anchors.fill: parent
    z: 1000000

    // --- CONFIGURATION ---
    property string targetLayerName: "" // Set automatically to first editable vector layer
    property bool panelVisible: true
    property var buttonList: ["Pothole", "Signage", "Debris"]
    property string buttonListString: buttonList.join(", ")
    // Add this to your Settings section or use a hardcoded toggle for now
    property bool useCamera: false
    property var photoFieldCandidates: ["photo", "picture", "image", "media", "camera"]
    property var pendingCapture: null
    property var editableVectorLayers: []
    property var typeFieldNames: []
    property string typeFieldName: "type"

    ListModel {
        id: typeFieldModel
    }

    function logDebug(message) {
        if (iface && typeof iface.logMessage === "function") {
            iface.logMessage("quick_capture: " + message);
        } else {
            console.log("quick_capture: " + message);
        }
    }

    function getLayerObjectByName(name) {
        for (var i = 0; i < editableVectorLayers.length; ++i) {
            if (editableVectorLayers[i].name === name) return editableVectorLayers[i].layer;
        }
        return null;
    }

    function getLayerFieldNames(layer) {
        if (!layer || !layer.fields || !layer.fields.names) return [];
        return (typeof layer.fields.names === "function") ? layer.fields.names() : layer.fields.names;
    }

    function getFieldObject(layer, fieldName, fieldIndex) {
        if (!layer || !layer.fields) return null;

        var fieldObj = null;
        if (typeof layer.fields.fieldByName === "function") {
            try {
                fieldObj = layer.fields.fieldByName(fieldName);
            } catch (e) { }
        }

        // Some APIs return a field index from fieldByName.
        if (typeof fieldObj === "number" && typeof layer.fields.field === "function") {
            try {
                fieldObj = layer.fields.field(fieldObj);
            } catch (e2) { }
        }

        if (!fieldObj && typeof layer.fields.field === "function") {
            try {
                fieldObj = layer.fields.field(fieldIndex);
            } catch (e3) { }
        }

        if (!fieldObj && typeof layer.fields.at === "function") {
            try {
                fieldObj = layer.fields.at(fieldIndex);
            } catch (e4) { }
        }

        return fieldObj;
    }

    function isStringField(layer, fieldName, fieldIndex) {
        if (!fieldName) return false;

        var fieldObj = getFieldObject(layer, fieldName, fieldIndex);
        if (fieldObj) {
            var tn = "";
            if (typeof fieldObj.typeName === "function") {
                tn = fieldObj.typeName();
            } else if (typeof fieldObj.typeName === "string") {
                tn = fieldObj.typeName;
            }

            if (typeof tn === "string") {
                var tnl = tn.toLowerCase();
                if (tnl.indexOf("string") >= 0 || tnl.indexOf("text") >= 0 || tnl.indexOf("char") >= 0 || tnl.indexOf("varchar") >= 0 || tnl.indexOf("qstring") >= 0) {
                    return true;
                }
            }

            var t = null;
            if (typeof fieldObj.type === "function") {
                t = fieldObj.type();
            } else if (typeof fieldObj.type !== "undefined") {
                t = fieldObj.type;
            }

            if (t !== null) {
                if (t === 10 || t === "string" || t === "QString") {
                    return true;
                }
                if (typeof t === "string") {
                    var tl = t.toLowerCase();
                    if (tl.indexOf("string") >= 0 || tl.indexOf("text") >= 0 || tl.indexOf("char") >= 0 || tl.indexOf("varchar") >= 0) {
                        return true;
                    }
                }
            }
        }

        // Provider fallback: allow common categorical text names when metadata is not exposed.
        var lowerName = fieldName.toLowerCase();
        if (lowerName === "type" || lowerName.indexOf("_type") >= 0 || lowerName.indexOf("type_") >= 0) {
            return true;
        }

        return false;
    }

    function layerHasStringField(layer) {
        var names = getLayerFieldNames(layer);
        for (var i = 0; i < names.length; ++i) {
            var name = names[i];
            if (!name) continue;

            if (isStringField(layer, name, i)) {
                return true;
            }
        }

        return false;
    }

    function refreshTypeFieldList(layer) {
        typeFieldNames = [];
        typeFieldName = "type";
        typeFieldModel.clear();
        if (!layer || !layer.fields || !layer.fields.names) return;

        var names = getLayerFieldNames(layer);
        for (var i = 0; i < names.length; ++i) {
            var name = names[i];
            if (!name) continue;

            if (isStringField(layer, name, i)) {
                typeFieldNames.push(name);
            }
        }

        logDebug("type fields for layer " + (((typeof layer.name === "function") ? layer.name() : layer.name) || "<unknown>") + " => [" + typeFieldNames.join(", ") + "]");

        if (typeFieldNames.indexOf("type") >= 0) {
            typeFieldName = "type";
        } else if (typeFieldNames.length > 0) {
            typeFieldName = typeFieldNames[0];
        }

        for (var j = 0; j < typeFieldNames.length; ++j) {
            typeFieldModel.append({ name: typeFieldNames[j] });
        }

        // Keep the UI combo in sync if it exists.
        if (typeof typeFieldCombo !== "undefined" && typeFieldCombo !== null) {
            typeFieldCombo.model = typeFieldModel;
            var idx = typeFieldNames.indexOf(typeFieldName);
            typeFieldCombo.currentIndex = idx >= 0 ? idx : -1;
        }
    }

    function refreshEditableLayerList() {
        if (!iface || !iface.mapCanvas || !iface.mapCanvas().mapSettings) {
            editableVectorLayers = [];
            return;
        }

        var layers = iface.mapCanvas().mapSettings.layers;
        if (!layers) {
            editableVectorLayers = [];
            return;
        }

        var candidates = [];
        for (var i = 0; i < layers.length; ++i) {
            var layer = layers[i];
            if (!layer) continue;

            var name = (typeof layer.name === "function") ? layer.name() : layer.name;
            if (!name) continue;

            // Ensure layer is editable (if supported by API)
            var editable = true;
            if (typeof layer.isEditable === "function") {
                editable = layer.isEditable();
            }
            if (typeof layer.isReadOnly === "function") {
                editable = editable && !layer.isReadOnly();
            }

            var hasStrings = layerHasStringField(layer);

            logDebug("layer check: " + name + " editable=" + editable + " hasString=" + hasStrings);

            if (editable && hasStrings) {
                candidates.push({ name: name, layer: layer });
            }
        }

        editableVectorLayers = candidates;

        // Ensure the UI combo is always in sync with our list.
        if (typeof layerCombo !== "undefined" && layerCombo !== null) {
            layerCombo.model = editableVectorLayers;
        }

        if (!targetLayerName && editableVectorLayers.length > 0) {
            targetLayerName = editableVectorLayers[0].name;
        }

        // Refresh the type field list based on the selected layer.
        var layer = getLayerObjectByName(targetLayerName);
        refreshTypeFieldList(layer);

        // Ensure the UI combo reflects the selected layer.
        if (typeof layerCombo !== "undefined" && layerCombo !== null) {
            layerCombo.model = editableVectorLayers;
            var idx = getLayerIndexByName(targetLayerName);
            if (idx >= 0) layerCombo.currentIndex = idx;
            else layerCombo.currentIndex = -1;
        }

        var names = [];
        for (var n = 0; n < editableVectorLayers.length; ++n) {
            names.push(editableVectorLayers[n].name);
        }
        logDebug("editableVectorLayers count=" + editableVectorLayers.length + " names=[" + names.join(", ") + "]");
    }

    function getLayerIndexByName(name) {
        for (var i = 0; i < editableVectorLayers.length; ++i) {
            if (editableVectorLayers[i].name === name) return i;
        }
        return -1;
    }

    function parseButtonListString(str) {
        if (!str) return [];
        return str.split(",").map(function(item) {
            return item.trim();
        }).filter(function(item) {
            return item.length > 0;
        });
    }

    // Cache references to key QField UI objects (used to add features using the same workflow QField does).
    property var overlayFeatureFormDrawer: iface.findItemByObjectName('overlayFeatureFormDrawer')

    // Listen for the built-in feature form being saved, so we can mark the project dirty.
    Connections {
        id: featureFormConnections
        target: overlayFeatureFormDrawer ? overlayFeatureFormDrawer.featureForm : null

        onConfirmed: {
            markProjectDirty();
            iface.mainWindow().displayToast("✅ Saved. Sync should now be enabled.", 2500);
        }
    }

    Component.onCompleted: {
        refreshEditableLayerList();
        if (typeof iface.addItemToPluginsToolbar === "function") {
            iface.addItemToPluginsToolbar(settingsBtn)
        }
    }

    // Also refresh the layer list whenever the map changes.
    Connections {
        target: iface.mapCanvas() ? iface.mapCanvas().mapSettings : null
        onLayersChanged: {
            refreshEditableLayerList();
        }
    }

    // --- SETTINGS BUTTON (Toolbar) ---
    QfToolButton {
        id: settingsBtn

        iconSource: "icon.svg"
        iconColor: Theme.mainColor
        bgcolor: Theme.darkGray
        round: true

        onClicked: panelVisible = !panelVisible
        onPressAndHold: settingsPopup.open()
    }

    // --- BACKGROUND OVERLAY + CAPTURE BUTTONS ---
    Rectangle {
        id: captureOverlay
        parent: iface.mainWindow().contentItem
        anchors.fill: parent
        z: 1000000000000
        color: panelVisible ? "#00000080" : "transparent"
        visible: panelVisible

        Component.onCompleted: {
            if (iface && typeof iface.logMessage === "function") {
                iface.logMessage("quick_capture: captureOverlay created (panelVisible=" + panelVisible + ", size=" + width + "x" + height + ")");
                if (parent) {
                    iface.logMessage("quick_capture: captureOverlay parent size=" + parent.width + "x" + parent.height);
                }
            }
        }

        onWidthChanged: {
            if (iface && typeof iface.logMessage === "function") {
                iface.logMessage("quick_capture: captureOverlay width=" + width + " height=" + height);
            }
        }

        onHeightChanged: {
            if (iface && typeof iface.logMessage === "function") {
                iface.logMessage("quick_capture: captureOverlay height=" + height);
            }
        }

        onVisibleChanged: {
            if (iface && typeof iface.logMessage === "function") {
                iface.logMessage("quick_capture: captureOverlay visible=" + visible + ", panelVisible=" + panelVisible);
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width * 0.8
            spacing: 20
            visible: panelVisible

            Repeater {
                model: buttonList
                Button {
                    // Use fixed size relative to the overlay rather than the delegate parent (which may be 0)
                    width: captureOverlay.width * 0.75
                    height: captureOverlay.height * 0.12
                    text: modelData

                    onClicked: captureFeature(modelData)

                    background: Rectangle {
                        color: "#2ecc71"; radius: 18;
                        border.color: "white"; border.width: 3
                        opacity: parent.pressed ? 0.7 : 1.0
                    }
                    contentItem: Text {
                        text: parent.text; color: "white";
                        font.bold: true; font.pixelSize: 26;
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // --- POPUP TO CHANGE LAYER NAME ---
    Popup {
        id: settingsPopup
        z: 1000000000001
        parent: Overlay.overlay
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 340
        height: settingsColumn.implicitHeight * 1.1
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onOpened: {
            logDebug("settingsPopup opened");
            refreshEditableLayerList();
            Qt.callLater(function() {
                refreshEditableLayerList();
                logDebug("settingsPopup opened (post-open refresh complete)");
            });
        }

        Component.onCompleted: {
            logDebug("settingsPopup component completed");
        }

        onClosed: {
            buttonList = parseButtonListString(buttonListString)
        }

        background: Rectangle { radius: 10; color: "white"; border.color: "#999"; border.width: 2 }

        ColumnLayout {
            id: settingsColumn
            anchors.fill: parent; anchors.margins: 15
            Label { text: "Target Layer:"; font.bold: true }
            ComboBox {
                id: layerCombo
                Layout.fillWidth: true
                model: editableVectorLayers
                textRole: "name"
                valueRole: "name"
                enabled: editableVectorLayers.length > 0

                Component.onCompleted: {
                    var idx = getLayerIndexByName(targetLayerName);
                    if (idx >= 0) currentIndex = idx;
                    logDebug("layerCombo completed (model length=" + editableVectorLayers.length + ", count=" + count + ", currentIndex=" + currentIndex + ")");
                }

                onCountChanged: {
                    logDebug("layerCombo count changed to " + count + " (model length=" + editableVectorLayers.length + ")");
                    if (count > 0 && (currentIndex < 0 || currentIndex >= count)) {
                        var idx = getLayerIndexByName(targetLayerName);
                        currentIndex = idx >= 0 ? idx : 0;
                    }
                }

                onModelChanged: {
                    logDebug("layerCombo model changed (model length=" + editableVectorLayers.length + ", count=" + count + ")");
                }

                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < editableVectorLayers.length) {
                        targetLayerName = editableVectorLayers[currentIndex].name;
                        refreshTypeFieldList(getLayerObjectByName(targetLayerName));
                    }
                }
            }
            Label {
                text: editableVectorLayers.length === 0 ? "No editable vector layers found." : ""
                color: "red"
                visible: editableVectorLayers.length === 0
            }

            Label { text: "Type field:"; font.bold: true; padding: 8 }
            ComboBox {
                id: typeFieldCombo
                Layout.fillWidth: true
                model: typeFieldModel
                textRole: "name"
                enabled: typeFieldModel.count > 0

                Component.onCompleted: {
                    var idx = typeFieldNames.indexOf(typeFieldName);
                    if (idx >= 0) currentIndex = idx;
                }

                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < typeFieldModel.count) {
                        var row = typeFieldModel.get(currentIndex);
                        if (row && row.name) {
                            typeFieldName = row.name;
                        }
                    }
                }
            }

            Label { text: "Capture buttons (comma-separated):"; font.bold: true; padding: 8 }
            TextField {
                id: buttonListInput
                Layout.fillWidth: true
                text: buttonListString
                onTextChanged: buttonListString = text
            }

            RowLayout {
                spacing: 8
                Label { text: "Enable photo capture:" }
                Switch {
                    checked: useCamera
                    onCheckedChanged: useCamera = checked
                }
            }

            Button { 
                text: "Close"; Layout.alignment: Qt.AlignHCenter
                onClicked: settingsPopup.close() 
            }

            // Add extra spacing at the bottom so the Close button isn't flush with the dialog edge.
            Item { Layout.preferredHeight: 12 }
        }
    }

    // --- CAMERA CAPTURE (optional) ---
    Loader {
        id: cameraLoader
        active: false
        sourceComponent: Component {
            id: cameraComponent

            QFieldItems.QFieldCamera {
                id: qfieldCamera
                visible: false

                Component.onCompleted: open()

                onFinished: (path) => {
                    close()
                    cameraLoader.active = false
                    if (pendingCapture) {
                        completeCaptureWithPhoto(path)
                    }
                }

                onCanceled: {
                    close()
                    cameraLoader.active = false
                    pendingCapture = null
                }

                onClosed: {
                    cameraLoader.active = false
                    pendingCapture = null
                }
            }
        }
    }

    // --- CAPTURE LOGIC ---
    function findLayerByName(name) {
        if (!iface || !iface.mapCanvas || !iface.mapCanvas().mapSettings) {
            return null;
        }

        var layers = iface.mapCanvas().mapSettings.layers;
        if (!layers) {
            return null;
        }

        for (var i = 0; i < layers.length; ++i) {
            var layer = layers[i];
            if (!layer)
                continue;

            // QField exposes the layer name as either a property or a method.
            var layerName = (typeof layer.name === "function") ? layer.name() : layer.name;
            if (layerName === name)
                return layer;
        }

        return null;
    }

    function logLayerState(layer) {
        if (!layer || !iface || !iface.logMessage) return;
        try {
            var info = [];
            if (typeof layer.name === "function") info.push("name=" + layer.name());
            else if (typeof layer.name !== "undefined") info.push("name=" + layer.name);

            if (typeof layer.isValid === "function") info.push("isValid=" + layer.isValid());
            if (typeof layer.isWritable === "function") info.push("isWritable=" + layer.isWritable());
            if (typeof layer.isEditable === "function") info.push("isEditable=" + layer.isEditable());
            if (typeof layer.isReadOnly === "function") info.push("isReadOnly=" + layer.isReadOnly());
            if (typeof layer.wkbType === "function") info.push("wkbType=" + layer.wkbType());
            if (typeof layer.dataProvider === "function") {
                try {
                    var dp = layer.dataProvider();
                    if (dp) {
                        if (typeof dp.name === "function") info.push("provider=" + dp.name());
                        else if (typeof dp.name !== "undefined") info.push("provider=" + dp.name);
                    }
                } catch (e) {
                    info.push("provider=error");
                }
            }
            iface.logMessage("quick_capture: layer state: " + info.join(", "));
        } catch (e) {
            iface.logMessage("quick_capture: failed to inspect layer state: " + e);
        }
    }

    function findPhotoFieldIndex(layer) {
        if (!layer || !layer.fields || !layer.fields.names) return -1;
        var names = layer.fields.names;
        for (var i = 0; i < names.length; ++i) {
            if (!names[i]) continue;
            if (names[i].toLowerCase() === "photo") {
                return i;
            }
        }
        for (const candidate of photoFieldCandidates) {
            for (var j = 0; j < names.length; ++j) {
                if (!names[j]) continue;
                if (names[j].toLowerCase() === candidate.toLowerCase()) {
                    return j;
                }
            }
        }
        return -1;
    }

    function startCameraCapture(typeValue, layer, geometry, photoFieldIndex) {
        pendingCapture = {
            typeValue: typeValue,
            layer: layer,
            geometry: geometry,
            photoFieldIndex: photoFieldIndex
        };

        // Ensure camera images are saved inside the project folder.
        try {
            platformUtilities.createDir(qgisProject.homePath, 'DCIM');
        } catch (e) {
            // ignore if not available
        }

        cameraLoader.active = true;
    }

    function completeCaptureWithPhoto(path) {
        if (!pendingCapture) return;

        const data = pendingCapture;
        pendingCapture = null;

        if (!path) {
            iface.mainWindow().displayToast("❌ No photo taken. Feature not saved.");
            return;
        }

        // Move file into project folder (like QField does). Use a stable relative path.
        var today = new Date();
        var relativePath = 'DCIM/' + today.getFullYear()
                                   + (today.getMonth() + 1).toString().padStart(2, 0)
                                   + today.getDate().toString().padStart(2, 0)
                                   + today.getHours().toString().padStart(2, 0)
                                   + today.getMinutes().toString().padStart(2, 0)
                                   + today.getSeconds().toString().padStart(2, 0)
                                   + '.' + FileUtils.fileSuffix(path);
        try {
            platformUtilities.renameFile(path, qgisProject.homePath + '/' + relativePath);
        } catch (e) {
            // If we can't move, just use original path.
            relativePath = path;
        }

        createAndAddFeature(data.layer, data.geometry, data.typeValue, data.photoFieldIndex, relativePath);
    }

    function createAndAddFeature(layer, geometry, typeValue, photoFieldIndex, photoPath) {
        var feature = FeatureUtils.createFeature(layer, geometry);
        if (!feature) {
            iface.mainWindow().displayToast("❌ Failed to create feature.");
            return;
        }

        // If possible, set the 'type' attribute before adding it to the layer.
        try {
            if (typeof feature.setAttribute === "function") {
                feature.setAttribute(typeFieldName, typeValue);
            }
        } catch (e) {
            // ignore - not all builds expose setAttribute
        }

        // If this layer has a photo field, set it.
        try {
            if (typeof feature.setAttribute === "function" && photoFieldIndex >= 0 && photoPath) {
                feature.setAttribute(photoFieldIndex, photoPath);
            }
        } catch (e) {
            // ignore
        }

        // Ensure the layer is editable before adding.
        if (typeof layer.startEditing === "function") {
            try {
                layer.startEditing();
            } catch (e) {
                // Some QField builds start edit mode automatically or disallow it.
            }
        }

        // Try to add it directly.
        var addedDirectly = false;
        try {
            if (typeof LayerUtils.addFeature === "function") {
                addedDirectly = LayerUtils.addFeature(layer, feature);
                iface.logMessage("quick_capture: LayerUtils.addFeature returned " + addedDirectly);
            }
        } catch (e) {
            iface.logMessage("quick_capture: LayerUtils.addFeature threw: " + e);
        }

        if (addedDirectly) {
            markLayerDirty(layer);
            markProjectDirty();
            iface.mainWindow().displayToast("📍 Dropped " + typeValue + ". Sync should now be enabled.", 3000);
            return;
        }

        if (typeof LayerUtils.addFeature === "function") {
            iface.mainWindow().displayToast("⚠️ Cannot add directly; opening the feature form instead.", 2000);
        }

        // Prefer using QField's own feature form workflow (ensures the project is marked changed).
        var usedForm = false;
        if (overlayFeatureFormDrawer && overlayFeatureFormDrawer.featureModel) {
            try {
                var fm = overlayFeatureFormDrawer.featureModel;
                if (typeof fm.setCurrentLayer === "function") {
                    fm.setCurrentLayer(layer);
                }
                if (typeof fm.setFeature === "function") {
                    fm.setFeature(feature);
                }
                if (typeof fm.resetAttributes === "function") {
                    fm.resetAttributes(true);
                }

                // Open the form drawer in 'Add' mode and let the user save.
                if (typeof overlayFeatureFormDrawer.setProperty === "function") {
                    overlayFeatureFormDrawer.setProperty("state", "Add");
                } else {
                    overlayFeatureFormDrawer.state = "Add";
                }

                if (typeof overlayFeatureFormDrawer.open === "function") {
                    overlayFeatureFormDrawer.open();
                }

                usedForm = true;
            } catch (e) {
                // fallback to direct API if any of this fails
            }
        }

        if (!usedForm) {
            iface.mainWindow().displayToast("❌ Failed to add feature. Try using the Add Feature button.");
            logLayerState(layer);
            return;
        }

        // If we used the form, let the user save in the form (it will mark project as dirty).
        iface.mainWindow().displayToast("📍 Dropped " + typeValue + ". Tap Save in the form to persist.", 3000);
    }

    function captureFeature(typeValue) {
        var layer = findLayerByName(targetLayerName);
        if (!layer) {
            iface.mainWindow().displayToast("❌ Layer not found: " + targetLayerName);
            return;
        }

        // If the layer is locked against additions, stop early.
        if (LayerUtils.isFeatureAdditionLocked(layer)) {
            iface.mainWindow().displayToast("❌ Layer is locked (no new features allowed).\nUse the Add Feature button in the UI.");
            return;
        }

        // Determine where to place the feature: use GPS if available, otherwise use map center.
        var position = null;
        if (iface.positioning && iface.positioning().valid) {
            position = iface.positioning().projectedPosition;
        }
        if (!position) {
            var settings = iface.mapCanvas().mapSettings;
            position = settings ? settings.center : null;
        }

        if (!position) {
            iface.mainWindow().displayToast("❌ Unable to determine a point location.");
            return;
        }

        // Create a point geometry at the chosen location.
        var geometry = GeometryUtils.createGeometryFromWkt("POINT(" + position.x + " " + position.y + ")");
        if (!geometry) {
            iface.mainWindow().displayToast("❌ Failed to create geometry.");
            return;
        }

        var photoFieldIndex = findPhotoFieldIndex(layer);
        if (useCamera && photoFieldIndex >= 0) {
            startCameraCapture(typeValue, layer, geometry, photoFieldIndex);
            return;
        }

        createAndAddFeature(layer, geometry, typeValue, photoFieldIndex, null);
    }

    function markLayerDirty(layer) {
        if (!layer) return;

        try {
            // Try to mark the layer as modified so QField's sync logic sees it.
            if ("dirty" in layer) {
                layer.dirty = true;
            }
            if ("modified" in layer) {
                layer.modified = true;
            }
            if ("changed" in layer) {
                layer.changed = true;
            }

            if (typeof layer.setDirty === "function") {
                layer.setDirty(true);
            }
            if (typeof layer.setModified === "function") {
                layer.setModified(true);
            }
            if (typeof layer.setChanged === "function") {
                layer.setChanged(true);
            }

            // QGIS layers have a commit/rollback API; try to nudge QField's edit buffer.
            if (typeof layer.commitChanges === "function") {
                try {
                    layer.commitChanges();
                } catch (e) {
                    // commitChanges may not be allowed here; ignoring.
                }
            }
            if (typeof layer.triggerRepaint === "function") {
                layer.triggerRepaint();
            }
        } catch (e) {
            // ignore if layer doesn't support these
        }
    }

    function markProjectDirty() {
        // Try to mark the project as dirty, so sync/Save detects a change.
        try {
            var project = iface.mapCanvas().mapSettings && iface.mapCanvas().mapSettings.project;
            if (project) {
                // Some QML bindings expose setters for these properties.
                if ("dirty" in project) {
                    project.dirty = true;
                }
                if ("modified" in project) {
                    project.modified = true;
                }
                if ("changed" in project) {
                    project.changed = true;
                }

                if (typeof project.setDirty === "function") {
                    project.setDirty(true);
                }
                if (typeof project.setModified === "function") {
                    project.setModified(true);
                }
                if (typeof project.setChanged === "function") {
                    project.setChanged(true);
                }

                // Some builds expose writeEntry/writeBoolEntry to force a project write.
                if (typeof project.writeEntry === "function") {
                    project.writeEntry("quick_capture", "lastEdit", Date.now());
                }
                if (typeof project.writeBoolEntry === "function") {
                    project.writeBoolEntry("quick_capture", "hasEdits", true);
                }
            }
        } catch (e) {
            // ignore if project isn't accessible or methods not present
        }

        // Try to trigger QField's internal save/dirty notifications.
        try {
            if (typeof iface.executeAction === "function") {
                const actions = [
                    "save",
                    "actionSave",
                    "actionSaveProject",
                    "saveProject",
                    "actionSaveAs",
                    "actionCommit",
                    "commit",
                    "saveAll"
                ];
                for (const a of actions) {
                    try {
                        iface.executeAction(a);
                    } catch (e) {
                        // ignore unknown actions
                    }
                }
            }
        } catch (e) {
            // ignore if action not supported
        }

        try {
            if (typeof iface.vibrate === "function") {
                iface.vibrate(100);
            }
        } catch (e) {
            // vibrate may not be exposed in this build
        }
    }
}


