# Gyroflow Toolbox

Allows you to import [Gyroflow](https://github.com/gyroflow/gyroflow) Projects into Apple's [Final Cut Pro](https://www.apple.com/final-cut-pro/).

## What is Gyroflow?

[Gyroflow](https://github.com/gyroflow/gyroflow) is a free and open source application that can stabilize your video by using motion data from a gyroscope and optionally an accelerometer. Modern cameras record that data internally (GoPro, Sony, Insta360 etc), and Gyroflow stabilizes the captured footage precisely by using them. It can also use gyro data from an external source (eg. from Betaflight blackbox).

Gyroflow Toolbox allows you to take the stabilised data from Gyroflow and use it within Final Cut Pro as an effect.

## Credits

This repo was thrown together by [Chris Hocking](https://github.com/latenitefilms).

However, none of this would be possible without the incredible [Gyroflow](https://github.com/gyroflow/gyroflow) project and the incredibly help and support from their main developer, [AdrianEddy](https://github.com/AdrianEddy).

## License

All the code within this repository is licensed under [MIT](LICENSE.md).

However, as soon as you build/compile the Rust code, it uses [`gyroflow_core`](https://github.com/gyroflow/gyroflow/tree/master/src/core) as a dependancy, which uses the [GNU General Public License v3.0](https://github.com/gyroflow/gyroflow/blob/master/LICENSE).

This means that as soon as you build/compile Gyroflow Toolbox, the application falls under the same [GNU General Public License v3.0](https://github.com/gyroflow/gyroflow/blob/master/LICENSE).

All Releases in this repository also fall under the same [GNU General Public License v3.0](https://github.com/gyroflow/gyroflow/blob/master/LICENSE).