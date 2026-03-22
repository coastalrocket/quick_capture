Quick Capture QField Plugin

Intended for Big Button feature capture.

Requirements: point layer with text attribute

Define capture buttons via the settings menu. Features are taken at map centre.
Typical use is to set map to follow current location (bottom right button), define capture buttons and then record features.

Details:

The settings button controls the visibility of the capture buttons.

Long press on settings button to display the settings dialog. From here you can:
- change target layer - this is the layer to which features are recorded. Only point features with a text attribute are available
- change type field - this is the field where the capture button's description is recorded to

If the target layer contains:
- an attachment field called 'photo' this will be populated if photos are enabled
- a date/time field called timestamp will be populated

Define capture button descriptions by either:
- defining a quick_capture_types table in the project. See https://app.qfield.cloud/a/andybmapman/quick_capture/ for example project - and load the buttons from the settings dialog. This method allows control over button icons, text and background colour. 
- or define a comma separated list in the settings dialog

If photos are enabled the camera interface is displayed. It's not possible to capture a photo without this interface displaying.

![screenshot](screenshots/quick_capture_example.png)