// ===========================================================================
//	VirtCamClient				(c) 2020 Mark F. Coniglio. All rights reserved
// ===========================================================================

#define OBS_VIRTUAL_CAMERA_COMPATIBLE	1

#if OBS_VIRTUAL_CAMERA_COMPATIBLE
	#define kVirtCamMachPortNameOrig	"com.johnboiles.obs-mac-virtualcam.server"
	#define kVirtCamMachPortNameOBSv26	"com.obsproject.obs-mac-virtualcam.server"
	#define VIRTCAM_ROW_BYTES			0
	#define VIRTCAM_FRAME_COMPONENTS	6
#else
	// #define kVirtCamMachPortName		"com.troikatronix.syphon-virtual-camera.server"
	#define kVirtCamMachPortName		"Q5V96MD6S6.com.troikatronix.syphon-virtual-camera.server"
	#define VIRTCAM_ROW_BYTES			1
	#define VIRTCAM_FRAME_COMPONENTS	7
#endif

typedef enum
{
	kVirtCam_Connect	= 1,
	kVirtCam_NewFrame	= 2,
	kVirtCam_Disconnect	= 3,
} VirtCamMessages;

extern bool gIsRunningOBSVirtCam;

#define vc_log_info(...)	printf(__VA_ARGS__)
#define vc_log_error(...)	printf(__VA_ARGS__)

