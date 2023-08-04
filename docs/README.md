<img class="rightLogo" src="https://gyroflowtoolbox.io/static/logo.png" align="right" style="width: 100px !important; height: 100px !important;" />

# Gyroflow Toolbox

Allows you to import [Gyroflow](https://github.com/gyroflow/gyroflow) Projects into Apple's [Final Cut Pro](https://www.apple.com/final-cut-pro/).

_**Advanced gyro-based video stabilisation without the round-tripping!**_

![](static/interface.png)

You can even use this in conjunction with [BRAW Toolbox](https://brawtoolbox.io) (also on the App Store), to stabilise **Blackmagic RAW files**!

To get started, simply drop your video clip from the Final Cut Pro Browser or Finder to the drop zone in the Final Cut Pro Inspector. You can also drop a Gyroflow Project.

**Sony**, **GoPro (Hero 8+)**, **DJI**, **Blackmagic RAW** and **Insta360** will be automatically synced when imported. Other cameras, such as **RED**, will require launching Gyroflow to synchronise.

**GoPro**, **DJI** and **Insta360** will automatically select a Lens Profile. For all other cameras, you may need to manually select a Lens Profile, however, we'll try and GUESS a good match.

---

### What is Gyroflow?

[Gyroflow](https://github.com/gyroflow/gyroflow) is a free and open source third-party application that can stabilise your video by using motion data from a gyroscope and optionally an accelerometer. Modern cameras record that data internally (such as Blackmagic, GoPro, Sony, Insta360 etc), and Gyroflow stabilises the captured footage precisely by using that data. It can also use gyro data from an external source, such as Betaflight Blackbox.

Gyroflow Toolbox allows you to take the stabilised data from Gyroflow and use it within Final Cut Pro as an effect, so you don't have to export a ProRes from Gyroflow!

You can watch a great Gyroflow Tutorial [here](https://www.youtube.com/watch?v=QAds3x8UU1w).

---

### Examples

Here are some before-and-after examples by the geniuses over at Gyroflow:

{% embed url="https://gyroflow.xyz/demo/?v=1" %}
**GoPro Hero 6**
{% endembed %}

{% embed url="https://gyroflow.xyz/demo/?demo=1&v=2" %}
**GoPro Hero 5 Session**
{% endembed %}

{% embed url="https://gyroflow.xyz/demo/?demo=2" %}
**GoPro Hero 8**
{% endembed %}

{% embed url="https://gyroflow.xyz/demo/?demo=3" %}
**GoPro Hero 8**
{% endembed %}

{% embed url="https://gyroflow.xyz/demo/?demo=4" %}
**GoPro Hero 10 + Horizon Lock**
{% endembed %}

{% embed url="https://gyroflow.xyz/demo/?demo=5" %}
**Blackmagic Pocket Cinema Camera 4k + Laowa 9mm**
{% endembed %}