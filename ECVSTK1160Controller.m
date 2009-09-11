/* Copyright (c) 2009, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * The names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY BEN TRASK ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL BEN TRASK BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "ECVSTK1160Controller.h"

// Other Sources
#import "ECVDebug.h"

enum {
	ECVHighFieldFlag = 1 << 6,
	ECVNewImageFlag = 1 << 7
};

static NSString *const ECVSTK1160VideoSourceKey = @"ECVSTK1160VideoSource";
static NSString *const ECVSTK1160VideoFormatKey = @"ECVSTK1160VideoFormat";

@implementation ECVSTK1160Controller

#pragma mark +NSObject

- (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite1Input], ECVSTK1160VideoSourceKey,
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Auto60HzFormat], ECVSTK1160VideoFormatKey,
		nil]];
}

#pragma mark -ECVCaptureController

- (id)initWithDevice:(io_service_t)device error:(out NSError **)outError
{
	if((self = [super initWithDevice:device error:outError])) {
		NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];
		self.videoSourceObject = [d objectForKey:ECVSTK1160VideoSourceKey];
		self.videoFormatObject = [d objectForKey:ECVSTK1160VideoFormatKey];
		self.brightness = [[d objectForKey:ECVBrightnessKey] doubleValue];
		self.contrast = [[d objectForKey:ECVContrastKey] doubleValue];
		self.hue = [[d objectForKey:ECVHueKey] doubleValue];
		self.saturation = [[d objectForKey:ECVSaturationKey] doubleValue];
	}
	return self;
}
@synthesize videoSource = _videoSource;
- (void)setVideoSoruce:(ECVSTK1160VideoSource)source
{
	_videoSource = source;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithUnsignedInteger:source] forKey:ECVSTK1160VideoSourceKey];
}
- (BOOL)SVideo
{
	return ECVSTK1160SVideoInput == self.videoSource;
}
@synthesize videoFormat = _videoFormat;
- (void)setVideoFormat:(ECVSTK1160VideoFormat)format
{
	_videoFormat = format;
	resolution = self.is60HzFormat ? STK11XX_720x480 : STK11XX_720x576;
	[self noteVideoSettingDidChange];
	self.windowContentSize = self.outputSize;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithUnsignedInteger:format] forKey:ECVSTK1160VideoFormatKey];
}
- (BOOL)is60HzFormat
{
	switch(self.videoFormat) {
		case ECVSTK1160Auto60HzFormat:
		case ECVSTK1160PAL60Format:
		case ECVSTK1160PALMFormat:
		case ECVSTK1160NTSC44360HzFormat:
			return YES;
		case ECVSTK1160Auto50HzFormat:
		case ECVSTK1160PALNFormat:
		case ECVSTK1160NTSCNFormat:
		case ECVSTK1160NTSC44350HzFormat:
			return NO;
		default:
			ECVAssertNotReached(@"Invalid video format.");
			return NO;
	}
}

#pragma mark -ECVCaptureController(ECVAbstract)

- (BOOL)requiresHighSpeed
{
	return YES;
}
- (NSSize)captureSize
{
	return NSMakeSize(stk11xx_image_sizes[resolution].x, stk11xx_image_sizes[resolution].y);
}
- (NSUInteger)simultaneousTransfers
{
	return 2;
}
- (NSUInteger)microframesPerTransfer
{
	return 512;
}
- (UInt8)isochReadingPipe
{
	return 2;
}

#pragma mark -

- (BOOL)threaded_play
{
	dev_stk0408_initialize_device(self);
	dev_stk0408_init_camera(self);
	dev_stk11xx_camera_on(self);
	dev_stk0408_start_stream(self);
	return YES;
}
- (BOOL)threaded_pause
{
	dev_stk0408_stop_stream(self);
	dev_stk11xx_camera_off(self);
	dev_stk0408_camera_asleep(self);
	return YES;
}
- (BOOL)threaded_watchdog
{
	SInt32 value;
	if(![self readValue:&value atIndex:0x0001]) return NO;
	return 0x0003 == value;
}
- (void)threaded_readFrame:(IOUSBLowLatencyIsocFrame *)frame bytes:(UInt8 const *)bytes
{
	size_t const length = (size_t)frame->frActCount;
	if(!length) return;
	size_t skip = 4;
	if(ECVNewImageFlag & bytes[0]) {
		[self threaded_startNewImageWithFieldType:ECVHighFieldFlag & bytes[0] ? ECVHighField : ECVLowField absoluteTime:frame->frTimeStamp];
		skip = 8;
	}
	if(length > skip) [self threaded_readImageBytes:bytes + skip length:length - skip];
}

#pragma mark -<ECVCaptureControllerConfiguring>

- (NSArray *)allVideoSourceObjects
{
	return [NSArray arrayWithObjects:
		[NSNumber numberWithUnsignedInteger:ECVSTK1160SVideoInput],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite1Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite2Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite3Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite4Input],
		nil];
}
- (NSString *)localizedStringForVideoSourceObject:(id)obj
{
	switch([obj unsignedIntegerValue]) {
		case ECVSTK1160SVideoInput: return NSLocalizedString(@"S-Video", nil);
		case ECVSTK1160Composite1Input: return NSLocalizedString(@"Composite 1", nil);
		case ECVSTK1160Composite2Input: return NSLocalizedString(@"Composite 2", nil);
		case ECVSTK1160Composite3Input: return NSLocalizedString(@"Composite 3", nil);
		case ECVSTK1160Composite4Input: return NSLocalizedString(@"Composite 4", nil);
	}
	return nil;
}
- (id)videoSourceObject
{
	return [NSNumber numberWithUnsignedInteger:self.videoSource];
}
- (void)setVideoSourceObject:(id)obj
{
	self.videoSource = [obj unsignedIntegerValue];
}

#pragma mark -

- (NSArray *)allVideoFormatObjects
{
	return [NSArray arrayWithObjects:
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Auto60HzFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Auto50HzFormat],
		[NSNull null],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160PAL60Format],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160PALMFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160PALNFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSCNFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSC44360HzFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSC44350HzFormat],
		nil];
}
- (NSString *)localizedStringForVideoFormatObject:(id)obj
{
	switch([obj unsignedIntegerValue]) {
		case ECVSTK1160Auto60HzFormat   : return NSLocalizedString(@"Auto-detect (60Hz)", nil);
		case ECVSTK1160Auto50HzFormat   : return NSLocalizedString(@"Auto-detect (50Hz)", nil);
		case ECVSTK1160PAL60Format      : return NSLocalizedString(@"PAL-60Hz", nil);
		case ECVSTK1160PALMFormat       : return NSLocalizedString(@"PAL-M", nil);
		case ECVSTK1160PALNFormat       : return NSLocalizedString(@"PAL-N", nil);
		case ECVSTK1160NTSCNFormat      : return NSLocalizedString(@"NTSC-N", nil);
		case ECVSTK1160NTSC44360HzFormat: return NSLocalizedString(@"NTSC 4.43 (60Hz)", nil);
		case ECVSTK1160NTSC44350HzFormat: return NSLocalizedString(@"NTSC 4.43 (50Hz)", nil);
		default: return nil;
	}
}
- (id)videoFormatObject
{
	return [NSNumber numberWithUnsignedInteger:self.videoFormat];
}
- (void)setVideoFormatObject:(id)obj
{
	self.videoFormat = [obj unsignedIntegerValue];
}

#pragma mark -

- (CGFloat)brightness
{
	return _brightness;
}
- (void)setBrightness:(CGFloat)val
{
	_brightness = val;
	if(self.playing) dev_stk0408_set_brightness(self, val);
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVBrightnessKey];
}
- (CGFloat)contrast
{
	return _contrast;
}
- (void)setContrast:(CGFloat)val
{
	_contrast = val;
	if(self.playing) dev_stk0408_set_contrast(self, val);
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVContrastKey];
}
- (CGFloat)saturation
{
	return _saturation;
}
- (void)setSaturation:(CGFloat)val
{
	_saturation = val;
	if(self.playing) dev_stk0408_set_saturation(self, val);
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVSaturationKey];
}
- (CGFloat)hue
{
	return _hue;
}
- (void)setHue:(CGFloat)val
{
	_hue = val;
	if(self.playing) dev_stk0408_set_hue(self, val);
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVHueKey];
}

@end
