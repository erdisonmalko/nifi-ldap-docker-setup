## Getting Started: Importing & Versioning your NiFi Flow
Follow these steps to import the provided flow definition and set up your own versioning bucket.
## 1. Locate the Flow Definition
The JSON definition for this flow is located in the repository at:
./templates/your-flow-definition.json
## 2. Import to NiFi Canvas

   1. Open the NiFi 2.0 UI.
   2. From the top components toolbar, drag the Process Group icon onto the canvas.
   3. In the Add Process Group dialog:
   * Do not type a name yet.
      * Click the Upload icon (next to the name field).
      * Select the your-flow-definition.json file from your local machine.
   4. Once the file is loaded, provide a proper name for your Process Group and click Add.

## 3. Create a New Bucket in NiFi Registry
Before you can version the flow, you must have a destination bucket.

   1. Open your NiFi Registry UI (e.g., http://localhost:18080/nifi-registry).
   2. Click the Settings (wrench icon) in the top right.
   3. Click New Bucket.
   4. Enter a name for your project/environment and click Create.

## 4. Start Version Control

   1. Go back to the NiFi Canvas.
   2. Right-click on your newly imported Process Group.
   3. Select Version > Start version control.
   4. In the dialog:
   * Registry Client: Select your configured registry.
      * Bucket: Select the new bucket you created in Step 3 from the dropdown.
      * Flow Name: Enter a name for this flow in the registry.
   5. Click Save.

