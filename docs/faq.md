# Frequently Asked Questions

### Why Gyroflow Toolbox?

When I first created [BRAW Toolbox](https://brawtoolbox.fcp.cafe), one of the questions I was constantly asked was if I could support BRAW's built-in gyro stabilisation.

When researching other open source gyro stabilisation projects to use as inspiration, I came across [Gyroflow](https://gyroflow.xyz) and instantly fell in love - it's an incredible application, both from an end-users perspective, but also a developers perspective.

I ended up chatting with [AdrianEddy](https://github.com/AdrianEddy), the genius developer behind Gyroflow, and he helped me put together Gyroflow Toolbox so that Final Cut Pro users can access Gyroflow faster and easier.

---

### Why the Mac App Store?

As end users, we love the Mac App Store, because when we purchase a new machine, all our previously purchased apps just auto-magically appear.

We also love the fact that if you have both a Desktop and a Laptop, you can just purchase once, and use the apps on both machines without any fuss.

The Mac App store is also very secure and highly trusted. Everything that's on the App Store is reviewed on multiple levels by Apple, and goes through a detailed App Review process.

As developers, the Mac App Store does have it's negatives - Apple takes a decent cut of all the payments, and there are very strict security and sandboxing requirements.

Even Final Cut Pro itself, isn't actually sandboxed - so we had to spend a lot of time, care and attention, making sure Gyroflow Toolbox works great in a locked-down sandboxed environment.

However, we think the pro's outweight the con's - and all the extra effort to make it App Store friendly was a worthwhile endeavour.

---

### Did you have Beta Testers?

Yes, prior to public release Gyroflow Toolbox was in a public beta from 21st December 2022 to 1st January 2023, and an internal beta before that.

MASSIVE thanks to the hundreds of users who took part in this extensive beta program!

---

### Is Gyroflow Toolbox Open Source?

Yes, Gyroflow Toolbox is completely open source - you can check out it's code on [GitHub](https://github.com/latenitefilms/GyroflowToolbox).

All the code within **this repository** is licensed under [MIT](LICENSE.md).

**However**, as soon as you build/compile the Rust code, it uses [`gyroflow_core`](https://github.com/gyroflow/gyroflow/tree/master/src/core) as a dependancy, which uses the [GNU General Public License v3.0 with App Store Exception](https://github.com/gyroflow/gyroflow/blob/master/LICENSE).

This means that as soon as you build/compile Gyroflow Toolbox, the application falls under the same [GNU General Public License v3.0 with App Store Exception](https://github.com/gyroflow/gyroflow/blob/master/LICENSE) license.

Because of this, any time you build the code in this repository, the binary will also fall under the same [GNU General Public License v3.0 with App Store Exception](https://github.com/gyroflow/gyroflow/blob/master/LICENSE).