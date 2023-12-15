# Release Notes

### 1.1.4 (Build 18)

#### 🎉 Released:
- 15th December 2023

#### 🔨 Improvements:
- We've updated to the [latest](https://github.com/gyroflow/gyroflow/commit/2b3332dd2631d7ac0aa6e9d0d313db5f308bc386) Gyroflow Core Renderer. HUGE thank you to the amazing [AdrianEddy](https://github.com/AdrianEddy) for all his ongoing help, assistance, genius and support! There should be a minor performance improvement to playback, and slightly lower memory usage.
- Updated from FxPlug `v4.2.7` to `v4.2.9`.
- 3156 lens profiles have been added from the hero Gyroflow project. Thanks to EVERYONE who has submitted lens profiles and another HUGE thank you to [AdrianEddy](https://github.com/AdrianEddy) for all the work that goes into managing them.
- We now load all lens profile when the FxPlug first starts, for faster importing later.
- We now show a loading popup when a Gyroflow project is being imported or generated for Final Cut Pro, so it's obvious that something is busy behind the scenes.
- We've added a **Grant Sandbox Access** and **Reset Sandbox Access** menu items to the **Settings** button in the Inspector, so that you can grant Gyroflow Toolbox access to an entire drive, for faster importing.

#### 🐞 Bug Fix:
- Fixed a potential crash that we've been trying to solve for ages. On SOME systems (specifically systems with Mac2 family GPUs), Apple's Metal Framework would generate a Metal Texture that the Metal Performance Shader in the Mac couldn't actually work with, causing a crash deep within Apple's code. It was very hard to reproduce, as it only happened on certain systems - and none of ours. HUGE thank you to Apple Developer Technical Support, the Final Cut Pro Team, AdrianEddy and Warren Moore for all their constant and on-going help, assistance, guidance, patience and support!

---

### 1.1.3 (Build 17)

#### 🎉 Released:
- 6th September 2023

#### 🐞 Bug Fixes:

- Fixed a bug where the stabilisation wouldn't load correctly after importing a clip or Gyroflow Project into Final Cut Pro until after you modified a parameter or toggled the Stabilisation Overview. Thanks for reporting JoneyMacaroney and JLPG!
- Fixed a bug where the Gyroflow Toolbox version information at the top of the Final Cut Pro Inspector was incorrect. Thanks for reporting JoneyMacaroney and JLPG!

---

### 1.1.2 (Build 16)

#### 🎉 Released:
- 10th August 2023

#### 🐞 Bug Fixes:

- Updated to FxPlug v4.2.7, which offers improved stability and reliability.
- Fixed a bug that could cause a memory leak. Thanks for reporting Денис Глушков!

---

### 1.1.1 (Build 15)

#### 🎉 Released:
- 6th August 2023

#### 🐞 Bug Fixes:

- Fixed an issue where the Gyroflow Toolbox output could be incorrectly clipped when in a HDR project. Thanks for reporting Tumist! Thanks to AdrianEddy for fixing the issue in Gyroflow Core!
- Fixed an issue where a Gyroflow Project could fail to reload correctly after restarting Final Cut Pro due to FxPlug4 incorrectly HTML decoding the string value. We solve this by now base64 encoding the Gyroflow Project in FxPlug4.

---

### 1.1.0 (Build 14)

#### 🎉 Released:
- 4th August 2023


#### 🎉 New Features:

- This is the first update for Gyroflow Toolbox since its launch. We've listened to your feedback and have tried to make it easier, cleaner and faster to use. We've completely re-designed the interface in the Final Cut Pro Inspector, and have re-designed everything under-the-hood to make it faster. HUGE thank you to AdrianEddy for all his help, support and genius! AdrianEddy is the brains behind Gyroflow, and Gyroflow Toolbox wouldn't exist without him - so again, thank you!
- You can now drag-and-drop media files from Final Cut Pro and Finder into the Inspector to load media into Gyroflow Toolbox. This includes BRAW Toolbox clips.
- You can now drag-and-drop Gyroflow Project files from Finder into the Inspector to load Gyroflow Projects into Gyroflow Toolbox.
- You can now press "Import Last Gyroflow Project" to load the last project that was opened in the Gyroflow application.
- You can now load Presets and Lens Profiles directly within Final Cut Pro.
- Gyroflow Toolbox is now compatible with the latest Gyroflow v1.5.2 release, as well as previous older releases.
- Added keyframe-able parameter controls for Horizontal Lock, Horizontal Roll, Position Offset, Input Rotation and Video Rotation.
- Added "Stabilisation Overview" & "Disable Gyroflow Stretch" Tools.
- Added "Reveal in Finder" and "Export Gyroflow Project" File Management Utilities.
- The "Launch Gyroflow" button now opens the active Gyroflow Project or Media File if an existing file has already been loaded into Gyroflow Toolbox.

#### 🐞 Bug Fixes:

- Fixed a bug where reloading the Gyroflow Project didn't do anything due to caching. Thanks for reporting richo!
- Fixed a bug where the Lens Correction was scaling at a different scale compared to Gyroflow. Thanks for reporting lagezon!

---

### 1.0.0 (Build 11)

#### 🎉 Released:
- 1st January 2023

This is the first non-beta release of Gyroflow Toolbox on GitHub! 🥳

Thanks to everyone who helped beta test - especially [@JW144754](https://github.com/JW144754)! Also a HUGE thank you to the amazing [@AdrianEddy](https://github.com/AdrianEddy) for all his endless help, support and technical genius!

#### 🔨 Improvements:
- We have a new icon for Gyroflow Toolbox, designed by the insanely talented [Matthew Skiles](https://matthewskiles.com).
- We no longer ask you for permission to the Movies folder again, if the Motion Template needs updating in a future update.

---

### 1.0.0-beta.9

#### 🎉 Released:
- 30th December 2022

#### ⚠️ Changes:
- Added support for macOS Big Sur. Thanks for suggesting [Nikolai_Ch2](https://twitter.com/Nikolai_Ch2)!

---

### 1.0.0-beta.8

#### 🎉 Released:
- 30th December 2022

#### ⚠️ Changes:
- Updated `gyroflow_core` which addresses the issue discussed in the 1.0.0-beta.6 release notes. Thanks [@AdrianEddy](https://github.com/AdrianEddy)!

---

### 1.0.0-beta.7

#### 🎉 Released:
- 30th December 2022

#### 🐞 Bug Fix:
- Fixed a memory leak by adding `[inputTexture setPurgeableState:MTLPurgeableStateEmpty];`.

---

### 1.0.0-beta.6

#### 🎉 Released:
- 30th December 2022

#### 🐞 Bug Fix:
- Fixed a bug where randomly sometimes the Gyroflow Toolbox effect would inconsistently just render the original image for a frame or two (as opposed to the stabilised image from Gyroflow). We've temporarily added a `command_buffer.wait_until_completed();` call inside `wgpu-hal` to fix the Metal scheduling order. This should be fixed in the `gyroflow_core` Rust code properly at some point. Thanks to [@AdrianEddy](https://github.com/AdrianEddy) for all his Discord problem solving genius!

---

### 1.0.0-beta.5

#### 🎉 Released:
- 30th December 2022

#### 🐞 Bug Fix:
- Fixed potential bug where images in Final Cut Pro could look funky and corrupt, by changing the `texture_copy` flag in `gyroflow_core` to `true` for both input and output Metal Textures.

---

### 1.0.0-beta.4

#### 🎉 Released:
- 29th December 2022

#### 🔨 Improvements:
- Gyroflow Toolbox now exchanges rendered data from `gyroflow_core` directly over a Metal. This should now give Gyroflow Toolbox very similar playback performance to the Gyroflow application. MASSIVE thank you to [@AdrianEddy](https://github.com/AdrianEddy) for all his amazing work and support making this happen! If you notice any glitches or issues on your machine, please submit a [GitHub Issue](https://github.com/latenitefilms/GyroflowToolbox/issues) and roll back to the previous 1.0.0-beta.3 release.

---

### 1.0.0-beta.3

#### 🎉 Released:
- 22nd December 2022

#### 🔨 Improvements:
- Added support for 32-bit float and 8-bit images from Final Cut Pro and Apple Motion. MASSIVE thank you to [@AdrianEddy](https://github.com/AdrianEddy) for all his help and support! [Issue #5]
- `OsLogger` initialisation now only happens once to avoid Console spamming. Thanks [@AdrianEddy](https://github.com/AdrianEddy)! [Issue #7]
- Increased general performance by increasing cache size, and only triggering recomputing when the FOV, Lens Correction or Smoothness has actually changed in the Inspector. Thanks [@AdrianEddy](https://github.com/AdrianEddy)!

---

### 1.0.0-beta.2

#### 🎉 Released:
- 22nd December 2022

**⚠️ Important Changes:**
- 1.0.0-beta.2 makes changes to the Motion Template, so you'll need to install the new Motion Template, then delete and reapply any Gyroflow Toolbox effects you have in your timeline.

#### 🔨 Improvements:
- We now make sure the Gyroflow Project contains processed gyro data before importing to avoid any confusion.
- We've renamed "Import Gyroflow Project" to "Import Project", and "Reload Gyroflow Project" to "Reload Project" to avoid the buttons being clipped in the Final Cut Pro Inspector if you make the width of the Inspector as small as possible. Thanks [@JW144754](https://github.com/JW144754)! [Issue #2](https://github.com/latenitefilms/GyroflowToolbox/issues/2)
- Improved error messages if pressing the "Import Project" button fails.

#### 🐞 Bug Fixes:
- The Final Cut Pro Inspector should no longer hang for a long time when selecting a clip with Gyroflow Toolbox applied. Thanks [@JW144754](https://github.com/JW144754)! [Issue #4](https://github.com/latenitefilms/GyroflowToolbox/issues/4)

---

### 1.0.0-beta.1

#### 🎉 Released:
- 21st December 2022

This is the first public beta of Gyroflow Toolbox. Woohoo!

**⚠️ Known Issues:**
- Currently only 16-bit Float is supported. If Final Cut Pro or Apple Motion supply 32-bit Float and 8-bit images - it won't work. This will be fixed in a later beta.