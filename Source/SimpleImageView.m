/*
 SimpleImageView.m
 Syphon (SDK)

 Copyright 2010-2014 bangnoise (Tom Butterworth) & vade (Anton Marini).
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

#import "SimpleImageView.h"
#import <OpenGL/gl3.h>

@interface SimpleImageView ()
@property (readwrite) BOOL needsReshape;
@property (readwrite) GLuint splashBkgTexture;
@property (readwrite) GLuint splashTextTexture;
@property (readwrite, retain) NSError *error;
@end

static const char *vertex = "#version 150\n\
in vec2 vertCoord;\
in vec2 texCoord;\
out vec2 fragTexCoord;\
void main() {\
    fragTexCoord = texCoord;\
    gl_Position = vec4(vertCoord, 1.0, 1.0);\
}";

static const char *frag = "#version 150\n\
uniform float alpha;\
uniform sampler2DRect tex;\
in vec2 fragTexCoord;\
out vec4 color;\
void main() {\
    color = texture(tex, fragTexCoord);\
    color *= alpha;\
}";

@implementation SimpleImageView {
    NSSize _imageSize;
    GLuint _program;
    GLuint _alpha;		// uniformat float alpha;
    GLuint _vao;
    GLuint _vbo;
    NSDate* _timerStart;
    NSTimer* _timer;
    double _splashIntensity;
    BOOL _splashDirty;
}

+ (NSError *)openGLError
{
    return [NSError errorWithDomain:@"info.v002.Syphon.Simple.error"
                               code:-1
                           userInfo:@{NSLocalizedDescriptionKey: @"OpenGL Error"}];
}

- (void)awakeFromNib
{
    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFAOpenGLProfile,
        NSOpenGLProfileVersion3_2Core,
        0
    };

    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];

    NSOpenGLContext* context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];

    [self setPixelFormat:pixelFormat];

    [self setOpenGLContext:context];

    self.needsReshape = YES;
    if ([NSView instancesRespondToSelector:@selector(setWantsBestResolutionOpenGLSurface:)])
    {
        // 10.7+
        [self setWantsBestResolutionOpenGLSurface:YES];
    }

    _imageSize = NSMakeSize(0, 0);
	
	_splashIntensity = 1.0;
	_timerStart = [NSDate dateWithTimeIntervalSinceNow:0.0];
	_timer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 target:self selector:@selector(timerFired:) userInfo:NULL repeats:YES];
}

- (void)dealloc
{
    if (_program)
    {
        glDeleteProgram(_program);
    }
    if (_vao)
    {
        glDeleteVertexArrays(1, &_vao);
    }
    if (_vbo)
    {
        glDeleteBuffers(1, &_vbo);
    }
}

- (void) timerFired:(NSTimer *)timer
{
	NSTimeInterval secs = [[NSDate dateWithTimeIntervalSinceNow:0.0] timeIntervalSinceDate:self->_timerStart];
	double min = 2.0;
	double max = min + 0.5;
	if (secs < min) {
		self->_splashIntensity = 1.0;
		[self setNeedsDisplay:YES];
	} else if (secs < max) {
		self->_splashIntensity = 1.0 - (secs - min) / (max - min);
		[self setNeedsDisplay:YES];
		#if DEBUG
		NSLog(@"Fading Out Splash");
		#endif
	} else {
		self->_splashIntensity = 0.0;
		[self->_timer invalidate];
		self->_timer = NULL;
		[self setNeedsDisplay:YES];
	}
}

- (void)prepareOpenGL
{
    [super prepareOpenGL];

    const GLint on = 1;
    [[self openGLContext] setValues:&on forParameter:NSOpenGLCPSwapInterval];

    GLuint vertShader = [self compileShader:vertex ofType:GL_VERTEX_SHADER];
    GLuint fragShader = [self compileShader:frag ofType:GL_FRAGMENT_SHADER];

    if (vertShader && fragShader)
    {
        _program = glCreateProgram();
        glAttachShader(_program, vertShader);
        glAttachShader(_program, fragShader);

        glDeleteShader(vertShader);
        glDeleteShader(fragShader);

        glLinkProgram(_program);
        GLint status;
        glGetProgramiv(_program, GL_LINK_STATUS, &status);
        if (status == GL_FALSE)
        {
            glDeleteProgram(_program);
            _program = 0;
        }
    }

    if (_program)
    {
        glUseProgram(_program);
        GLint tex = glGetUniformLocation(_program, "tex");
        glUniform1i(tex, 0);

        glGenVertexArrays(1, &_vao);
        glGenBuffers(1, &_vbo);

        GLint vertCoord = glGetAttribLocation(_program, "vertCoord");
        GLint texCoord = glGetAttribLocation(_program, "texCoord");

        glBindVertexArray(_vao);
        glBindBuffer(GL_ARRAY_BUFFER, _vbo);

        if (vertCoord != -1 && texCoord != -1)
        {
            glEnableVertexAttribArray(vertCoord);
            glVertexAttribPointer(vertCoord, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), NULL);

            glEnableVertexAttribArray(texCoord);
            glVertexAttribPointer(texCoord, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (GLvoid *)(2 * sizeof(GLfloat)));
        }
        else
        {
            self.error = [[self class] openGLError];
        }

        _alpha = glGetUniformLocation(_program, "alpha");

        glUseProgram(0);

        _imageSize = NSZeroSize;
        // TODO: maybe some of the above can stay bound
    }
    else
    {
        self.error = [[self class] openGLError];
    }
}

- (void)reshape
{
    self.needsReshape = YES;
    [super reshape];
}

- (NSSize)renderSize
{
    if ([NSView instancesRespondToSelector:@selector(convertRectToBacking:)])
    {
        // 10.7+
        return [self convertSizeToBacking:[self bounds].size];
    }
    else return [self bounds].size;
}

- (void)drawRect:(NSRect)dirtyRect
{
    SyphonImage *image = self.image;

    BOOL changed = self.needsReshape || !NSEqualSizes(_imageSize, image.textureSize);

    if (self.needsReshape)
    {
        NSSize frameSize = self.renderSize;

        glViewport(0, 0, frameSize.width, frameSize.height);

        [[self openGLContext] update];

        self.needsReshape = NO;
    }
    
    if (_splashDirty) {
		changed = true;
		_splashDirty = NO;
	}

    if (image && changed)
    {
        _imageSize = image.textureSize;

        NSSize frameSize = self.renderSize;

        NSSize scaled;
        float wr = _imageSize.width / frameSize.width;
        float hr = _imageSize.height / frameSize.height;
        float ratio = (hr < wr ? wr : hr);
        scaled = NSMakeSize(ceilf(_imageSize.width / ratio), ceil(_imageSize.height / ratio));

        // When the view is aspect-restrained, these will always be 1.0
        float width = scaled.width / frameSize.width;
        float height = scaled.height / frameSize.height;

        glBindBuffer(GL_ARRAY_BUFFER, _vbo);

        GLfloat vertices[] = {
            -width, -height,    0.0,                0.0,
            -width,  height,    0.0,                _imageSize.height,
             width, -height,    _imageSize.width,   0.0,
             width,  height,    _imageSize.width,   _imageSize.height
        };

        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);

    if (image)
    {
        glUseProgram(_program);
        glBindTexture(GL_TEXTURE_RECTANGLE, image.textureName);

        glUniform1f(_alpha, 1.0f);

        glBindVertexArray(_vao);

        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        glBindVertexArray(0);
        glBindTexture(GL_TEXTURE_RECTANGLE, 0);
        glUseProgram(0);
    }
	
	if (_splashIntensity > 0.0) {
   		[self drawSplashImage];
   		_splashDirty = YES;
   	}
	
    [[self openGLContext] flushBuffer];
}

- (GLuint)compileShader:(const char *)source ofType:(GLenum)type
{
    GLuint shader = glCreateShader(type);

    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);

    GLint status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);

    if (status == GL_FALSE)
    {
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

- (void)textureFromImage:(NSImage*)theImg textureName:(GLuint*)texName
{
	// Generate a new texture name if one was not provided.
	if (*texName == 0) {
	
		NSBitmapImageRep* bitmap = [NSBitmapImageRep alloc];
		GLint samplesPerPixel = 0;
		NSSize imgSize = [theImg size];

		[theImg lockFocus];
		(void) [bitmap initWithFocusedViewRect: NSMakeRect(0.0, 0.0, imgSize.width, imgSize.height)];
		[theImg unlockFocus];

		// Set proper unpacking row length for bitmap.
		glPixelStorei(GL_UNPACK_ROW_LENGTH, (GLint) [bitmap pixelsWide]);

		// Set byte aligned unpacking (needed for 3 byte per pixel bitmaps).
		glPixelStorei (GL_UNPACK_ALIGNMENT, 1);

		glGenTextures (1, texName);
		glBindTexture (GL_TEXTURE_RECTANGLE, *texName);

		// Non-mipmap filtering (redundant for texture_rectangle).
		glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MIN_FILTER,  GL_LINEAR);
		samplesPerPixel = (GLint) [bitmap samplesPerPixel];

		// Nonplanar, RGB 24 bit bitmap, or RGBA 32 bit bitmap.
		if(![bitmap isPlanar] && (samplesPerPixel == 3 || samplesPerPixel == 4)) {
			glTexImage2D(GL_TEXTURE_RECTANGLE, 0,
				samplesPerPixel == 4 ? GL_RGBA8 : GL_RGB8,
				(GLsizei) [bitmap pixelsWide],
				(GLsizei) [bitmap pixelsHigh],
				0,
				samplesPerPixel == 4 ? GL_RGBA : GL_RGB,
				GL_UNSIGNED_BYTE,
				[bitmap bitmapData]);
		} else {
			// Handle other bitmap formats.
		}

		// Clean up.
		#if !__has_feature(objc_arc)
		[bitmap release];
		#endif
		bitmap = NULL;
	}
}

-(void) drawSplashImage
{
	NSImage* splashBkgImage = [NSImage imageNamed:@"syphon-virtual-webcam-splash-bkg.png"];
	NSImage* splashTextImage = [NSImage imageNamed:@"syphon-virtual-webcam-splash-text.png"];

	[self textureFromImage:splashBkgImage textureName:&_splashBkgTexture];
	[self textureFromImage:splashTextImage textureName:&_splashTextTexture];

   	if (splashBkgImage && splashTextImage && _splashBkgTexture && _splashTextTexture) {
		[self renderTexture:(GLuint)_splashBkgTexture textureSize:(NSSize)[splashBkgImage size] inset:0.8 keepAspect:NO];
		[self renderTexture:(GLuint)_splashTextTexture textureSize:(NSSize)[splashTextImage size] inset:0.8 keepAspect:YES];
	}
}

-(void) renderTexture:(GLuint)textureName textureSize:(NSSize)textureSize inset:(float)inset keepAspect:(BOOL)keepAspect
{
	NSSize frameSize = self.renderSize;

	NSSize scaled;
	float wr = textureSize.width / frameSize.width;
	float hr = textureSize.height / frameSize.height;
	float ratio = (hr < wr ? wr : hr);
	scaled = NSMakeSize(ceilf(textureSize.width / ratio), ceil(textureSize.height / ratio));

	// When the view is aspect-restrained, these will always be 1.0
	float width = scaled.width / frameSize.width * inset;
	float height = scaled.height / frameSize.height * inset;
	if (!keepAspect) {
		width = height = 1.0f;
	}

	glBindBuffer(GL_ARRAY_BUFFER, _vbo);

	GLfloat vertices[] = {
		-width, -height,    0.0,                 textureSize.height*2,
		-width,  height,    0.0,                 0.0,
		 width, -height,    textureSize.width*2, textureSize.height*2,
		 width,  height,    textureSize.width*2, 0.0
	};

	glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
	glBindBuffer(GL_ARRAY_BUFFER, 0);

	glUseProgram(_program);
	glBindTexture(GL_TEXTURE_RECTANGLE, textureName);

	glBindVertexArray(_vao);

	glEnable(GL_BLEND);
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
	glUniform1f(_alpha, _splashIntensity);

	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

	glDisable(GL_BLEND);

	glBindVertexArray(0);
	glBindTexture(GL_TEXTURE_RECTANGLE, 0);
	glUseProgram(0);
}

-(void) LogGLErrors:(const char*)file line:(int)line
{
	GLenum err = glGetError();

	while (err != 0) {
		NSLog(@"OpenGL Error %04X\n", (int) err);
		err = glGetError();
	}
}

#define LogGLError() [self LogGLErrors:__FILE__ line:__LINE__]

-(void) RenderCurrentImageIntoFBO:(GLuint) fbo pixelData:(void*)pixelData pixelDataSize:(GLuint)pixelDataSize pixelDataRowBytes:(GLuint)pixelDataRowBytes
{
	SyphonImage *image = self.image;

	GLint viewport[4];
	glGetIntegerv(GL_VIEWPORT, viewport);
	
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	LogGLError();
	
	NSSize imageSize = NSMakeSize(0, 0);
	
    if (image)
    {
        imageSize = image.textureSize;

 		glViewport(0, 0, imageSize.width, imageSize.height);

       	NSSize frameSize = image.textureSize;

        NSSize scaled;
        float wr = imageSize.width / frameSize.width;
        float hr = imageSize.height / frameSize.height;
        float ratio = (hr < wr ? wr : hr);
        scaled = NSMakeSize(ceilf(imageSize.width / ratio), ceil(imageSize.height / ratio));

        // When the view is aspect-restrained, these will always be 1.0
        float width = scaled.width / frameSize.width;
        float height = scaled.height / frameSize.height;

        glBindBuffer(GL_ARRAY_BUFFER, _vbo);

		if (self.mirror) {
		
			GLfloat vertices[] = {
				-width, -height,    imageSize.width,    imageSize.height,
				-width,  height,    imageSize.width,    0.0,
				 width, -height,    0.0,			    imageSize.height,
				 width,  height,    0.0,				0.0
			};
			glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
        
        } else {
			GLfloat vertices[] = {
				-width, -height,    0.0,                imageSize.height,
				-width,  height,    0.0,                0.0,
				 width, -height,    imageSize.width,    imageSize.height,
				 width,  height,    imageSize.width,	0.0
			};
			glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
		}

        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);

    if (image)
    {
        glUseProgram(_program);
        glBindTexture(GL_TEXTURE_RECTANGLE, image.textureName);

        glUniform1f(_alpha, 1.0f);

        glBindVertexArray(_vao);

        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        glBindVertexArray(0);
        glBindTexture(GL_TEXTURE_RECTANGLE, 0);
        glUseProgram(0);
    }
	
	
	if (image) {
		
		memset(pixelData, 0, pixelDataSize);
		
		if (pixelDataSize >= imageSize.width * imageSize.height * 4) {
		
			glPixelStorei(GL_PACK_ROW_LENGTH, pixelDataRowBytes / 4);
			glPixelStorei(GL_PACK_ALIGNMENT, 1);
			LogGLError();
			glReadPixels(0, 0, imageSize.width, imageSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, pixelData);
			LogGLError();
		}

		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		LogGLError();
	}

	glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
}

@end
