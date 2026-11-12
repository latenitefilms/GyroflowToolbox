# How To Use

If you haven't already, follow the installation instructions [here](/installation/) first.

After you have installed Gyroflow Toolbox, you'll see a **Gyroflow Toolbox** Effect in the **Effects Browser**:

![](static/06-install.png)

To use Gyroflow Toolbox, first create a **Compound Clip** of your footage that has gyroscope metadata.

The Compound Clip must have the EXACT SAME frame rate and resolution as your source clip - you need to triple check this, as sometimes Final Cut Pro's `Automatic` setting gets it wrong.

Inside the Compound Clip, apply the Gyroflow Toolbox effect.

Because Effects have no knowledge of what they're applied to, you need to tell the Effect what the source clip is.

Simply drag-and-drop the Compound Clip from the Final Cut Pro Browser to the Gyroflow Toolbox Effect drop-zone.

You'll be prompted to grant sandbox access to the file you just dragged across.

In most cases, for a lot of cameras, that's all you need to do! You can then adjust all the parameters as needed. 🥳

Gyroflow (the hero open source application) is INSANELY powerful, so there's a huge amount of parameters and controls.

---

### Important Limitation

_**You should always put the Gyroflow Toolbox effect on a clip INSIDE a Compound Clip with EXACTLY the same FRAME RATE and RESOLUTION.**_

This is because you should only ever apply the Gyroflow Toolbox effect to an **entire clip** - the clip **cannot** be trimmed.

Due to limitations in Final Cut Pro's FxPlug4 API - we currently can't determine the source start timecode of a clip.

Because of this, the Gyroflow Toolbox effect should only be applied to a clip where the start of the clip hasn't been trimmed in the timeline (i.e. the clip you have in the timeline should show the first frame of the source clip).

If you need to trim the start of this clip, you can use the full clip within a Compound Clip, then trim the Compound Clip as required.

We have been in contact with the Final Cut Pro team about this, and there's currently no other better workaround or solution. This is discussed [on GitHub](https://github.com/latenitefilms/GyroflowToolbox/issues/8) and we would appreciate it if you could let Apple know this is something you'd like to see addressed. You can reference our Apple Feedback Assistant ID: **FB12043900**.

Another annoying thing is that Final Cut Pro's Automatic setting when creating a Compound Clip doesn't properly support non-standard resolutions and aspect ratios - so you really need to TRIPLE CHECK that the frame rate and resolution match your source clip.

---

### Applying the Effect

Again, you should always put the Gyroflow Toolbox effect on a clip INSIDE a Compound Clip with the EXACT same RESOLUTION and FRAME RATE.

It will then look like this:

![](static/07-install.png)

---

### Importing Media File

If you don't already have a Gyroflow Project for a media file, there's a few different ways you can import a media file:

- Drag & Drop from Final Cut Pro Browser
- Drag & Drop from another application (such as an Asset Management Tool)
- Drag & Drop from Finder
- Press the **Import Media File** button

If you drag-and-drop from the Final Cut Pro Browser you will be prompted to select the video file you imported (due to macOS's sandboxing).

If there's a Gyroflow Project next to the Media File with the exact same filename, Gyroflow Toolbox will try to load that file instead.

GoPro, DJI, Insta360 and some Sony files will automatically synchronise (as the gyroscope data is within the media file), so then you'll be presented with:

![](static/10-install.png)

If the Media File requires synchronising in the hero Gyroflow application, Gyroflow Toolbox will launch the Media File in Gyroflow.

If the Media File requires manually loading a **Lens Profile**, Gyroflow Toolbox will prompt to allow you to select a Lens Profile from the built-in collection within Gyroflow.

---

### Importing Gyroflow Project

If you have a pre-existing Gyroflow Project, there's a few different ways you can import a Gyroflow Project:

- Drag & Drop from Finder
- Drag & Drop from another application (such as an Asset Management Tool)
- Press the **Import Gyroflow Project**
- Press the **Import Last Gyroflow Project**

If you have a Gyroflow Project with the same filename sitting next to the Media File, Gyroflow Toolbox will always try and load that Gyroflow Project.

---

### Gyroflow Parameters

Once you've imported a Media File or Gyroflow Project you can then use the Gyroflow Parameters to customise things.

All of the parameters are keyframe-able.

![](static/11-install.png)

**Input Rotation** is when Final Cut Pro rotates the input pixels before feeding to Gyroflow Toolbox.

For example, if an `.mp4` contains rotation in the metadata, Final Cut Pro may automatically rotate it. Gyroflow expects raw pixels directly from the source file, so if Final Cut Pro has already rotated them, it won't match.

Given this, the **Input Rotation** is the rotation done by the host BEFORE feeding to Gyroflow Toolbox, whereas **Video Rotation** is a rotation by the Gyroflow engine AFTER stabilisation.

---

### Tools

There are also some handy tools:

![](static/12-install.png)

#### Stabilisation Overview

This allow you to zoom out the view to see the stabilization results. This is very useful to see if and how Gyroflow is working. You should disable this before rendering.

#### Disable Gyroflow Stretch

If you used Input stretch in the lens profile in Gyroflow, and you de-stretched the video separately in Resolve, check this to disable Gyroflow's internal stretching.

---

### File Management

At the bottom of the Effect is in the Inspector is some File Management tools:

![](static/13-install.png)

**Reload Gyroflow Project** allows you to reload the contents of a Gyroflow Project if you've modified it externally (i.e. in the Gyroflow application).

**Launch Gyroflow** is handy for opening the hero Gyroflow application. If you have a Gyroflow Project or Media File already loaded, it will open that file.

**Export Gyroflow Project** is handy if you imported a GoPro, DJI or Insta360 clip (that didn't require synchronising in the hero Gyroflow application), and you need to export a Gyroflow Project for sharing or editing.

**Reveal in Finder** reveals the Gyroflow Project in Finder.

**Settings** allows you to enable/disable some of the helper alerts/popups throughout the application, **Show Log Files in Finder**, and **Reset All Settings** (which is only really used for debugging/development).
