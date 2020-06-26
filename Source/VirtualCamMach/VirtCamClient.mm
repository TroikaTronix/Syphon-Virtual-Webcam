// ===========================================================================
//	VirtCamClient				(c) 2020 Mark F. Coniglio. All rights reserved
// ===========================================================================

#import <Foundation/Foundation.h>
#import "VirtCamClient.h"

// ---------------------------------------------------------------------------------
//	VirtCamClient : INTERFACE
// ---------------------------------------------------------------------------------
@interface VirtCamClient() <NSPortDelegate>
{
    NSPort*					_mReceivePort;
	CVirtCamClientReceiver*	_mReceiver;
}
@end

// ---------------------------------------------------------------------------------
//	VirtCamClient : IMPLEMENTATION
// ---------------------------------------------------------------------------------
@implementation VirtCamClient

// ---------------------------------------------------------------------------------
//	dealloc
// ---------------------------------------------------------------------------------
- (void)dealloc
{
    vc_log_info("VirtCamClient: Dealloc\n");
	_mReceivePort.delegate = nil;
	if (_mReceiver != NULL) {
		_mReceiver->Release();
		_mReceiver = NULL;
	}
	#if !__has_feature(objc_arc)
		[super dealloc];
	#endif
}

// ---------------------------------------------------------------------------------
//	setReceiver
// ---------------------------------------------------------------------------------
- (void) setReceiver:(CVirtCamClientReceiver*)inReceiver
{
	CVirtCamClientReceiver* oldReceiver = _mReceiver;
	
	_mReceiver = inReceiver;
	_mReceiver->Retain();
	
	oldReceiver->Release();
}

// ---------------------------------------------------------------------------------
//	isServerAvailable
// ---------------------------------------------------------------------------------
// Returns true if a server is available

- (BOOL) isServerAvailable
{
    return ([VirtCamClient getServerPort] != NULL);
}

// ---------------------------------------------------------------------------------
//	connectToServer
// ---------------------------------------------------------------------------------
- (BOOL) connectToServer
{
	BOOL success = NO;
	
	NSPort* serverPort = [VirtCamClient getServerPort];

	if (serverPort != nil) {

		// create an NSPortMessage to request connection to the server
		NSPortMessage *message = [[NSPortMessage alloc] initWithSendPort:serverPort receivePort:self.receivePort components:nil];
		message.msgid = kVirtCam_Connect;

		// set the timeout for message sending
		NSTimeInterval timeout = 5.0;
		// attempt to send the message
		if ([message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:timeout]]) {
			success = YES;
		} else {
			vc_log_error("kVirtCamClient: FAILED TO CONNECT TO SERVER %s!\n", kVirtCamMachPortName);
		}
		
	} else {
		vc_log_error("VirtCamClient: SERVER %s NOT FOUND\n", kVirtCamMachPortName);
	}
	
	return success;
}

// ---------------------------------------------------------------------------------
//	getServerPort
// ---------------------------------------------------------------------------------
// Retrieve's the server port using kVirtCamMachPortName

+ (NSPort*) getServerPort
{
	NSPort* port = [[NSMachBootstrapServer sharedInstance] portForName:@kVirtCamMachPortName];
	return port;
}

// ---------------------------------------------------------------------------------
//	receivePort
// ---------------------------------------------------------------------------------
// Returns true if we have connected to a server

- (NSPort*) receivePort
{
    if (_mReceivePort == nil) {
		
        vc_log_info("VirtCamClient: Will attempt to connect to server...\n");
		
   		// create a mach port on which to receive data
        NSPort *receivePort = [NSMachPort port];
		
        if (receivePort != NULL) {
		
			// set receive port
			_mReceivePort = receivePort;
			// and make ourself the delegate of that port
			_mReceivePort.delegate = self;
			
			// create a weak reference to ourself for use within the dispatch queue
			__weak typeof(self) weakSelf = self;
			
			// exceute
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				
				// get the current run loop
				NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
				
				// add our port to the run loop
				[runLoop addPort:receivePort forMode:NSDefaultRunLoopMode];
				
				// while self exists, execute the run loop. once self is released
				// we will exit this loop
				while (weakSelf) {
					[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
				}
				vc_log_info("VirtCamClient: Shutting down receive run loop\n");
			});
			
			vc_log_info("VirtCamClient: Created Mach Port %d for Client\n", ((NSMachPort *)_mReceivePort).machPort);
			
        } else {
			vc_log_error("VirtCamClient: COULD NOT CREATE MACH PORT\n");
		}
    }
	
    return _mReceivePort;
}

// ---------------------------------------------------------------------------------
//	receivePort
// ---------------------------------------------------------------------------------
- (void) handlePortMessage:(NSPortMessage*)message
{
	NSArray *components = message.components;

	switch (message.msgid) {

	case kVirtCam_Connect:
		{
			vc_log_info("VirtCamClient: Connect Request\n");
		}
		break;

	case kVirtCam_NewFrame:
		{
			vc_log_info("VirtCamClient: Frame Received\n");
			
			if (components.count == VIRTCAM_FRAME_COMPONENTS) {
				
				int index0 = 0;
				
				CGFloat sizeHorz;
				[components[index0++] getBytes:&sizeHorz length:sizeof(sizeHorz)];
				
				CGFloat sizeVert;
				[components[index0++] getBytes:&sizeVert length:sizeof(sizeVert)];
				
				#if VIRTCAM_ROW_BYTES
				uint32_t rowBytes;
				[components[index0++] getBytes:&rowBytes length:sizeof(rowBytes)];
				#endif
				
				uint64_t timestamp;
				[components[index0++] getBytes:&timestamp length:sizeof(timestamp)];
				
				vc_log_info("Received frame data: %fx%f (%llu)\n", sizeHorz, sizeVert, timestamp);
				
				NSData* frameData = components[index0++];
				
				uint32_t fpsNumerator;
				[components[index0++] getBytes:&fpsNumerator length:sizeof(fpsNumerator)];
				
				uint32_t fpsDenominator;
				[components[index0++] getBytes:&fpsDenominator length:sizeof(fpsDenominator)];
				
				if (_mReceiver != NULL) {
					_mReceiver->ReceiveFrame(
						[frameData bytes],
						sizeHorz,
						sizeVert,
						#if VIRTCAM_ROW_BYTES
						rowBytes,
						#endif
						timestamp,
						fpsNumerator,
						fpsDenominator);
				}
				
				// [self.delegate receivedFrameWithSize:NSMakeSize(sizeHorz, sizeVert) rowBytes:rowBytes timestamp:timestamp fpsNumerator:fpsNumerator fpsDenominator:fpsDenominator frameData:frameData];
			}
		}
		break;

	case kVirtCam_Disconnect:
		{
			vc_log_info("VirtCamClient: Disonnect Request\n");
			if (_mReceiver != NULL) {
				_mReceiver->ServerStoppedNotification();
			}
			// [self.delegate receivedStop];
		}
		break;

	default:
		{
			vc_log_error("VirtCamServer: Invalid Mach Port Message ID %u\n", (unsigned) message.msgid);
		}
		break;
	}
}

@end

// ---------------------------------------------------------------------------------
//	CVirtCamServer [CONSTRUCTOR]
// ---------------------------------------------------------------------------------

CVirtCamClient::CVirtCamClient() :
	mRefCount(1),
	mVirtCamClientRef( [[VirtCamClient alloc] init] )
{
	
}

// ---------------------------------------------------------------------------------
//	~CVirtCamClient [DESTRUCTOR]
// ---------------------------------------------------------------------------------

CVirtCamClient::~CVirtCamClient()
{
	#if !__has_feature(objc_arc)
		[mVirtCamClientRef release];
	#endif
	mVirtCamClientRef = NULL;
}

// ---------------------------------------------------------------------------------
//	Retain
// ---------------------------------------------------------------------------------

void
CVirtCamClient::Retain()
{
	mRefCount += 1;
}

// ---------------------------------------------------------------------------------
//	Retain
// ---------------------------------------------------------------------------------

void
CVirtCamClient::Release()
{
	mRefCount -= 1;
	if (mRefCount == 0) {
		delete this;
	}
}

// ---------------------------------------------------------------------------------
//	IsServerAvailable
// ---------------------------------------------------------------------------------

bool
CVirtCamClient::IsServerAvailable()
{
	bool isAvailable = [VirtCamClient getServerPort] != NULL;
	return isAvailable;
}

// ---------------------------------------------------------------------------------
//	IsConnectedToServer
// ---------------------------------------------------------------------------------

bool
CVirtCamClient::IsConnectedToServer()
{
	bool isAvailable = false;
	if (mVirtCamClientRef != NULL) {
		isAvailable = [mVirtCamClientRef receivePort] != NULL;
	}
	return isAvailable;
}

// ---------------------------------------------------------------------------------
//	GetServerUUID
// ---------------------------------------------------------------------------------

std::string
CVirtCamClient::GetServerUUID()
{
	return kVirtCamMachPortName;
}

// ---------------------------------------------------------------------------------
//	GetClientName
// ---------------------------------------------------------------------------------

std::string
CVirtCamClient::GetServerDeviceName()
{
	return "Virtual Camera";
}

// ---------------------------------------------------------------------------------
//	GetClientName
// ---------------------------------------------------------------------------------

std::string
CVirtCamClient::GetServerApplicationName()
{
	return "TroikaTronix";
}

// ---------------------------------------------------------------------------------
//	SetClientReceiver
// ---------------------------------------------------------------------------------

void
CVirtCamClient::SetClientReceiver(
	CVirtCamClientReceiver*	inReceiver)
{
	if (mVirtCamClientRef != NULL) {
		[mVirtCamClientRef setReceiver:inReceiver];
	}
}


