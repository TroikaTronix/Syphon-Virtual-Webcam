// ===========================================================================
//	VirtCamServer				(c) 2020 Mark F. Coniglio. All rights reserved
// ===========================================================================

#import <Foundation/Foundation.h>
#import "VirtCamServer.h"

// ---------------------------------------------------------------------------------
//	VirtCamServer : INTERFACE
// ---------------------------------------------------------------------------------

@interface VirtCamServer () <NSPortDelegate>
	@property NSPort*			mPort;
	@property NSMutableSet*		mClientPorts;
	@property NSRunLoop*		mRunLoop;
@end


// ---------------------------------------------------------------------------------
//	VirtCamServer : IMPLEMENTATION
// ---------------------------------------------------------------------------------

@implementation VirtCamServer

// ---------------------------------------------------------------------------------
//	init
// ---------------------------------------------------------------------------------

- (id) init {
    if (self = [super init]) {
        self.mClientPorts = [[NSMutableSet alloc] init];
    }
    return self;
}

// ---------------------------------------------------------------------------------
//	dealloc
// ---------------------------------------------------------------------------------

- (void) dealloc
{
    vc_log_info("VirtCamServer: Dealloc\n");
    [self.mRunLoop removePort:self.mPort forMode:NSDefaultRunLoopMode];
    [self.mPort invalidate];
    self.mPort.delegate = NULL;
    #if !__has_feature(objc_arc)
    	[super dealloc];
	#endif
}

// ---------------------------------------------------------------------------------
//	startVirtCamServer
// ---------------------------------------------------------------------------------

- (void) startVirtCamServer
{
	vc_log_info("VirtCamServer: **** ATTEMPT START for %s ***\n", kVirtCamMachPortName);
	
	// if the port has not yet been created
    if (self.mPort == NULL) {

		// attempt to create mach port with virtual camera name
		self.mPort = [[NSMachBootstrapServer sharedInstance] servicePortWithName:@kVirtCamMachPortName];
		
		// if the port was created
		if (self.mPort != NULL) {
		
		   	#if !__has_feature(objc_arc)
			[self.mPort retain];
			#endif
		
			// make ourself the delegate
			self.mPort.delegate = self;

			// get a reference to the current run loop
			self.mRunLoop = [NSRunLoop currentRunLoop];
			// and start running the loop
			[self.mRunLoop addPort:self.mPort forMode:NSDefaultRunLoopMode];

			vc_log_info("VirtCamServer: **** SERVER STARTED for %s ***\n", kVirtCamMachPortName);

		} else {
			vc_log_error("VirtCamServer: NSMachBootstrapServer Failed to Create Port for %s!\n", kVirtCamMachPortName);
			return;
		}

    } else {
        vc_log_info("VirtCamServer: Server for %s already exists.... exiting\n", kVirtCamMachPortName);
        return;
    }
}

// ---------------------------------------------------------------------------------
//	stopVirtCamServer
// ---------------------------------------------------------------------------------

- (void)stopVirtCamServer
{
	vc_log_info("VirtCamServer: **** ATTEMPT STOP *** for %s\n", kVirtCamMachPortName);
	
	vc_log_info("VirtCamServer: Sending kVirtCam_Disconnect (%lu clients)\n", self.mClientPorts.count);
	[self sendMessageToAllClients:kVirtCam_Disconnect components:NULL];
}

// ---------------------------------------------------------------------------------
//	handlePortMessage
// ---------------------------------------------------------------------------------
// Handles an incoming mach port message. The only message we handle is a connect
// reqquest from a client.
//
// See the message definitions in VirtCamMessages.h

- (void) handlePortMessage:(NSPortMessage *)message
{
    switch (message.msgid) {
        case kVirtCam_Connect:
            if (message.sendPort != NULL) {
               	vc_log_info("VirtCamServer: Connection Requested from Mach Port %d\n", ((NSMachPort *)message.sendPort).machPort);
                [self.mClientPorts addObject:message.sendPort];
            }
            break;
        default:
            vc_log_error("VirtCamServer: Invalid Mach Port Message ID %u\n", (unsigned)message.msgid);
            break;
    }
}

// ---------------------------------------------------------------------------------
//	sendFrameWithSize
// ---------------------------------------------------------------------------------

- (void) sendFrameWithSize:(uint8_t*)inFrameData
	size:(NSSize)inFrameSize
	#if VIRTCAM_ROW_BYTES
	rowbytes:(uint32_t)inFrameRowBytes
	#endif
	timestamp:(uint64_t)inTimestamp
	fpsNumerator:(uint32_t)inFPSNumerator
	fpsDenominator:(uint32_t)inFPSDenominator
{
	if ([self.mClientPorts count] > 0) {

		@autoreleasepool {
			#if VIRTCAM_ROW_BYTES
			NSUInteger frameBytes = inFrameRowBytes * (NSUInteger) inFrameSize.height;
			#else
			NSUInteger frameBytes = (NSUInteger) inFrameSize.width * (NSUInteger) inFrameSize.height * 2;
			#endif
			NSData* nsFrameData = [NSData dataWithBytesNoCopy:(void *)inFrameData length:frameBytes freeWhenDone:NO];
			CGFloat sizeHorz = inFrameSize.width;
			NSData* nsSizeHorz = [NSData dataWithBytes:&sizeHorz length:sizeof(sizeHorz)];
			CGFloat sizeVert = inFrameSize.height;
			NSData* nsSizeVert = [NSData dataWithBytes:&sizeVert length:sizeof(sizeVert)];
			#if VIRTCAM_ROW_BYTES
			NSData* nsRowBytes = [NSData dataWithBytes:&inFrameRowBytes length:sizeof(inFrameRowBytes)];
			#endif
			NSData* nsTimestamp = [NSData dataWithBytes:&inTimestamp length:sizeof(inTimestamp)];
			NSData* nsFPSNumerator = [NSData dataWithBytes:&inFPSNumerator length:sizeof(inFPSNumerator)];
			NSData* nsFPSDenominator = [NSData dataWithBytes:&inFPSDenominator length:sizeof(inFPSDenominator)];
			[self sendMessageToAllClients:kVirtCam_NewFrame
				components:@[nsSizeHorz, nsSizeVert,
				#if VIRTCAM_ROW_BYTES
				nsRowBytes,
				#endif
				nsTimestamp,
				nsFrameData,
				nsFPSNumerator,
				nsFPSDenominator]];
		}
	}

}

// ---------------------------------------------------------------------------------
//	sendMessageToAllClients
// ---------------------------------------------------------------------------------

- (void) sendMessageToAllClients:(uint32_t)inMachMessageID
	components:(nullable NSArray *)inComponents
{
	if ([self.mClientPorts count] > 0) {

		// if we lose the connection to a client, this
		// list will be used to remove the client(s) below
		NSMutableSet* removedPorts = [NSMutableSet set];
		
		bool didRemoveClient = false;
		
		// for each client in our list
		for (NSPort *port in self.mClientPorts) {
			@try {
				
				// create a Mach port message with the supplied components
				NSPortMessage* message = [[NSPortMessage alloc] initWithSendPort:port receivePort:NULL components:inComponents];
				// set the mach message ID
				message.msgid = inMachMessageID;
				
				// atempt to send message... if it fails, that means are client
				// is unreachable so we need to remove that client from our list
				
				if (![message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]]) {
					vc_log_error("VirtCamServer: Send Message to Mach Port %d FAILED. Remove Client from Server.\n", ((NSMachPort *)port).machPort);
					[removedPorts addObject:port];
					didRemoveClient = true;
				}
				
			} @catch (NSException *exception) {
				vc_log_error("VirtCamServer: Send Message to Mach Port %d FAILED. Remove Client from Server.\n", ((NSMachPort *)port).machPort);
				vc_log_error("failed to send message (exception) to %d, removing it from the clients!\n", ((NSMachPort *)port).machPort);
				[removedPorts addObject:port];
				didRemoveClient = true;
			}
		}

		// if we removed any clients, then subtract them
		// from our list of clients
		if (didRemoveClient) {
			[self.mClientPorts minusSet:removedPorts];
		}
	}
}

@end

// ---------------------------------------------------------------------------------
//	CVirtCamServer [CONSTRUCTOR]
// ---------------------------------------------------------------------------------

CVirtCamServer::CVirtCamServer() :
	mRefCount(1),
	mVirtCamServerRef( [[VirtCamServer alloc] init] )
{
	
}

// ---------------------------------------------------------------------------------
//	~CVirtCamServer [DESTRUCTOR]
// ---------------------------------------------------------------------------------

CVirtCamServer::~CVirtCamServer()
{
    #if !__has_feature(objc_arc)
	[mVirtCamServerRef release];
	#endif
	mVirtCamServerRef = NULL;
}

// ---------------------------------------------------------------------------------
//	Retain
// ---------------------------------------------------------------------------------

void
CVirtCamServer::Retain()
{
	mRefCount += 1;
}

// ---------------------------------------------------------------------------------
//	Retain
// ---------------------------------------------------------------------------------

void
CVirtCamServer::Release()
{
	mRefCount -= 1;
	if (mRefCount == 0) {
		delete this;
	}
}

// ---------------------------------------------------------------------------------
//	StartServer
// ---------------------------------------------------------------------------------

void
CVirtCamServer::StartServer()
{
	if (mVirtCamServerRef != NULL) {
		[mVirtCamServerRef startVirtCamServer];
	}
}

// ---------------------------------------------------------------------------------
//	StopServer
// ---------------------------------------------------------------------------------

void
CVirtCamServer::StopServer()
{
	if (mVirtCamServerRef != NULL) {
		[mVirtCamServerRef stopVirtCamServer];
	}
}

// ---------------------------------------------------------------------------------
//	StopServer
// ---------------------------------------------------------------------------------

void
CVirtCamServer::SendFrameWithSize(
	uint8_t*	inFrameData,
	NSSize		inFrameSize,
	#if VIRTCAM_ROW_BYTES
	uint32_t	inRowBytes,
	#endif
	uint64_t	inTimeStamp,
	uint32_t	inFPSNumerator,
	uint32_t	inFPSDenominator)
{
	if (mVirtCamServerRef != NULL) {
		[mVirtCamServerRef sendFrameWithSize:inFrameData
			size:inFrameSize
			#if VIRTCAM_ROW_BYTES
			rowbytes:inRowBytes
			#endif
			timestamp:inTimeStamp
			fpsNumerator:inFPSNumerator
			fpsDenominator:inFPSDenominator];
	}
}

