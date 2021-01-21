/*
    SimpleClientAppDelegate.m
	Syphon (SDK)
	
    Copyright 2010-2011 bangnoise (Tom Butterworth) & vade (Anton Marini).
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
    ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SimpleClientAppDelegate.h"
#import "HelpWindowController.h"
#import "VirtCamServer.h"
#import <OpenGL/gl3.h>
#import <CoreVideo/CoreVideo.h>

static NSString * const SyphonVirtCamFirstRunKey  = @"SyphonVCFirstRun";
static NSString * const SyphonVirtCamFirstRunVersionKey  = @"SyphonVCFirstRunVers";
static NSString * const MirrorCheckboxKey  = @"MirrorKey";

#ifdef DEBUG
	#define log_info(msg, ...) printf(msg, ##__VA_ARGS__)
#else
	#define log_info(msg, ...) { }
#endif

#include <mach/mach_time.h>

// ----------------------------------------------------------------------
// NSString (NSLocalizerCategory) CATEGORY
// ----------------------------------------------------------------------

@interface NSString (NSLocalizerCategory)
- (NSString*) localized;
@end

@implementation NSString (NSLocalizerCategory)
- (NSString*) localized
{
	return NSLocalizedString(self, comment: "");
}
@end

// ----------------------------------------------------------------------
// roundUpToMacroblockMultiple HELPER FUNCTION
// ----------------------------------------------------------------------

static size_t roundUpToMacroblockMultiple(size_t size)
{
    return (size + 15) & ~15;
}

// ----------------------------------------------------------------------
// CreateSurfacePixelBufferCreationOptions HELPER FUNCTION
// ----------------------------------------------------------------------

CFDictionaryRef CreateSurfacePixelBufferCreationOptions(IOSurfaceRef surface)
{
	CFDictionaryRef	attr = (__bridge CFDictionaryRef) @{
        (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey : @YES,
    };

    OSType format = IOSurfaceGetPixelFormat(surface);
    size_t width = IOSurfaceGetWidth(surface);
    size_t height = IOSurfaceGetHeight(surface);
    size_t extendedRight = roundUpToMacroblockMultiple(width) - width;
    size_t extendedBottom = roundUpToMacroblockMultiple(height) - height;

    if ((format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        && (IOSurfaceGetBytesPerRowOfPlane(surface, 0) >= width + extendedRight)
        && (IOSurfaceGetBytesPerRowOfPlane(surface, 1) >= width + extendedRight)
        && (IOSurfaceGetAllocSize(surface) >= (height + extendedBottom) * IOSurfaceGetBytesPerRowOfPlane(surface, 0) * 3 / 2)) {
            attr = (__bridge CFDictionaryRef) @{
                (__bridge NSString *)kCVPixelBufferOpenGLCompatibilityKey : @YES,
                (__bridge NSString *)kCVPixelBufferExtendedPixelsRightKey : @(extendedRight),
                (__bridge NSString *)kCVPixelBufferExtendedPixelsBottomKey : @(extendedBottom)
            };
    }

    return attr;
}

// ----------------------------------------------------------------------
// SimpleClientAppDelegate CLASS
// ----------------------------------------------------------------------

#include <VideoToolbox/VideoToolbox.h>

@interface SimpleClientAppDelegate (Private)
- (void)resizeWindowForCurrentVideo;
@end

@implementation SimpleClientAppDelegate
{
    SyphonClient*	syClient;
    VirtCamServer*	virtCamServer;
	NSTimer*		renderTimer;
	NSLock*			renderLock;
	
    CGLContextObj fboContext;
    GLuint fbo;
    GLuint fboTexture;
    GLuint fboWidth;
    GLuint fboHeight;
	
    void* fboRGBBuffer;				// horz/vert size always matches fboWidth/fboHeight
    GLuint fboRGBBufferSize;		// size in bytes
    GLuint fboRGBBufferRowBytes;	// row bytes for the buffer
	
    void* fboYUVBuffer;				// horz/vert size always matches fboWidth/fboHeight
    GLuint fboYUVBufferSize;		// size in bytes
    GLuint fboYUVBufferRowBytes;	// row bytes for the buffer
	
	VTPixelTransferSessionRef vtPixelTransferSessionRef;
	
    IBOutlet NSArrayController *availableServersController;
    
    id <NSObject> _appNapPreventer;

    NSArray *selectedServerDescriptions;

    NSTimeInterval fpsStart;
    NSUInteger fpsCount;
}

// ----------------------------------------------------------------------
// initialize
// ----------------------------------------------------------------------

+ (void)initialize
{
	#if DEBUG
	NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
	[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];
	#endif
	
	NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
	
	// get current build version
	NSString* buildVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey: (NSString *)kCFBundleVersionKey];

	// default value for first run flag is YES
	[defaults setObject:[NSNumber numberWithBool:YES] forKey:SyphonVirtCamFirstRunKey];
	// default value for first run version number is this app's build version
	[defaults setObject:buildVersion forKey:SyphonVirtCamFirstRunVersionKey];
	// default value for mirror checkbox is YES
	[defaults setObject:[NSNumber numberWithBool:YES] forKey:MirrorCheckboxKey];
	
	// register these defaults
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
	
	// set all of the initial values
	[[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:defaults];
}

// ----------------------------------------------------------------------
// init
// ----------------------------------------------------------------------

-(id)init
{
	if (self = [super init]) {
    	renderLock = [[NSLock alloc] init];
    }
    return self;
}

// ----------------------------------------------------------------------
// dealloc
// ----------------------------------------------------------------------

-(void)dealloc
{
	[renderLock lock];
	
	[self DisposeFBO];
	
	if (virtCamServer != NULL) {
		[virtCamServer stopVirtCamServer];
		virtCamServer = NULL;
	}
	
	if (vtPixelTransferSessionRef != NULL) {
		VTPixelTransferSessionInvalidate(vtPixelTransferSessionRef);
		CFRelease(vtPixelTransferSessionRef);
		vtPixelTransferSessionRef = NULL;
	}
	
	if (renderTimer != NULL) {
		[renderTimer invalidate];
		renderTimer = NULL;
	}
	
	[renderLock unlock];
	// [renderLock release];
	renderLock = NULL;
	
}

// ----------------------------------------------------------------------
// keyPathsForValuesAffectingStatus
// ----------------------------------------------------------------------

+ (NSSet *)keyPathsForValuesAffectingStatus
{
    return [NSSet setWithObjects:@"frameWidth", @"frameHeight", @"FPS", @"selectedServerDescriptions", @"view.error", nil];
}

// ----------------------------------------------------------------------
// status
// ----------------------------------------------------------------------

- (NSString *)status
{
    if (self.view.error)
    {
        return self.view.error.localizedDescription;
    }
    else if (self.frameWidth && self.frameHeight)
    {
        return [NSString stringWithFormat:@"%lu x %lu : %lu FPS", (unsigned long)self.frameWidth, (unsigned long)self.frameHeight, (unsigned long)self.FPS];
    }
    else
    {
        return @"--";
    }
}

// ----------------------------------------------------------------------
// applicationShouldTerminateAfterLastWindowClosed
// ----------------------------------------------------------------------

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

// ----------------------------------------------------------------------
// applicationDidFinishLaunching
// ----------------------------------------------------------------------

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSActivityOptions options = NSActivityUserInitiatedAllowingIdleSystemSleep;
    NSString* reason = @"Prevent Interruptions to Video Feed";
    _appNapPreventer = [[NSProcessInfo processInfo] beginActivityWithOptions:options reason:reason];

	NSBundle* bundle = [NSBundle bundleWithPath:@"/Library/CoreMediaIO/Plug-Ins/DAL/obs-mac-virtualcam.plugin"];
	if (bundle == NULL) {
		[self downloadAndInstallVirtualCamera:NO];
	} else {
		if ([self isOBSVirtualWebcamInstalled]) {
			extern bool gIsRunningOBSVirtCam;
			gIsRunningOBSVirtCam = true;
		}
	}

    // We use an NSArrayController to populate the menu of available servers
    // Here we bind its content to SyphonServerDirectory's servers array
    [availableServersController bind:@"contentArray" toObject:[SyphonServerDirectory sharedDirectory] withKeyPath:@"servers" options:nil];
    
    // Slightly weird binding here, if anyone can neatly and non-weirdly improve on this then feel free...
    [self bind:@"selectedServerDescriptions" toObject:availableServersController withKeyPath:@"selectedObjects" options:nil];
	
	[[self.view window] makeKeyAndOrderFront:self];
	[[self.view window] setContentMinSize:(NSSize){400.0,300.0}];
	[[self.view window] setDelegate:self];
	
	self.view.mirror = [[[NSUserDefaults standardUserDefaults] objectForKey:SyphonVirtCamFirstRunKey] boolValue];	// mirror button defaults to enabled

	BOOL firstRun = [[[NSUserDefaults standardUserDefaults] objectForKey:SyphonVirtCamFirstRunKey] boolValue];
	NSString* buildVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey: (NSString *)kCFBundleVersionKey];
	NSString* firstRunVersion = [[NSUserDefaults standardUserDefaults] objectForKey:SyphonVirtCamFirstRunVersionKey];
	if ([firstRunVersion compare:buildVersion] != NSOrderedSame) {
		firstRun = YES;
	}
	if (firstRun) {
		[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithBool:NO] forKey:SyphonVirtCamFirstRunKey];
		[[NSUserDefaults standardUserDefaults] setObject: buildVersion forKey:SyphonVirtCamFirstRunVersionKey];
		[self showHelp:NULL];
	}
}

// ----------------------------------------------------------------------
// selectedServerDescriptions
// ----------------------------------------------------------------------

- (NSArray *)selectedServerDescriptions
{
    return selectedServerDescriptions;
}

// ----------------------------------------------------------------------
// mirrorChanged
// ----------------------------------------------------------------------

- (IBAction)mirrorChanged:(id)sender
{
	BOOL mirror = ([((NSButton*) sender) integerValue] != 0);
	self.view.mirror = mirror;
	[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithBool:mirror] forKey:MirrorCheckboxKey];
	[self renderToVirtualCameraServer];
}

// ----------------------------------------------------------------------
// CreateFBO
// ----------------------------------------------------------------------

- (void) CreateFBO:(CGLContextObj)inClientContext horz:(GLuint)inHorz vert:(GLuint)inVert
{
	// round up to next highest multiple of four
	if (inHorz % 4 != 0) {
		inHorz = (inHorz + 3) & ~0x03;
	}
	
	if (inClientContext != fboContext || fbo == 0 || (inHorz != fboWidth || inVert != fboHeight)) {
	
		[self DisposeFBO];
		
		if (inClientContext != fboContext) {
			CGLContextObj oldContext = fboContext;
			fboContext = inClientContext;
			CGLRetainContext(fboContext);
			if (oldContext != NULL) {
				CGLReleaseContext(oldContext);
			}
		}

		CGLContextObj saveCtx = [self pushContex:fboContext];

		glGenFramebuffers(1, &fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);

		glGenTextures(1, &fboTexture);
		glBindTexture(GL_TEXTURE_2D, fboTexture);

		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, inHorz, inVert, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fboTexture, 0);
		
		GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
		if (status == GL_FRAMEBUFFER_COMPLETE) {
			log_info("FBO Initialized\n");
		} else {
			log_info("FBO Failed to Initialize\n");
		}
		
		fboWidth = inHorz;
		fboHeight = inVert;
		
		fboRGBBufferRowBytes = (GLuint) fboWidth * 4;
		fboRGBBufferSize = fboRGBBufferRowBytes * fboHeight;
		fboRGBBuffer = malloc(fboRGBBufferSize);

		fboYUVBufferRowBytes = (GLuint) fboWidth * 2;
		fboYUVBufferSize = fboYUVBufferRowBytes * fboHeight;
		fboYUVBuffer = malloc(fboYUVBufferSize);

		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		
		[self popContext:saveCtx];
		
	}
}

// ----------------------------------------------------------------------
// DisposeFBO
// ----------------------------------------------------------------------

- (void) DisposeFBO
{
	if (fboContext != NULL) {
	
		CGLContextObj saveCtx =  [self pushContex:fboContext];
		
		if (fbo != 0) {
			glDeleteFramebuffers(1, &fbo);
			fbo = 0;
		}
		if (fboTexture != 0) {
			glDeleteTextures(1, &fboTexture);
			fboTexture = 0;
		}
		
		[self popContext:saveCtx];
		
		CGLReleaseContext(fboContext);
		fboContext = NULL;
	}
	if (fboRGBBuffer != NULL) {
		free(fboRGBBuffer);
		fboRGBBuffer = NULL;
	}
	fboRGBBufferSize = 0;
	fboRGBBufferRowBytes = 0;
	
	if (fboYUVBuffer != NULL) {
		free(fboYUVBuffer);
		fboYUVBuffer = NULL;
	}
	fboYUVBufferSize = 0;
	fboYUVBufferRowBytes = 0;
}

// ----------------------------------------------------------------------
// pushContex
// ----------------------------------------------------------------------

- (CGLContextObj) pushContex:(CGLContextObj) newContext
{
	CGLContextObj saveCtx = CGLGetCurrentContext();
	if (saveCtx != fboContext) {
		CGLSetCurrentContext(fboContext);
	}
	return saveCtx;
}

// ----------------------------------------------------------------------
// popContext
// ----------------------------------------------------------------------

- (void) popContext:(CGLContextObj) savedContext
{
	CGLContextObj curCtx = CGLGetCurrentContext();
	if (curCtx != savedContext) {
		CGLSetCurrentContext(savedContext);
	}
}

// ----------------------------------------------------------------------
// SendFBOTextureToVirtualCamera
// ----------------------------------------------------------------------

- (void) SendFBOTextureToVirtualCamera:(GLint)texture
{
	if (fboContext != NULL && fbo != 0 && fboTexture != 0) {
		
		CGLContextObj saveCtx = CGLGetCurrentContext();
		if (saveCtx != fboContext) {
			CGLSetCurrentContext(fboContext);
		}
		
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT); // we're not using the stencil buffer now
		glDisable(GL_DEPTH_TEST);
		
		glViewport(0, 0, fboWidth, fboHeight);
		

		glBindFramebuffer(GL_FRAMEBUFFER, 0);

		if (saveCtx != fboContext) {
			CGLSetCurrentContext(saveCtx);
		}
	}
}

// ----------------------------------------------------------------------
// setSelectedServerDescriptions
// ----------------------------------------------------------------------

- (void)setSelectedServerDescriptions:(NSArray *)descriptions
{
    if (![descriptions isEqualToArray:selectedServerDescriptions])
    {
        NSString *currentUUID = [selectedServerDescriptions lastObject][SyphonServerDescriptionUUIDKey];
        NSString *newUUID = [descriptions lastObject][SyphonServerDescriptionUUIDKey];
        BOOL uuidChange = newUUID && ![currentUUID isEqualToString:newUUID];
        selectedServerDescriptions = descriptions;

        if (!newUUID || !currentUUID || uuidChange)
        {
            // Stop our current client
            [syClient stop];
            if (virtCamServer != NULL) {
            	[virtCamServer stopVirtCamServer];
 				virtCamServer = NULL;
			}
			
            // Reset our terrible FPS display
            fpsStart = [NSDate timeIntervalSinceReferenceDate];
            fpsCount = 0;
            self.FPS = 0;
            syClient = [[SyphonClient alloc] initWithServerDescription:[descriptions lastObject]
                                                               context:[[self.view openGLContext] CGLContextObj]
                                                               options:nil newFrameHandler:^(SyphonClient *client) {
                // This gets called whenever the client receives a new frame.
                
                // The new-frame handler could be called from any thread, but because we update our UI we have
                // to do this on the main thread.
                
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                
                    // First we track our framerate...
                    self->fpsCount++;
                    float elapsed = [NSDate timeIntervalSinceReferenceDate] - self->fpsStart;
                    if (elapsed > 1.0)
                    {
                        self.FPS = ceilf(self->fpsCount / elapsed);
                        self->fpsStart = [NSDate timeIntervalSinceReferenceDate];
                        self->fpsCount = 0;
                    }
                    // ...then we check to see if our dimensions display or window shape needs to be updated
                    SyphonImage *frame = [client newFrameImage];

                    NSSize imageSize = frame.textureSize;
                    
                    BOOL changed = NO;
                    if (self.frameWidth != imageSize.width)
                    {
                        changed = YES;
                        self.frameWidth = imageSize.width;
                    }
                    if (self.frameHeight != imageSize.height)
                    {
                        changed = YES;
                        self.frameHeight = imageSize.height;
                    }
                    if (changed)
                    {
                        [[self.view window] setContentAspectRatio:imageSize];
                        [self resizeWindowForCurrentVideo];
                    }
                    // ...then update the view and mark it as needing display
                    self.view.image = frame;

                    [self.view setNeedsDisplay:YES];
				
					#if DEBUG
					NSLog(@"Render From Server!");
					#endif
					[self renderToVirtualCameraServer];
					
                }];
            }];
			
            if (syClient != nil) {
            	virtCamServer = [[VirtCamServer alloc] init];
            	[virtCamServer startVirtCamServer];
			}
			
            // If we have a client we do nothing - wait until it outputs a frame
            
            // Otherwise clear the view
            if (syClient == nil)
            {
                self.view.image = nil;

                self.frameWidth = 0;
                self.frameHeight = 0;

                [self.view setNeedsDisplay:YES];
            }
        }
    }
}

// ----------------------------------------------------------------------
// renderToVirtualCameraServerFromTimer
// ----------------------------------------------------------------------

- (void)renderToVirtualCameraServerFromTimer:(NSTimer*)timer
{
	#if DEBUG
	NSLog(@"############# Render With Timer ############# ");
	#endif
	
	[self renderToVirtualCameraServer];
}

// ----------------------------------------------------------------------
// renderToVirtualCameraServer
// ----------------------------------------------------------------------

- (void)renderToVirtualCameraServer
{
	@autoreleasepool {
	
		[renderLock lock];
		
		if (self->virtCamServer != NULL) {
		
			if (renderTimer != NULL) {
				[renderTimer invalidate];
				renderTimer = NULL;
			}
			
			[self CreateFBO:[syClient context] horz:(GLuint)self.frameWidth vert:(GLuint)self.frameHeight];
			
			if (self->fboRGBBuffer != NULL && self->fboRGBBufferSize > 0 && self->fboYUVBuffer != NULL && self->fboYUVBufferSize > 0) {
				
				CVReturn cvErr = kCVReturnSuccess;
				
				// IOSurfaceRef ioSurface = [self->syClient getIOSurface];
				// CVPixelBufferRef pixelBuffer;
				// cvErr = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, ioSurface, CreateSurfacePixelBufferCreationOptions(ioSurface), &pixelBuffer);

				CGLContextObj saveCtx = [self pushContex:self->fboContext];
				[self.view prepareOpenGL];
				[self.view RenderCurrentImageIntoFBO:self->fbo fboWidth:self->fboWidth fboHeight:self->fboHeight pixelData:self->fboRGBBuffer pixelDataSize:self->fboRGBBufferSize pixelDataRowBytes:self->fboRGBBufferRowBytes];
				[self popContext:saveCtx];
				
				CVPixelBufferRef srcpb = NULL;
				CVPixelBufferRef dstpb = NULL;
				
				if (cvErr == kCVReturnSuccess) {
					cvErr = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, self->fboWidth, self->fboHeight, kCVPixelFormatType_32BGRA, self->fboRGBBuffer, self->fboRGBBufferRowBytes, NULL, NULL, NULL, &srcpb);
				}
				if (cvErr == kCVReturnSuccess) {
					cvErr = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, self->fboWidth, self->fboHeight, kCVPixelFormatType_422YpCbCr8, self->fboYUVBuffer, self->fboYUVBufferRowBytes, NULL, NULL, NULL, &dstpb);
				}
				
				if (cvErr == kCVReturnSuccess && srcpb != NULL && dstpb != NULL) {
				
					if (self->vtPixelTransferSessionRef == NULL) {
						cvErr = VTPixelTransferSessionCreate(kCFAllocatorDefault, &self->vtPixelTransferSessionRef);
					}
					if (self->vtPixelTransferSessionRef != NULL) {
						cvErr = VTPixelTransferSessionTransferImage(self->vtPixelTransferSessionRef, srcpb, dstpb);
					}
				}
				
				if (srcpb != NULL) {
					CVPixelBufferRelease(srcpb);
					srcpb = NULL;
				}
				if (dstpb != NULL) {
					CVPixelBufferRelease(dstpb);
					dstpb = NULL;
				}
				
				NSSize fboSize = NSMakeSize(self->fboWidth, self->fboHeight);

				[self->virtCamServer sendFrameWithSize:self->fboYUVBuffer
					size:fboSize
					#if VIRTCAM_ROW_BYTES
					rowbytes:self->fboYUVBufferRowBytes
					#endif
					timestamp:mach_absolute_time()
					fpsNumerator:30000
					fpsDenominator:1000];
				
				#if DEBUG
				static double lastRender_mS = 0.0;
				double renderTime = (double) mach_absolute_time() / (double) 1000000.0;
				NSLog(@"Render Frame at %f mS", renderTime - lastRender_mS);
				lastRender_mS = renderTime;
				#endif
				
				renderTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(renderToVirtualCameraServerFromTimer:) userInfo:NULL repeats:NO];
			}
		} else {
			if (renderTimer != NULL) {
				[renderTimer invalidate];
				renderTimer = NULL;
			}
		}
		
		[renderLock unlock];
	
	}
}

// ----------------------------------------------------------------------
// applicationWillTerminate
// ----------------------------------------------------------------------

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	if (virtCamServer != NULL) {
		[virtCamServer stopVirtCamServer];
		virtCamServer = NULL;
	}
	[syClient stop];
	syClient = nil;

    [[NSProcessInfo processInfo] endActivity:_appNapPreventer];
    _appNapPreventer = nil;
}

#pragma mark Window Sizing

// ----------------------------------------------------------------------
// windowContentSizeForCurrentVideo
// ----------------------------------------------------------------------

- (NSSize)windowContentSizeForCurrentVideo
{
	NSSize imageSize = NSMakeSize(self.frameWidth, self.frameHeight);
	
	if (imageSize.width == 0 || imageSize.height == 0)
	{
		imageSize.width = 640;
		imageSize.height = 480;
	}

    return imageSize;
}

// ----------------------------------------------------------------------
// frameRectForContentSize
// ----------------------------------------------------------------------

- (NSRect)frameRectForContentSize:(NSSize)contentSize
{
    // Make sure we are at least as big as the window's minimum content size
	NSSize minContentSize = [[self.view window] contentMinSize];
	if (contentSize.height < minContentSize.height)
	{
		float scale = minContentSize.height / contentSize.height;
		contentSize.height *= scale;
		contentSize.width *= scale;
	}
	if (contentSize.width < minContentSize.width)
	{
		float scale = minContentSize.width / contentSize.width;
		contentSize.height *= scale;
		contentSize.width *= scale;
	}
    
    NSRect contentRect = (NSRect){[[self.view window] frame].origin, contentSize};
    NSRect frameRect = [[self.view window] frameRectForContentRect:contentRect];
    
    // Move the window up (or down) so it remains rooted at the top left
    float delta = [[self.view window] frame].size.height - frameRect.size.height;
    frameRect.origin.y += delta;
    
    // Attempt to remain on-screen
    NSRect available = [[[self.view window] screen] visibleFrame];
    if ((frameRect.origin.x + frameRect.size.width) > available.size.width)
    {
        frameRect.origin.x = available.size.width - frameRect.size.width;
    }
    if ((frameRect.origin.y + frameRect.size.height) > available.size.height)
    {
        frameRect.origin.y = available.size.height - frameRect.size.height;
    }

    return frameRect;
}

// ----------------------------------------------------------------------
// windowWillUseStandardFrame
// ----------------------------------------------------------------------

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)newFrame
{
	// We get this when the user hits the zoom box, if we're not already zoomed
	if ([window isEqual:[self.view window]])
	{
		// Resize to the current video dimensions
        return [self frameRectForContentSize:[self windowContentSizeForCurrentVideo]];        
    }
	else
	{
		return newFrame;
	}
}

// ----------------------------------------------------------------------
// resizeWindowForCurrentVideo
// ----------------------------------------------------------------------

- (void)resizeWindowForCurrentVideo
{
    // Resize to the correct aspect ratio, keeping as close as possible to our current dimensions
    NSSize wantedContentSize = [self windowContentSizeForCurrentVideo];
    NSSize currentSize = [[[self.view window] contentView] frame].size;
    float wr = wantedContentSize.width / currentSize.width;
    float hr = wantedContentSize.height / currentSize.height;
    NSUInteger widthScaledToHeight = wantedContentSize.width / hr;
    NSUInteger heightScaledToWidth = wantedContentSize.height / wr;
    if (widthScaledToHeight - currentSize.width < heightScaledToWidth - currentSize.height)
    {
        wantedContentSize.width /= hr;
        wantedContentSize.height /= hr;
    }
    else
    {
        wantedContentSize.width /= wr;
        wantedContentSize.height /= wr;
    }
    
    NSRect newFrame = [self frameRectForContentSize:wantedContentSize];
    [[self.view window] setFrame:newFrame display:YES animate:NO];
}

#pragma mark ----- MENU COMMANDS -----

// ----------------------------------------------------------------------
// showHelp
// ----------------------------------------------------------------------

- (IBAction)showHelp:(id)sender
{
	_helpWindowController = [[HelpWindowController alloc] initWithWindowNibName:@"HelpWindowController"];
	[_helpWindowController.window setDelegate:self];
	[_helpWindowController showWindow:self];
	[_helpWindowController.window makeKeyAndOrderFront:NULL];
}

// ----------------------------------------------------------------------
// downloadOBSVirtualCamera
// ----------------------------------------------------------------------

- (IBAction)downloadOBSVirtualCamera:(id)sender
{
	[self downloadAndInstallVirtualCamera:YES];
}

// ----------------------------------------------------------------------
// showPluginPage
// ----------------------------------------------------------------------

- (IBAction)showPluginPage:(id)sender
{
	NSString* urlString = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"PluginPageURL"];
	NSURL* url = [NSURL URLWithString:urlString];
	[[NSWorkspace sharedWorkspace] openURL:url];
}

// ----------------------------------------------------------------------
// showCompatibleCameras
// ----------------------------------------------------------------------

- (IBAction)showCompatibleCameras:(id)sender
{
	NSString* urlString = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CompatibleCamerasURL"];
	NSURL* url = [NSURL URLWithString:urlString];
	[[NSWorkspace sharedWorkspace] openURL:url];
}

// ----------------------------------------------------------------------
// isadoraLearnMore
// ----------------------------------------------------------------------

- (IBAction)isadoraLearnMore:(id)sender
{
	NSURL* url = [NSURL URLWithString:@"https://troikatronix.com"];
	[[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark ----- OBS VIRTUAL WEBCAM PLUGIN -----

// ----------------------------------------------------------------------
// getOBSVirtCamMostRecentURLandVersion
// ----------------------------------------------------------------------

- (NSArray*) getOBSVirtCamMostRecentURLandVersion
{
	NSString* urlString = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"OBSDownloadURL"];
	NSURL* url = [NSURL URLWithString:urlString];
	
	NSString *html = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"/johnboiles/obs-mac-virtualcam/releases/download/([a-zA-Z0-9\\/\\s_\\\\.\\-\\(\\):])+(.pkg)"
																		   options:NSRegularExpressionCaseInsensitive
																			 error:nil];
	
	NSArray *matches = [regex matchesInString:html options:0 range:NSMakeRange(0, html.length)];
	
	NSString* mostRecentDownloadURL = NULL;
	NSString* mostRecentVersion = NULL;
	for (NSTextCheckingResult *match in matches) {
		NSRange matchRange = [match range];
		NSString* matchedString = [html substringWithRange:matchRange];
		if ([matchedString containsString:@"obs-mac-virtualcam"]
		&& ![matchedString containsString:@"issues"]
		&& [matchedString containsString:@"download"]
		&& [matchedString hasSuffix:@".pkg"]) {
			
			NSLog(@"%@", matchedString);
			
			@try {
				NSString* fileURL = matchedString;
				fileURL = [@"https://github.com" stringByAppendingString:fileURL];
				
				if (fileURL != NULL) {
					NSRange versionRange = [fileURL rangeOfString:@"-v" options:NSBackwardsSearch range:NSMakeRange(0, [fileURL length])];
					NSRange pkgRange = [fileURL rangeOfString:@".pkg"];
					NSString* curVersion = NULL;
					if (versionRange.location != NSNotFound && pkgRange.location != NSNotFound) {
						NSUInteger versionStart = versionRange.location + versionRange.length;
						NSUInteger versionEnd = pkgRange.location;
						NSRange versionRange = NSMakeRange(versionStart, versionEnd - versionStart);
						curVersion = [fileURL substringWithRange:versionRange];
					}
					if (curVersion != NULL) {
						if (mostRecentDownloadURL == NULL) {
							mostRecentDownloadURL = fileURL;
							mostRecentVersion = curVersion;
							NSLog(@"Set New Version to %@", mostRecentVersion);
						} else {
							if ([SimpleClientAppDelegate compareVersion:mostRecentVersion toVersion:curVersion] == NSOrderedAscending) {
								mostRecentDownloadURL = fileURL;
								mostRecentVersion = curVersion;
								NSLog(@"Set New Version to %@", curVersion);
							} else {
								NSLog(@"Ignore Version to %@", curVersion);
							}
						}
					}
				}
			} @catch (NSException* ex) {
				NSLog(@"Error processing string %@", matchedString);
			}
		}
	}
	
	return @[mostRecentDownloadURL, mostRecentVersion];

}

// ----------------------------------------------------------------------
// compareVersion
// ----------------------------------------------------------------------

+ (NSComparisonResult)compareVersion:(NSString*)versionOne toVersion:(NSString*)versionTwo {
    NSArray* versionOneComp = [versionOne componentsSeparatedByString:@"."];
    NSArray* versionTwoComp = [versionTwo componentsSeparatedByString:@"."];

    NSInteger pos = 0;

    while ([versionOneComp count] > pos || [versionTwoComp count] > pos) {
        NSInteger v1 = [versionOneComp count] > pos ? [[versionOneComp objectAtIndex:pos] integerValue] : 0;
        NSInteger v2 = [versionTwoComp count] > pos ? [[versionTwoComp objectAtIndex:pos] integerValue] : 0;
        if (v1 < v2) {
            return NSOrderedAscending;
        }
        else if (v1 > v2) {
            return NSOrderedDescending;
        }
        pos++;
    }

    return NSOrderedSame;
}

// ----------------------------------------------------------------------
// getOBSVirtualWebcamVersionNumber
// ----------------------------------------------------------------------
- (NSString*) getOBSVirtualWebcamVersionNumber
{
	NSString* version = NULL;
	
	NSBundle* bundle = [NSBundle bundleWithPath:@"/Library/CoreMediaIO/Plug-Ins/DAL/obs-mac-virtualcam.plugin"];
	if (bundle != NULL) {
		NSDictionary* info = [bundle infoDictionary];
		if (info != NULL) {
			version = [info objectForKey:@"CFBundleShortVersionString"];
		}
	}
	
	return version;
}

// ----------------------------------------------------------------------
// isOBSVirtualWebcamInstalled
// ----------------------------------------------------------------------
- (BOOL) isOBSVirtualWebcamInstalled
{
	BOOL obsVirtualWebCamInstalled = NO;
	
	NSString* version = [self getOBSVirtualWebcamVersionNumber];
	if (version != NULL) {
		NSArray* values = [version componentsSeparatedByString: @"."];
		if (values != NULL
		&& [values objectAtIndex:0] != NULL) {
			const char* majorVersionStr = [[values objectAtIndex:0] UTF8String];
			int majorVersion = atoi(majorVersionStr);
			if (majorVersion >= 26) {
				obsVirtualWebCamInstalled = YES;
			}
		}
	}
	
	return obsVirtualWebCamInstalled;
}

// ----------------------------------------------------------------------
// downloadAndInstallVirtualCamera
// ----------------------------------------------------------------------

- (void) downloadAndInstallVirtualCamera:(BOOL)fromMenu
{
	NSArray* vcamInfo = [self getOBSVirtCamMostRecentURLandVersion];
	
	NSString* pluginURLString = vcamInfo[0];
	NSURL* pluginURL = NULL;
	if (pluginURLString != NULL)
		pluginURL = [NSURL URLWithString:pluginURLString];
	NSString* pluginVersion = vcamInfo[1];

	NSModalResponse response;
	bool quit = false;
	bool exit = false;
	
	bool foundMostRecentVersion = false;
	
	NSString* okText = [@"OK_BUTTON" localized];
	NSString* cancelText = [@"CANCEL_BUTTON" localized];
	NSString* downloadText = [@"DOWNLOAD_BUTTON" localized];
	NSString* quitText = [@"QUIT_BUTTON" localized];
	NSString* continueText = [@"CONTINUE_BUTTON" localized];
	NSString* goToDownloadsButton = [@"GO_TO_DOWNLOADS_BUTTON" localized];

	if ([self isOBSVirtualWebcamInstalled]) {
		NSString* noNeedToDownload1 = [@"NO_NEED_TO_DOWNLAD_1" localized];
		NSString* obsVirtCamVesrion = [self getOBSVirtualWebcamVersionNumber];
		NSString* noNeedToDownload2 = [@"NO_NEED_TO_DOWNLAD_2" localized];
		NSString* infoText = [@"NO_NEED_TO_DOWNLAD_3" localized];
		NSString* msg = [NSString stringWithFormat:@"%@%@%@", noNeedToDownload1, obsVirtCamVesrion, noNeedToDownload2];
		NSAlert* alert = [[NSAlert alloc] init] ;
		[alert addButtonWithTitle:okText];
		[alert setMessageText: msg];
		[alert setInformativeText:infoText];
		[alert setAlertStyle:NSAlertStyleInformational];
		response = [alert runModal];
		alert = NULL;
		foundMostRecentVersion = true;
		return;
	}
	
	if (pluginURLString != NULL && pluginVersion != NULL) {
		NSAlert* alert = [[NSAlert alloc] init] ;
		[alert addButtonWithTitle:downloadText];
		if (fromMenu) {
			[alert addButtonWithTitle:cancelText];
		} else {
			[alert addButtonWithTitle:quitText];
		}
		[alert setMessageText: [@"DOWNLOAD_ALERT_1_MESSAGE" localized]];
		NSString* infoText = [NSString stringWithFormat:[@"DOWNLOAD_ALERT_1_INFO_FMT" localized], pluginVersion];
		[alert setInformativeText:infoText];
		[alert setAlertStyle:NSAlertStyleWarning];
		response = [alert runModal];
		alert = NULL;
		foundMostRecentVersion = true;
	} else {
		NSAlert* alert = [[NSAlert alloc] init] ;
		[alert addButtonWithTitle:goToDownloadsButton];
		if (fromMenu) {
			[alert addButtonWithTitle:cancelText];
		} else {
			[alert addButtonWithTitle:quitText];
		}
		[alert setMessageText:[@"DOWNLOAD_ALERT_1_MESSAGE" localized]];
		NSString* infoText = [NSString stringWithFormat:[@"DOWNLOAD_ALERT_1_INFO_NO_VERSION" localized], nil];
		[alert setInformativeText:infoText];
		[alert setAlertStyle:NSAlertStyleWarning];
		response = [alert runModal];
		alert = NULL;
		NSString* urlString = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"OBSDownloadURL"];
		pluginURL = [NSURL URLWithString:urlString];
	}
	
	switch (response) {
	case NSAlertFirstButtonReturn:
		[[NSWorkspace sharedWorkspace] openURL:pluginURL];
		if (foundMostRecentVersion) {
			usleep(1000000 * 0.10); // wait 1/10 a second
			[[NSApplication sharedApplication] activateIgnoringOtherApps : YES];
		}
		break;
	case NSAlertSecondButtonReturn:
		exit = true;
		break;
	}
	
	if (!exit) {
		if (pluginURLString != NULL && pluginVersion != NULL) {
			NSAlert* alert = [[NSAlert alloc] init] ;
			[alert addButtonWithTitle:continueText];
			if (fromMenu) {
				[alert addButtonWithTitle:cancelText];
			} else {
				[alert addButtonWithTitle:quitText];
			}
			NSString* messageText = [NSString stringWithFormat:[@"DOWNLOAD_ALERT_2_MESSAGE_FMT" localized], [pluginURL lastPathComponent]];
			[alert setMessageText:messageText];
			[alert setAlertStyle:NSAlertStyleInformational];
			response = [alert runModal];
			alert = NULL;
		} else {
			NSAlert* alert = [[NSAlert alloc] init] ;
			[alert addButtonWithTitle:okText];
			[alert addButtonWithTitle:quitText];
			NSString* messageText = [@"DOWNLOAD_ALERT_2_MESSAGE_NO_VERISON" localized];
			[alert setMessageText:messageText];
			[alert setAlertStyle:NSAlertStyleInformational];
			response = [alert runModal];
			alert = NULL;
		}
	}
	
	switch (response) {
	case NSAlertFirstButtonReturn:
		if (pluginURLString != NULL && pluginVersion != NULL) {
			NSArray* urls = [[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask];
			if ([urls count] > 0) {
				NSURL* url = urls[0];
				url = [url URLByAppendingPathComponent:[pluginURL lastPathComponent]];
				[[NSWorkspace sharedWorkspace] openURL:url];
			}
		}
		break;
	case NSAlertSecondButtonReturn:
		exit = true;
		break;
	}
	
	if (!exit) {
		NSAlert* alert = [[NSAlert alloc] init] ;
		[alert addButtonWithTitle:quitText];
		[alert setMessageText: [@"DOWNLOAD_ALERT_3_MESSAGE" localized]];
		[alert setInformativeText: [@"DOWNLOAD_ALERT_3_INFO" localized]];
		[alert setAlertStyle:NSAlertStyleInformational];
		response = [alert runModal];
		alert = NULL;
		quit = YES;
	}

	if (!fromMenu || quit) {
		[NSApp terminate:self];
	}
}
@end
