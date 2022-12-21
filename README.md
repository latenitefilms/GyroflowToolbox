# Gyroflow Toolbox

Allows you to import [Gyroflow](https://github.com/gyroflow/gyroflow) Projects into Apple's [Final Cut Pro](https://www.apple.com/final-cut-pro/).

## What is Gyroflow?

[Gyroflow](https://github.com/gyroflow/gyroflow) is a free and open source application that can stabilize your video by using motion data from a gyroscope and optionally an accelerometer. Modern cameras record that data internally (GoPro, Sony, Insta360 etc), and Gyroflow stabilizes the captured footage precisely by using them. It can also use gyro data from an external source (eg. from Betaflight blackbox).

Gyroflow Toolbox allows you to take the stabilised data from Gyroflow and use it within Final Cut Pro as an effect.

You will need to install the latest [Gyroflow](https://gyroflow.xyz/download) application, before using Gyroflow Toolbox.

## Supported Gyro Sources

You can find a list of all the current supported gyro sources on the [Gyroflow Repository](https://github.com/gyroflow/gyroflow#supported-gyro-sources).

## Known Issues

- Currently all our testing has been done on MacBook Pro's (16-inch 2021, M1 Max, 64GB RAM) running **Final Cut Pro 10.6.5** and **macOS Monterey 12.5.1**. We haven't yet properly tested Intel machines, older versions of macOS, older versions of Final Cut Pro or macOS Ventura. Please [submit an issue](https://github.com/latenitefilms/GyroflowToolbox/issues) if you run into problems.
- Currently to get from FxPlug4 to Gyroflow and back again, we're going from GPU>RAM>GPU>RAM>GPU which isn't very efficient. Hopefully eventually we'll be able to just pass a Metal Texture directly to Gyroflow. ([Issue #6](https://github.com/latenitefilms/GyroflowToolbox/issues/6))
- Currently only 16-bit Float is supported. If Final Cut Pro or Apple Motion supply 32-bit Float and 8-bit images - it won't work. This will be fixed in a later beta. ([Issue #5](https://github.com/latenitefilms/GyroflowToolbox/issues/5))
- The "Import Gyroflow Project" and "Reload Gyroflow Project" buttons can be cropped if the width of the Final Cut Pro Inspector is too small. ([Issue #2](https://github.com/latenitefilms/GyroflowToolbox/issues/2))

## Installation

You can download the latest Gyroflow Toolbox release [here](https://github.com/latenitefilms/GyroflowToolbox/releases/latest).

Download the top ZIP file, then when you extract it, drag the `Gyroflow Toolbox.app` application to your Applications folder.

You should then run the application. If it's the first time installing the software, or if there's been an update, you'll be prompted to **Install Motion Template**.

![Screenshot](Documentation/01-install.png)

Once you click the button, you'll be prompted to grant permission to your Movies folder. This is due to macOS's sandboxing. Click **OK**.

![Screenshot](Documentation/02-install.png)

You then need to click **Grant Access**:

![Screenshot](Documentation/03-install.png)

Once done, you'll be presented with a successful message:

![Screenshot](Documentation/04-install.png)

The button will now be disabled, and will say **Motion Template Installed**. You can now close the Gyroflow Toolbox application.

![Screenshot](Documentation/05-install.png)

## How To Use

After you have installed Gyroflow and Gyroflow Toolbox, you'll see a Gyroflow Toolbox Effect in the Effects Browser.

![Screenshot](Documentation/06-install.png)

You can then apply this effect to any clips that are supported by Gyroflow.

From the Inspector you can then click **Launch Gyroflow**, to open the Gyrflow application.

![Screenshot](Documentation/07-install.png)

You can learn more about Gyroflow [here](https://docs.gyroflow.xyz).

Once you have finished stabilising in Gyroflow you should click the **Export** button arrow and then **Export project file (including processed gyro data)**.

It's important that you include the processed gyro data, otherwise none of the stabilisation will come across to Gyroflow Toolbox.

![Screenshot](Documentation/08-install.png)

You can now press the **Import Gyroflow Project** button in the Final Cut Pro Inspector to import it.

The data from the Gyroflow Project gets saved within the Final Cut Pro library. If you want to reload it, you can either re-import, or if the file is in the same path, you can press **Reload Gyroflow Project**.

You can adjust and keyframe the FOV, Smoothness and Lens Correction within Final Cut Pro.

## Help & Support

For general support and discussion, you can find the Gyroflow developers and other users on the [Gyroflow Discord server](https://discord.gg/BBJ2UVAr2D).

For bug reports and feature requests for Gyroflow Toolbox, please [submit an issue](https://github.com/latenitefilms/GyroflowToolbox/issues).

## Credits

This repository was thrown together by [Chris Hocking](https://github.com/latenitefilms).

However, none of this would be possible without the incredible [Gyroflow](https://github.com/gyroflow/gyroflow) project and the incredibly help and support from their main developer, [AdrianEddy](https://github.com/AdrianEddy).

## License

All the code within **this repository** is licensed under [MIT](LICENSE.md).

**However**, as soon as you build/compile the Rust code, it uses [`gyroflow_core`](https://github.com/gyroflow/gyroflow/tree/master/src/core) as a dependancy, which uses the [GNU General Public License v3.0](https://github.com/gyroflow/gyroflow/blob/master/LICENSE).

This means that as soon as you build/compile Gyroflow Toolbox, the application falls under the same [GNU General Public License v3.0](https://github.com/gyroflow/gyroflow/blob/master/LICENSE). Because of this, all [Releases](https://github.com/latenitefilms/GyroflowToolbox/releases) in this repository also fall under the same [GNU General Public License v3.0](https://github.com/gyroflow/gyroflow/blob/master/LICENSE).