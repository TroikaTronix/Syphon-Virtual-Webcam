# About Syphon Virtual Webcam

This free app, created for you by [TroikaTronix/Isadora](https://troikatronix.com), allows you to send a Syphon video stream to a compatible application that supports video input from a webcam.  It relies on the Open Broadcasting System (OBS) Virtual Webcam driver first implemented by John Boiles.

If you have installed OBS v26.1 or later, you can install the latest OBS Virtual Webcam driver by opening OBS and choosing **Tools > Start Virtual Webcam**. Please note that you cannot use Syphon Virtual Webcam while OBS's virtual webcam output is running, i.e., after choosing **Tools > Start Virtual Webcam**; trying to do this may lead to unpredictable results including crashes.

If you have not installed OBS (or have installed a version of OBS before v26.1) then Syphon Virtual Camera will guide you through the process of downloading and installing the standalone OBS Virtual Webcam driver from [John Boiles' GitHub Repository](https://github.com/johnboiles/obs-mac-virtualcam).

The latest version of Syphon Virtual Webcam can be found in the [plugins](https://troikatronix.com/plugin/syphon-virtual-webcam/) section of the TroikaTronix website.

# Download

The latest version of Syphon Virtual Webcam can always be found in the [plugins section](https://troikatronix.com/plugin/syphon-virtual-webcam/) of the TroikaTronix website.

# Compatibility

The applications that work with with OBS Virtual Camera depend on the version of macOS you are using and the application itself. Jump to the the [OBS Virtual Camera Compatibility](https://github.com/johnboiles/obs-mac-virtualcam/wiki/Compatibility) listing for the most recent list of compatible (and incompatible) applications.

# How to Use

1. Ensure your Syphon source is running.
1. Select your Syphon source using the popup menu in the main window.
1. Start the app that will receive a signal from the virtual webcam
1. Choose "OBS Virtual Camera" as the webcam source
1. Click the "Mirror" checkbox if you need to flip the image horizontally.

If you don't see "OBS Virtual Webcam" in the list of webcams, then your app may not be compatible with virtual webcams. Check the [list of applications compatible with OBS Virtual Webcam](https://github.com/johnboiles/obs-mac-virtualcam/wiki/Compatibility).

# Compiling

Clone or download this respository, open the XCode project in XCode 11 or later, and compile. If you wish to distribute this to the public, you will need to add your own developer signature to the code signing options XCode project; otherwise the app will not open on macOS Mojave and later.

# Known Issues

The Syphon image on the GPU must be pulled back into the CPU as an ARGB bitmap. Then it must be converted to YUV so that it can be passed on to OBS Virtual Camera. Neither of these two processes are optimized, so this app is currently CPU hungry. If there is enough interest, we will put more effort into optimizing these two operations.

# Not Working with Zoom?

Some users reported that Syphon Virtual Webcam did not work with Zoom. The following procedure seemed to solve the problem for them.

1.	Quit all applications.
2.	In Finder, choose **Go > Go to Folder...** In the dialog that appears, enter **/Library/CoreMediaIO/Plug-Ins/DAL/** and click "Go"
3.	In the folder that appears, delete **obs-mac-virtualcam.plugin** and then empty the trash
4.	Delete **Zoom** from the Applications folder
5.	Ensure that in the Apple System Preferences, **Security & Privacy > General > Allow Apps Downloaded From** says "App Store and Identified Developers"
6.	Install **Zoom** (Version 5.1.2 or later)
7.	Run **Syphon Virtual Webcam** -- it should automatically ask you to install the **OBS Virtual Camera** driver. Follow the instructions to download and install the **OBS Virtual Camera Plugin**.  (If it doesn't automatically ask you to install the plugin, try choosing **Install OBS Virtual Camera Plugin** from the **Help** menu instead.) 
8.	Reboot your computer
9.	Open **QuickTime Player** and choose **File > New Movie Recording**
10.	Click the little triangle near the record button to show the available video input devices. If you see **OBS Virtual Camera**, select it. (If not, then something has gone wrong. See **Questions** below.)
11.	After selecting **OBS Virtual Camera** in the popup, you should see the **OBS Virtual Camera** test pattern.
12.	If that succeeds, open **Zoom** and try to select **OBS Virtual Camera** as the video input.
13.	If that succeeds, run **Syphon Virtual Webcam** and feed it a Syphon video stream. You should be good to go.

# Frequently Asked Questions

**Q: How can I completely uninstall the Syphon Virtual Webcam and the OBS Virtual Webcam driver?**

Follow these steps:

1. Go to the **Applications** folder and drag **Syphon Virtual Webcam** to the Trash.
1. In the Finder choose **Go > Go To Folder**, enter `/Library/CoreMediaIO/Plug-Ins/DAL/`, and click OK.
1. Drag file **obs-mac-virtualcam.plugin** to the Trash.
1. If asked, enter your password to confirm deletion.
1. Restart your computer.

**Q: How can I check what version of OBS Virtual Webcam driver is being used?**

Follow these steps:

1. In the Finder choose **Go > Go To Folder**, enter `/Library/CoreMediaIO/Plug-Ins/DAL/`, and click OK.
1. Select the file **obs-mac-virtualcam.plugin**.
1. Choose File > Get Info.
1. Look for the version number in the top section of the Window.

If the version number is 26.1 or greater, then this driver was installed by the latest version of OBS. If the version number its 1.3.1, then the driver is the version downloaded from John Boiles' GitHub Repository.

# More Questions?

You can ask for help on the [TroikaTronix Forum](https://community.troikatronix.com/topic/6742).

# Release History

**v0.9.6**
Updated Syphon Virtual Webcam to work with either the OBS 26.1 Virtual Webcam driver or the original driver archived on [GitHub](https://github.com/johnboiles/obs-mac-virtualcam).

**v0.9.5**
* Ensured that the **OBS Virtual Camera Is Inactive** screen would not appear when the Syphon source had a very slow frame rate.
* Ensured that "App Nap" was disabled for Syphon Virtual Camera.
* Fixed a bug where a scrambled image would be shown if  the Syphon source width was not divisible by 4.
* ixed a few small memory leaks.
* Added "Download the Latest Version" to the Help Menu.

**v0.9.4**
* Initial Release

