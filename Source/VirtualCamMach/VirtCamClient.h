// ===========================================================================
//	VirtCamClient				(c) 2020 Mark F. Coniglio. All rights reserved
// ===========================================================================

#ifndef _H_VirtCamClient
#define _H_VirtCamClient

#include "VirtCamMessages.h"

#ifdef __cplusplus
	#include <string>
#endif

#ifdef __OBJC__
	NS_ASSUME_NONNULL_BEGIN
#endif

// ---------------------------------------------------------------------------------
// C++ CALLBACK INTERFACE
// ---------------------------------------------------------------------------------

#ifdef __cplusplus

	class CVirtCamClientReceiver
	{
	public:
		virtual void	Retain() = 0;
		virtual void	Release() = 0;
		
		virtual void	ReceiveFrame(
							const void* inFrameData,
							uint32_t inWidth,
							uint32_t inHeight,
							#if VIRTCAM_ROW_BYTES
							uint32_t inRowBytes,
							#endif
							uint64_t inTimestamp,
							uint32_t inFPSNumerator,
							uint32_t inFPSDenominator) = 0;
		
		virtual void	ServerStoppedNotification() = 0;
	};
#endif

// ---------------------------------------------------------------------------------
// OBJECTIVE-C INTERFACE
// ---------------------------------------------------------------------------------

#ifdef __OBJC__

	@protocol VirtCamClientDelegate

	- (void) receivedFrameWithSize:(NSSize)size
			#if VIRTCAM_ROW_BYTES
			rowBytes:(uint32_t)rowBytes
			#endif
			timestamp:(uint64_t)timestamp
			fpsNumerator:(uint32_t)fpsNumerator
			fpsDenominator:(uint32_t)fpsDenominator
			frameData:(NSData *)frameData;
	- (void) receivedStop;

	@end


	@interface VirtCamClient : NSObject

	@property (nullable, weak) id<VirtCamClientDelegate> delegate;

	- (void) setReceiver:(CVirtCamClientReceiver*)inReceiver;

	- (BOOL) isServerAvailable;

	- (BOOL) connectToServer;

	@end

	typedef VirtCamClient*		NSVirtCamClientRef;

#else

	typedef void*				NSVirtCamClientRef;

#endif

// ---------------------------------------------------------------------------------
// C++ INTERFACE
// ---------------------------------------------------------------------------------

#ifdef __cplusplus

	class CVirtCamClient
	{
	public:
							CVirtCamClient();

	private:
							~CVirtCamClient();
		
	public:

		void				Retain();
		void				Release();
		
		bool				IsConnectedToServer();
		
		std::string			GetServerDeviceName();
		std::string			GetServerApplicationName();
		
		void				SetClientReceiver(
								CVirtCamClientReceiver*	inReceiver);

	// STATIC FUNCTIONS
	
		static std::string	GetServerUUID();
		
		static bool			IsServerAvailable();
		
	private:
		int					mRefCount;
		NSVirtCamClientRef	mVirtCamClientRef;
	};

#endif

#ifdef __OBJC__
	NS_ASSUME_NONNULL_END
#endif

#endif
