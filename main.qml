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
    property var mainWindow: iface && iface.mainWindow ? iface.mainWindow() : null

    // --- CONFIGURATION ---
    property string targetLayerName: "" // Set automatically to first editable vector layer
    property bool panelVisible: false
    property var buttonList: ["Pothole", "Signage", "Debris"]
    property var buttonStyleMap: ({})
    property string buttonListString: buttonList.join(", ")
    property bool compactCaptureButtons: buttonList.length > 6
    property real captureButtonHeightFactor: compactCaptureButtons ? 0.08 : 0.12
    property real captureButtonVPadding: compactCaptureButtons ? 1 : 6
    property real captureButtonHPadding: 14
    property int bottomGroupCount: {
        var count = 0;
        for (var i = 0; i < buttonList.length; ++i) {
            if (i < 3 || (i >= 6 && (i - 6) % 2 === 0)) count++;
        }
        return count;
    }
    property int topGroupCount: {
        var count = 0;
        for (var i = 0; i < buttonList.length; ++i) {
            if ((i >= 3 && i < 6) || (i >= 7 && (i - 7) % 2 === 0)) count++;
        }
        return count;
    }
    property int maxGroupCount: Math.max(bottomGroupCount, topGroupCount)
    property int bottomSlotCount: buttonList.length <= 6 ? Math.max(3, bottomGroupCount) : maxGroupCount
    property int topSlotCount: buttonList.length <= 6 ? Math.max(3, topGroupCount) : maxGroupCount

    function getBottomButtonIndex(repeaterIndex) {
        var bottomIdx = 0;
        for (var i = 0; i < buttonList.length; ++i) {
            if (i < 3 || (i >= 6 && (i - 6) % 2 === 0)) {
                if (bottomIdx === repeaterIndex) return i;
                bottomIdx++;
            }
        }
        return -1;
    }

    function getTopButtonIndex(repeaterIndex) {
        var topIdx = 0;
        for (var i = 0; i < buttonList.length; ++i) {
            if ((i >= 3 && i < 6) || (i >= 7 && (i - 7) % 2 === 0)) {
                if (topIdx === repeaterIndex) return i;
                topIdx++;
            }
        }
        return -1;
    }

    function normalizeColorValue(value) {
        if (value === null || typeof value === "undefined") return "";

        var colorString = String(value).trim();
        return colorString.length > 0 ? colorString : "";
    }

    function resolveIconSource(pathValue) {
        var rawPath = normalizeColorValue(pathValue);
        if (rawPath.length === 0) return "";

        if (rawPath.indexOf("qrc:/") === 0 || rawPath.indexOf("file:") === 0 || rawPath.indexOf("http://") === 0 || rawPath.indexOf("https://") === 0) {
            return rawPath;
        }

        function toFileUrl(path) {
            var normalized = normalizeColorValue(path).replace(/\\/g, "/");
            if (normalized.length === 0) return "";
            // Keep slashes intact while encoding spaces and special characters.
            return "file://" + encodeURI(normalized);
        }

        if (rawPath.indexOf("/") === 0) {
            return toFileUrl(rawPath);
        }

        var projectPath = "";
        var projectDir = "";
        try {
            var project = iface && iface.mapCanvas && iface.mapCanvas().mapSettings ? iface.mapCanvas().mapSettings.project : null;
            if (project) {
                if (typeof project.absoluteFilePath === "function") {
                    projectPath = normalizeColorValue(project.absoluteFilePath());
                } else if (typeof project.absoluteFilePath === "string") {
                    projectPath = normalizeColorValue(project.absoluteFilePath);
                } else if (typeof project.fileName === "function") {
                    projectPath = normalizeColorValue(project.fileName());
                } else if (typeof project.fileName === "string") {
                    projectPath = normalizeColorValue(project.fileName);
                }

                if (typeof project.homePath === "function") {
                    projectDir = normalizeColorValue(project.homePath());
                } else if (typeof project.homePath === "string") {
                    projectDir = normalizeColorValue(project.homePath);
                } else if (typeof project.absolutePath === "function") {
                    projectDir = normalizeColorValue(project.absolutePath());
                } else if (typeof project.absolutePath === "string") {
                    projectDir = normalizeColorValue(project.absolutePath);
                }
            }
        } catch (e) {
            projectPath = "";
            projectDir = "";
        }

        if (projectDir.length > 0) {
            var normalizedProjectDir = projectDir.replace(/\\/g, "/");
            if (normalizedProjectDir.slice(-1) !== "/") normalizedProjectDir += "/";
            return toFileUrl(normalizedProjectDir + rawPath);
        }

        if (projectPath.length > 0) {
            var normalizedProjectPath = projectPath.replace(/\\/g, "/");
            var lastSlash = normalizedProjectPath.lastIndexOf("/");
            if (lastSlash >= 0) {
                return toFileUrl(normalizedProjectPath.substring(0, lastSlash + 1) + rawPath);
            }
        }

        // Fallback: keep relative value as-is in case runtime resolves against project folder.
        return rawPath;
    }

    function getButtonStyle(typeValue) {
        var defaultStyle = {
            backgroundColor: "#2ecc71",
            textColor: "white",
            iconSource: ""
        };

        if (typeValue === null || typeof typeValue === "undefined") {
            return defaultStyle;
        }

        var styleEntry = buttonStyleMap[String(typeValue)];
        if (!styleEntry) {
            return defaultStyle;
        }

        return {
            backgroundColor: styleEntry.backgroundColor || defaultStyle.backgroundColor,
            textColor: styleEntry.textColor || defaultStyle.textColor,
            iconSource: styleEntry.iconSource || defaultStyle.iconSource
        };
    }

    function getButtonBackgroundColor(typeValue) {
        return getButtonStyle(typeValue).backgroundColor;
    }

    function getButtonTextColor(typeValue) {
        return getButtonStyle(typeValue).textColor;
    }

    function getButtonIconSource(typeValue) {
        return getButtonStyle(typeValue).iconSource;
    }

    // Add this to your Settings section or use a hardcoded toggle for now
    property bool useCamera: false
    property var photoFieldCandidates: ["photo", "picture", "image", "media", "camera"]
    property var pendingCapture: null
    property var activeCamera: null
    property var nativeCameraResource: null
    property bool nativeCameraInProgress: false
    property var editableVectorLayers: []
    property var typeFieldNames: []
    property string typeFieldName: "type"
    property bool canLoadTypesFromLayer: false
    property var pendingTypesLayer: null
    property int typesLoadAttempts: 0

    ListModel {
        id: typeFieldModel
    }

    FeatureListModel {
        id: quickCaptureTypesModel
        keyField: "type"
        displayValueField: "type"
        orderByValue: true
        addNull: false
    }

    Timer {
        id: typesLoadPollTimer
        interval: 250
        repeat: false
        onTriggered: finalizeTypesLoadFromModel()
    }

    function logDebug(message) {
        if (iface && typeof iface.logMessage === "function") {
            iface.logMessage("quick_capture: " + message);
        } else {
            console.log("quick_capture: " + message);
        }
    }

    function debugToast(message, durationMs) {
        logDebug(message);
        if (iface && iface.mainWindow && iface.mainWindow() && typeof iface.mainWindow().displayToast === "function") {
            iface.mainWindow().displayToast("📷 " + message, durationMs || 1500);
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

    function getFeatureAttributeValue(feature, fieldName, fieldIndex) {
        if (!feature) return null;

        try {
            if (typeof feature.attribute === "function") {
                var valueByName = feature.attribute(fieldName);
                if (valueByName !== null && typeof valueByName !== "undefined") {
                    return valueByName;
                }

                var valueByIndex = feature.attribute(fieldIndex);
                if (valueByIndex !== null && typeof valueByIndex !== "undefined") {
                    return valueByIndex;
                }
            }
        } catch (e) { }

        if (feature.attributes && typeof feature.attributes.length !== "undefined" && feature.attributes.length > fieldIndex) {
            return feature.attributes[fieldIndex];
        }

        return null;
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

    function checkIfTypesCanBeLoaded() {
        // Find quick_capture_types layer (may be non-spatial)
        var qcTypesLayer = findLayerByNameInProject("quick_capture_types");

        if (!qcTypesLayer) {
            canLoadTypesFromLayer = false;
            return;
        }

        // Check if it has a 'type' field
        var fieldNames = getLayerFieldNames(qcTypesLayer);
        canLoadTypesFromLayer = fieldNames.indexOf("type") >= 0;
    }

    function applyLoadedTypes(distinctTypes, stylesByType) {
        if (!distinctTypes || distinctTypes.length === 0) {
            iface.mainWindow().displayToast("⚠️ No types found in 'quick_capture_types' layer.");
            return;
        }

        buttonListString = distinctTypes.join(", ");
        buttonList = distinctTypes;
        buttonStyleMap = stylesByType || ({})

        iface.mainWindow().displayToast("✅ Loaded " + distinctTypes.length + " types.", 1500);
    }

    function finalizeTypesLoadFromModel() {
        var rowCount = 0;
        try {
            rowCount = quickCaptureTypesModel.rowCount();
        } catch (e) {
            quickCaptureTypesModel.currentLayer = null;
            pendingTypesLayer = null;
            return;
        }

        if (rowCount === 0 && typesLoadAttempts < 8) {
            typesLoadAttempts += 1;
            typesLoadPollTimer.start();
            return;
        }

        var distinctTypes = [];
        var stylesByType = {};
        var typeMap = {};
        var displayRole = (typeof FeatureListModel !== "undefined" && typeof FeatureListModel.DisplayStringRole !== "undefined")
                ? FeatureListModel.DisplayStringRole
                : Qt.DisplayRole;
        var featureIdRole = (typeof FeatureListModel !== "undefined" && typeof FeatureListModel.FeatureIdRole !== "undefined")
                ? FeatureListModel.FeatureIdRole
                : -1;
        var textHexFieldIndex = pendingTypesLayer ? getLayerFieldNames(pendingTypesLayer).indexOf("text_hex") : -1;
        var backgroundHexFieldIndex = pendingTypesLayer ? getLayerFieldNames(pendingTypesLayer).indexOf("background_hex") : -1;
        var iconFieldIndex = pendingTypesLayer ? getLayerFieldNames(pendingTypesLayer).indexOf("icon") : -1;
        for (var row = 0; row < rowCount; ++row) {
            var displayValue = quickCaptureTypesModel.dataFromRowIndex(row, displayRole);

            if (displayValue !== null && typeof displayValue !== "undefined") {
                var typeString = String(displayValue).trim();
                if (typeString.length > 0 && !typeMap[typeString]) {
                    typeMap[typeString] = true;
                    distinctTypes.push(typeString);

                    if (pendingTypesLayer && featureIdRole >= 0) {
                        var featureId = quickCaptureTypesModel.dataFromRowIndex(row, featureIdRole);
                        var feature = quickCaptureTypesModel.getFeatureById(featureId);
                        var textHex = normalizeColorValue(getFeatureAttributeValue(feature, "text_hex", textHexFieldIndex));
                        var backgroundHex = normalizeColorValue(getFeatureAttributeValue(feature, "background_hex", backgroundHexFieldIndex));
                        var iconSource = resolveIconSource(getFeatureAttributeValue(feature, "icon", iconFieldIndex));

                        if (iconSource.length > 0) {
                            logDebug("icon for type '" + typeString + "' => " + iconSource);
                        }

                        if (textHex.length > 0 || backgroundHex.length > 0 || iconSource.length > 0) {
                            stylesByType[typeString] = {
                                textColor: textHex,
                                backgroundColor: backgroundHex,
                                iconSource: iconSource
                            };
                        }
                    }
                }
            }
        }

        quickCaptureTypesModel.currentLayer = null;
        pendingTypesLayer = null;
        typesLoadAttempts = 0;
        applyLoadedTypes(distinctTypes, stylesByType);
    }

    function loadTypesFromLayer() {
        // Find quick_capture_types layer (may be non-spatial)
        var qcTypesLayer = findLayerByNameInProject("quick_capture_types");

        if (!qcTypesLayer) {
            iface.mainWindow().displayToast("❌ Layer 'quick_capture_types' not found in project.");
            return;
        }

        // Get field names and find the 'type' field
        var fieldNames = getLayerFieldNames(qcTypesLayer);
        var typeFieldIndex = fieldNames.indexOf("type");
        if (typeFieldIndex < 0) {
            iface.mainWindow().displayToast("❌ Field 'type' not found in 'quick_capture_types' layer.");
            return;
        }

        pendingTypesLayer = qcTypesLayer;
        typesLoadAttempts = 0;
        quickCaptureTypesModel.currentLayer = null;
        quickCaptureTypesModel.displayValueField = "type";
        quickCaptureTypesModel.keyField = "type";
        quickCaptureTypesModel.currentLayer = qcTypesLayer;
        typesLoadPollTimer.start();
    }

    function refreshEditableLayerList() {
        if (!iface || !iface.mapCanvas || !iface.mapCanvas().mapSettings) {
            editableVectorLayers = [];
            canLoadTypesFromLayer = false;
            return;
        }

        var layers = iface.mapCanvas().mapSettings.layers;
        if (!layers) {
            editableVectorLayers = [];
            canLoadTypesFromLayer = false;
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
        checkIfTypesCanBeLoaded();

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

    function findLayerByNameInProject(layerName) {
        // Search map canvas layers first (spatial layers)
        if (iface && iface.mapCanvas && iface.mapCanvas().mapSettings) {
            var mapLayers = iface.mapCanvas().mapSettings.layers;
            if (mapLayers) {
                for (var i = 0; i < mapLayers.length; ++i) {
                    var layer = mapLayers[i];
                    if (!layer) continue;
                    var name = (typeof layer.name === "function") ? layer.name() : layer.name;
                    if (name === layerName) {
                        return layer;
                    }
                }
            }
        }

        // Search project layers (includes non-spatial layers)
        try {
            var project = iface && iface.mapCanvas && iface.mapCanvas().mapSettings ? iface.mapCanvas().mapSettings.project : null;
            if (project && typeof project.mapLayersByName === "function") {
                var foundLayers = project.mapLayersByName(layerName);
                if (foundLayers && foundLayers.length > 0) {
                    return foundLayers[0];
                }
            }
        } catch (e) {
            logDebug("Error searching project layers: " + e);
        }

        return null;
    }

    function isMapCanvasForeground() {
        if (!iface || !iface.mapCanvas || !iface.mapCanvas()) {
            return false;
        }

        var canvas = iface.mapCanvas();
        if (typeof canvas.visible !== "undefined" && !canvas.visible) {
            return false;
        }
        if (typeof canvas.enabled !== "undefined" && !canvas.enabled) {
            return false;
        }
        if (typeof canvas.opacity === "number" && canvas.opacity <= 0) {
            return false;
        }

        return true;
    }

    function closePanelIfMapHidden() {
        if (panelVisible && !isMapCanvasForeground()) {
            panelVisible = false;
            logDebug("map hidden -> capture panel closed");
        }
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
        mainWindow = iface && iface.mainWindow ? iface.mainWindow() : null;
        refreshEditableLayerList();
        closePanelIfMapHidden();
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

    Connections {
        target: iface.mapCanvas() ? iface.mapCanvas() : null
        ignoreUnknownSignals: true

        function onVisibleChanged() {
            closePanelIfMapHidden();
        }

        function onEnabledChanged() {
            closePanelIfMapHidden();
        }

        function onOpacityChanged() {
            closePanelIfMapHidden();
        }
    }

    Connections {
        target: nativeCameraResource

        function onResourceReceived(path) {
            if (!nativeCameraInProgress) return;

            nativeCameraInProgress = false;
            nativeCameraResource = null;

            if (!pendingCapture) return;

            if (!path || path === "") {
                iface.mainWindow().displayToast("❌ No photo received from native camera.");
                pendingCapture = null;
                return;
            }

            debugToast("native camera received: " + path, 1500);

            var data = pendingCapture;
            pendingCapture = null;
            createAndAddFeature(data.layer, data.geometry, data.typeValue, data.photoFieldIndex, path);
        }
    }

    Connections {
        target: platformUtilities
        ignoreUnknownSignals: true

        function onResourceCanceled(message) {
            if (!nativeCameraInProgress) return;

            nativeCameraInProgress = false;
            nativeCameraResource = null;
            pendingCapture = null;

            var msg = message && message.length > 0 ? message : "Camera canceled.";
            iface.mainWindow().displayToast("⚠️ " + msg);
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
        parent: iface.mapCanvas()
        anchors.fill: parent
        z: 1000000000000
        color: panelVisible ? "#00000080" : "transparent"
        visible: panelVisible && activeCamera === null && isMapCanvasForeground()

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

        // Bottom half: buttons for bottom group
        Column {
            y: parent.height * 0.5
            height: parent.height * 0.5
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.8
            spacing: (parent.height * 0.5 - quickCaptureRoot.bottomSlotCount * captureOverlay.height * quickCaptureRoot.captureButtonHeightFactor) / (quickCaptureRoot.bottomSlotCount + 1)
            topPadding: (parent.height * 0.5 - quickCaptureRoot.bottomSlotCount * captureOverlay.height * quickCaptureRoot.captureButtonHeightFactor) / (quickCaptureRoot.bottomSlotCount + 1)
            visible: panelVisible && buttonList.length > 0

            Repeater {
                model: quickCaptureRoot.bottomGroupCount
                Button {
                    id: bottomCaptureButton
                    property int buttonModelIndex: quickCaptureRoot.getBottomButtonIndex(quickCaptureRoot.bottomGroupCount - 1 - index)
                    property string buttonTypeValue: buttonModelIndex >= 0 ? buttonList[buttonModelIndex] : ""
                    width: captureOverlay.width * 0.7
                    height: captureOverlay.height * quickCaptureRoot.captureButtonHeightFactor
                    topPadding: quickCaptureRoot.captureButtonVPadding
                    bottomPadding: quickCaptureRoot.captureButtonVPadding
                    leftPadding: quickCaptureRoot.captureButtonHPadding
                    rightPadding: quickCaptureRoot.captureButtonHPadding
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: buttonTypeValue

                    onClicked: {
                        if (buttonModelIndex >= 0) captureFeature(buttonTypeValue);
                    }

                    background: Rectangle {
                        color: quickCaptureRoot.getButtonBackgroundColor(parent.buttonTypeValue); radius: 18;
                        border.color: "white"; border.width: 3
                        opacity: parent.pressed ? 0.7 : 1.0
                    }
                    contentItem: Item {
                        id: bottomContentItem
                        property string iconSource: quickCaptureRoot.getButtonIconSource(bottomCaptureButton.buttonTypeValue)

                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            visible: bottomContentItem.iconSource !== ""

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 26
                                source: bottomContentItem.iconSource
                                visible: status !== Image.Error
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: bottomCaptureButton.text
                                color: quickCaptureRoot.getButtonTextColor(bottomCaptureButton.buttonTypeValue)
                                font.bold: true
                                font.pixelSize: 26
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: bottomContentItem.iconSource === ""
                            text: bottomCaptureButton.text
                            color: quickCaptureRoot.getButtonTextColor(bottomCaptureButton.buttonTypeValue)
                            font.bold: true
                            font.pixelSize: 26
                        }
                    }
                }
            }
        }

        // Top half: buttons for top group
        Column {
            y: 0
            height: parent.height * 0.5
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.8
            spacing: (parent.height * 0.5 - quickCaptureRoot.topSlotCount * captureOverlay.height * quickCaptureRoot.captureButtonHeightFactor) / (quickCaptureRoot.topSlotCount + 1)
            topPadding: (parent.height * 0.5 - quickCaptureRoot.topSlotCount * captureOverlay.height * quickCaptureRoot.captureButtonHeightFactor) / (quickCaptureRoot.topSlotCount + 1)
            visible: panelVisible && quickCaptureRoot.topGroupCount > 0

            Repeater {
                model: quickCaptureRoot.topGroupCount
                Button {
                    id: topCaptureButton
                    property int buttonModelIndex: quickCaptureRoot.getTopButtonIndex(quickCaptureRoot.topGroupCount - 1 - index)
                    property string buttonTypeValue: buttonModelIndex >= 0 ? buttonList[buttonModelIndex] : ""
                    width: captureOverlay.width * 0.7
                    height: captureOverlay.height * quickCaptureRoot.captureButtonHeightFactor
                    topPadding: quickCaptureRoot.captureButtonVPadding
                    bottomPadding: quickCaptureRoot.captureButtonVPadding
                    leftPadding: quickCaptureRoot.captureButtonHPadding
                    rightPadding: quickCaptureRoot.captureButtonHPadding
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: buttonTypeValue

                    onClicked: {
                        if (buttonModelIndex >= 0) captureFeature(buttonTypeValue);
                    }

                    background: Rectangle {
                        color: quickCaptureRoot.getButtonBackgroundColor(parent.buttonTypeValue); radius: 18;
                        border.color: "white"; border.width: 3
                        opacity: parent.pressed ? 0.7 : 1.0
                    }
                    contentItem: Item {
                        id: topContentItem
                        property string iconSource: quickCaptureRoot.getButtonIconSource(topCaptureButton.buttonTypeValue)

                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            visible: topContentItem.iconSource !== ""

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 26
                                source: topContentItem.iconSource
                                visible: status !== Image.Error
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: topCaptureButton.text
                                color: quickCaptureRoot.getButtonTextColor(topCaptureButton.buttonTypeValue)
                                font.bold: true
                                font.pixelSize: 26
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: topContentItem.iconSource === ""
                            text: topCaptureButton.text
                            color: quickCaptureRoot.getButtonTextColor(topCaptureButton.buttonTypeValue)
                            font.bold: true
                            font.pixelSize: 26
                        }
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
            checkIfTypesCanBeLoaded();
            Qt.callLater(function() {
                refreshEditableLayerList();
                checkIfTypesCanBeLoaded();
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
                text: quickCaptureRoot.buttonListString
                onTextEdited: quickCaptureRoot.buttonListString = text
            }

            Button {
                text: "load types from quick_capture_types"
                Layout.alignment: Qt.AlignHCenter
                enabled: canLoadTypesFromLayer
                onClicked: loadTypesFromLayer()
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
    Component {
        id: cameraComponent

        QFieldItems.QFieldCamera {
            id: qfieldCamera
            parent: iface.mainWindow().contentItem

            Component.onCompleted: {
                debugToast("camera component completed", 1200);
            }

            onFinished: (path) => {
                debugToast("camera finished", 1200);
                close();
                if (quickCaptureRoot.activeCamera === qfieldCamera) {
                    quickCaptureRoot.activeCamera = null;
                }
                if (pendingCapture) {
                    completeCaptureWithPhoto(path);
                }
                destroy();
            }

            onCanceled: {
                debugToast("camera canceled", 1200);
                close();
                if (quickCaptureRoot.activeCamera === qfieldCamera) {
                    quickCaptureRoot.activeCamera = null;
                }
                pendingCapture = null;
                destroy();
            }

            onClosed: {
                debugToast("camera closed", 1200);
                if (quickCaptureRoot.activeCamera === qfieldCamera) {
                    quickCaptureRoot.activeCamera = null;
                }
                pendingCapture = null;
                destroy();
            }
        }
    }

    function clearActiveCamera() {
        if (!activeCamera) return;

        try {
            if (typeof activeCamera.close === "function") {
                activeCamera.close();
            }
        } catch (e) {
            logDebug("clearActiveCamera close failed: " + e);
        }

        try {
            activeCamera.destroy();
        } catch (e2) {
            logDebug("clearActiveCamera destroy failed: " + e2);
        }

        activeCamera = null;
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
        var names = getLayerFieldNames(layer);
        if (!names || names.length === 0) return -1;

        for (var i = 0; i < names.length; ++i) {
            if (!names[i]) continue;
            if (names[i].toLowerCase() === "photo") {
                return i;
            }
        }
        for (var c = 0; c < photoFieldCandidates.length; ++c) {
            var candidate = photoFieldCandidates[c];
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

        debugToast("startCameraCapture called", 1200);
        logDebug("startCameraCapture: type=" + typeValue + ", photoFieldIndex=" + photoFieldIndex + ", useCamera=" + useCamera);

        // Ensure camera images are saved inside the project folder.
        try {
            platformUtilities.createDir(qgisProject.homePath, 'DCIM');
        } catch (e) {
            // ignore if not available
        }

        // Prefer platform native camera flow (same approach as QField's ExternalResource widget).
        try {
            if (platformUtilities && platformUtilities.capabilities && (platformUtilities.capabilities & PlatformUtilities.NativeCamera)) {
                var now = new Date();
                var filename = "JPEG_"
                        + now.getFullYear()
                        + (now.getMonth() + 1).toString().padStart(2, "0")
                        + now.getDate().toString().padStart(2, "0")
                        + "_"
                        + now.getHours().toString().padStart(2, "0")
                        + now.getMinutes().toString().padStart(2, "0")
                        + now.getSeconds().toString().padStart(2, "0")
                        + ".JPG";
                var relativePath = "DCIM/" + filename;

                debugToast("launching native camera", 1200);
                nativeCameraResource = platformUtilities.getCameraPicture(qgisProject.homePath + "/", relativePath, FileUtils.fileSuffix(relativePath), quickCaptureRoot);

                if (nativeCameraResource) {
                    nativeCameraInProgress = true;
                    return;
                }

                debugToast("native camera unavailable, using in-app camera", 1500);
            }
        } catch (nativeErr) {
            logDebug("native camera launch failed: " + nativeErr);
            debugToast("native camera failed, using in-app camera", 1500);
        }

        if (!iface || !iface.mainWindow || !iface.mainWindow() || !iface.mainWindow().contentItem) {
            iface.mainWindow().displayToast("❌ Unable to access app window for camera.");
            pendingCapture = null;
            return;
        }

        clearActiveCamera();

        debugToast("creating camera object", 1200);
        var cameraObj = cameraComponent.createObject(iface.mainWindow().contentItem);
        if (!cameraObj) {
            iface.mainWindow().displayToast("❌ Failed to create camera object.");
            pendingCapture = null;
            return;
        }

        activeCamera = cameraObj;
        debugToast("camera object created", 1200);

        try {
            if (typeof cameraObj.setProperty === "function") {
                cameraObj.setProperty("z", 2147483647);
                cameraObj.setProperty("visible", true);
                cameraObj.setProperty("focus", true);
            } else {
                if ("z" in cameraObj) cameraObj.z = 2147483647;
                if ("visible" in cameraObj) cameraObj.visible = true;
                if ("focus" in cameraObj) cameraObj.focus = true;
            }
        } catch (prepErr) {
            logDebug("camera property prep failed: " + prepErr);
        }

        if (typeof cameraObj.forceActiveFocus === "function") {
            try {
                cameraObj.forceActiveFocus();
            } catch (focusErr) {
                logDebug("camera forceActiveFocus failed: " + focusErr);
            }
        }

        debugToast("camera prepared for display", 1200);

        if (typeof cameraObj.open === "function") {
            try {
                debugToast("calling camera.open()", 1200);
                cameraObj.open();
                debugToast("camera.open() returned", 1200);
                Qt.callLater(function() {
                    if (activeCamera === cameraObj) {
                        debugToast("post-open: camera still active", 1200);
                    }
                });
            } catch (e3) {
                logDebug("cameraObj.open failed: " + e3);
                iface.mainWindow().displayToast("❌ Failed to open camera.");
                clearActiveCamera();
                pendingCapture = null;
            }
        } else {
            iface.mainWindow().displayToast("❌ Camera object has no open() method.");
            clearActiveCamera();
            pendingCapture = null;
        }
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

    function coordinateValue(point, axisName) {
        if (!point) return null;

        // Different bindings may expose coordinates as properties (x/y) or methods (x()/y()).
        var propertyValue = point[axisName];
        if (typeof propertyValue === "number") {
            return propertyValue;
        }
        if (typeof propertyValue === "function") {
            try {
                var methodValue = propertyValue.call(point);
                if (typeof methodValue === "number") {
                    return methodValue;
                }
            } catch (e) {
                return null;
            }
        }

        return null;
    }

    function getMapCenterPosition() {
        if (!iface || !iface.mapCanvas || !iface.mapCanvas()) {
            return null;
        }

        var canvas = iface.mapCanvas();
        var center = null;

        try {
            if (typeof canvas.center === "function") {
                center = canvas.center();
            } else if (typeof canvas.center !== "undefined") {
                center = canvas.center;
            }
        } catch (e) {
            center = null;
        }

        var mapSettings = canvas.mapSettings;
        if (!center && mapSettings) {
            try {
                var visibleExtent = (typeof mapSettings.visibleExtent === "function") ? mapSettings.visibleExtent() : mapSettings.visibleExtent;
                if (visibleExtent) {
                    center = (typeof visibleExtent.center === "function") ? visibleExtent.center() : visibleExtent.center;
                }
            } catch (e2) {
                center = null;
            }
        }

        if (!center && mapSettings) {
            try {
                var extent = (typeof mapSettings.extent === "function") ? mapSettings.extent() : mapSettings.extent;
                if (extent) {
                    center = (typeof extent.center === "function") ? extent.center() : extent.center;
                }
            } catch (e3) {
                center = null;
            }
        }

        if (!center) {
            return null;
        }

        var x = coordinateValue(center, "x");
        var y = coordinateValue(center, "y");
        if (x === null || y === null) {
            return null;
        }

        return { x: x, y: y };
    }

    function captureFeature(typeValue) {
        debugToast("capture button tapped: " + typeValue, 1200);

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

        // Capture at the current map center instead of using GPS.
        var position = getMapCenterPosition();

        if (!position) {
            iface.mainWindow().displayToast("❌ Could not determine the map center.");
            return;
        }

        // Create a point geometry at the chosen location.
        var geometry = GeometryUtils.createGeometryFromWkt("POINT(" + position.x + " " + position.y + ")");
        if (!geometry) {
            iface.mainWindow().displayToast("❌ Failed to create geometry.");
            return;
        }

        var photoFieldIndex = findPhotoFieldIndex(layer);
        if (useCamera) {
            debugToast("camera mode enabled", 1200);
            if (photoFieldIndex < 0) {
                iface.mainWindow().displayToast("⚠️ Camera opened, but no photo field was found. Photo will not be saved to an attribute.");
            }
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


