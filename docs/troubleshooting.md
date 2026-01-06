# Troubleshooting

### Gyroflow Toolbox's Stabilisation doesn't look like Gyroflow's?

This is the most common support issue we get. Basically...

_**You should always put the Gyroflow Toolbox effect on a clip INSIDE a Compound Clip with EXACTLY the same FRAME RATE and RESOLUTION.**_

If you're working with non-standard aspect ratios (i.e. once's that don't appear in Final Cut Pro's drop-downs when you create new Projects or Compound Clips), if you leave the creation settings to **Automatic**, Final Cut Pro will sometimes get them wrong, and will use a default resolution and/or frame rate - so make sure when you create a new Compound Clip you always use **Custom Settings** and make sure the resolution and frame rate match your source clip EXACTLY.

This is because you should only ever apply the Gyroflow Toolbox effect to an **entire clip** - the clip cannot be trimmed.

Due to limitations in Final Cut Pro's FxPlug4 API - we currently can't determine the source start timecode of a clip. Because of this, the Gyroflow Toolbox effect should only be applied to a clip where the start of the clip hasn't been trimmed in the timeline (i.e. the clip you have in the timeline should show the first frame of the source clip). If you need to trim the start of this clip, you can use the full clip within a Compound Clip, then trim the Compound Clip as required.

We have been in contact with the Final Cut Pro team about this, and there's currently no other better workaround or solution. This is discussed [on GitHub](https://github.com/latenitefilms/GyroflowToolbox/issues/8) and we would appreciate it if you could let Apple know this is something you'd like to see addressed. You can reference our Apple Feedback Assistant ID: **FB12043900**.

---

### Problems with Vertical Sony Footage?

With some Sony MP4 files, Final Cut Pro will automatically rotate the footage from 9x16 to 16x9 without actually setting anything in the rotation metadata in the Final Cut Pro Inspector - so 9x16 footage, just looks like regular 16x9 footage in Final Cut Pro, and there's nothing in the user interface to tell you it's actually rotated.

Gyroflow on the other hand uses the correct native resolution (i.e. 1080x1920), and shows the rotation metadata - so you know it's been rotated to 16x9.

So that Final Cut Pro and Gyroflow Toolbox are on the same page, you need to set the **Input Rotation** and **Video Rotation** to `90` in Gyroflow Toolbox.

---

### I've run into a bug. Where can I find the log files?

You can find Gyroflow Toolbox's log files here:

```
/Users/YOUR-USER-NAME/Library/Containers/com.latenitefilms.GyroflowToolbox.Renderer/Data/Library/Application Support/FxPlug.log
/Users/YOUR-USER-NAME/Library/Containers/com.latenitefilms.GyroflowToolbox.Renderer/Data/Library/Application Support/GyroflowCore.log
```

To access these files, copy the below path, press **COMMAND+SHIFT+G** from Finder (or via the **Go > Go to Folder...** menubar item), and paste in that path into the **Go to Folder** popup:

```
~/Library/Containers/com.latenitefilms.GyroflowToolbox.Renderer/Data/Library/Application Support/
```

You can find any crash reports here:

```
/Users/YOUR-USER-NAME/Library/Logs/DiagnosticReports
```

Again, you can also copy the below path, press **COMMAND+SHIFT+G** from Finder (or via the **Go > Go to Folder...** menubar item), and paste in that path into the **Go to Folder** popup:

```
~/Library/Logs/DiagnosticReports
```

Any crashes related to Gyroflow Toolbox will have **Gyroflow Toolbox** at the start of the filename.

There might also be crash logs in the **Retired** sub-folder (these are crash logs that have already been sent to Apple):

`/Users/YOUR-USER-NAME/Library/Logs/DiagnosticReports/Retired`

You can [post an issue](https://github.com/latenitefilms/gyroflowtoolbox/issues) with these files in a ZIP, and we'll try and resolve your specific problem.