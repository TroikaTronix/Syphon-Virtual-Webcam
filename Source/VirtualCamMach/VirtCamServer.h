// ===========================================================================
//	VirtCamServer				(c) 2020 Mark F. Coniglio. All rights reserved
// ===========================================================================

#include "VirtCamMessages.h"

#ifdef __OBJC__
	NS_ASSUME_NONNULL_BEGIN
#endif

#ifdef __OBJC__

	@interface VirtCamServer : NSObject

	- (void)startVirtCamServer;
	- (void)stopVirtCamServer;

	- (void) sendFrameWithSize:(uint8_t*)inFrameData
		size:(NSSize)inFrameSize
		#if VIRTCAM_ROW_BYTES
		rowbytes:(uint32_t)inRowBytes
		#endif
		timestamp:(uint64_t)inTimestamp
		fpsNumerator:(uint32_t)inFPSNumerator
		fpsDenominator:(uint32_t)inFPSDenominator;

	@end

	typedef VirtCamServer*		NSVirtCamServerRef;

#else

	typedef void*				NSVirtCamServerRef;

#endif	// #ifdef __OBJC__

#ifdef __cplusplus

	class CVirtCamServer
	{
	public:
		CVirtCamServer();

	private:
		~CVirtCamServer();
	public:

		void		Retain();
		void		Release();
		
		void		StartServer();
		
		void		StopServer();
		
		void		SendFrameWithSize(
						uint8_t*	inFrameData,
						NSSize		inFrameSize,
						#if VIRTCAM_ROW_BYTES
						uint32_t	inRowBytes,
						#endif
						uint64_t	inTimeStamp,
						uint32_t	inFPSNumerator,
						uint32_t	inFSPDenominator);

	private:
		int					mRefCount;
		NSVirtCamServerRef	mVirtCamServerRef;
	};

#endif	// #ifdef __cplusplus

#ifdef __OBJC__
	NS_ASSUME_NONNULL_END
#endif
