# About Syphon Virtual Webcam

This free app, created for you by [TroikaTronix/Isadora](https://troikatronix.com), allows you to send a Syphon video stream to a compatible application that supports video input from a webcam. It works with the excellent virtual webcam driver [OBS Virtual Camera for macOS](https://github.com/johnboiles/obs-mac-virtualcam/releases) implemented by John Boiles.

Syphon Virtual Camera will guide you through the process of downloading and installing the OBS Virtual Camera driver. You can download and install the latest version at any time by choosing **Help > Install OBS Virtual Webcam** from the main menu. 

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

# Questions?

You can ask for help on the [TroikaTronix Forum](https://community.troikatronix.com).
