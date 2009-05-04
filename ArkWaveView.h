////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Arkonnekt AppKit, Cocoa classes for audio programming. 
// Copyright (C) 2005 Jeremy Jurksztowicz
//
// This library is free software; you can redistribute it and/or modify it under the terms of the 
// GNU Lesser General Public License as published by the Free Software Foundation; either version 
// 2.1 of the License, or (at your option) any later version. This library is distributed in the 
// hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License 
// for more details. 
//
// You should have received a copy of the GNU Lesser General Public License along with this library; 
// if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 
// 02111-1307 USA
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

#import <Cocoa/Cocoa.h>

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Supporting structs, protocols, categories, functions, enums
//
struct ArkWaveViewCore;
@class ArkLinePrefs;

typedef int ArkWaveSampleFormat;
enum { ArkWaveSampleFormat_32BitFloat, ArkWaveSampleFormat_16BitShort };

typedef int ArkWaveChannel;
enum { ArkWaveChannel_Left, ArkWaveChannel_Right, 
	   ArkWaveChannel_Mono, ArkWaveChannel_Stereo, ArkWaveChannel_All };
						   
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Wave Data. Contains data requested from a data source.
//
#ifndef ARK_MAX_CHANNELS
#define ARK_MAX_CHANNELS 2
#endif
typedef struct ArkWaveData_struct
{
	void *				buffers[ARK_MAX_CHANNELS];
	unsigned int		bufferCount;
	unsigned int		frameCount;
	int					sampleFormat;
} ArkWaveData;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// A wave region. Used by delegate, data source and some of the interface to ArkWaveView
//
typedef struct ArkWaveRegion_struct 
{
	int channel;
	int begin;
	int length;
} ArkWaveRegion;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// The wave data source object protocol
//
@protocol ArkWaveDataSource

- (int)	waveFrameCountForObject:(id)owner;

- (int) waveChannelCountForObject:(id)owner;

- (BOOL) lockWaveForObject:(id)				owner		// The object which is requesting data.
				 selection:(ArkWaveRegion)	reg			// The region of data requested
				  waveData:(ArkWaveData*)	outData;
		  
- (void) unlockWaveForObject:(id)owner selection:(ArkWaveRegion)reg;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// The wave view delegate handles "optional" support
//
@class ArkWaveView;

@interface NSObject(ArkWaveViewDelegate)

- (BOOL) waveView:(ArkWaveView*)wView selectedRegion:(ArkWaveRegion)reg;

- (BOOL) waveViewCutSelection:(ArkWaveView*)wView;

- (BOOL) waveViewCopiedSelection:(ArkWaveView*)wView;

- (BOOL) waveViewDeletedSelection:(ArkWaveView*)wView;

- (BOOL) waveView:(ArkWaveView*)wView openWave:(id)sender;

- (BOOL) waveViewCloseWave:(ArkWaveView*)wView;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// ArkWaveView
//
@interface ArkWaveView : NSView
{
	// C++ Core object.
	struct ArkWaveViewCore * core;
	id delegate;
		
	// General prefs.
	NSColor * backgroundColor;
	NSColor * waveColor;
	
	ArkLinePrefs * channelSepPrefs;
	ArkLinePrefs * channelCenterPrefs;
	ArkLinePrefs * playCursorPrefs;
	
	//ArkWaveRegion selRegion;
	//float startX, endX, lastStartX, lastEndX;
	
	NSLock *	cursorLock;
	unsigned	playCursor;
	BOOL		smoothWave;
	float		ampMod;
	
	// Performance data
	BOOL	useCache;
	BOOL	shouldAntialias;
	BOOL	isOpaque;
	
	// Image caching / faster and more memory hungry than minmax caching.
	NSImage *	imageCache;
	NSSize		imageCacheThreshold;
	BOOL		useImageCache;		// Use the created cache
	BOOL		drawIntoImageCache;	// Inits the cache drawing
	BOOL		createImageCache;	// Inits the creation process
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Class method interface
//
+ (BOOL) drawSampleBuffers:(void**)		buffs 
		  withChannelCount:(int)		chans 
				frameCount:(int)		frms
			  sampleFormat:(ArkWaveSampleFormat)fmt 
					inRect:(NSRect)		rect 
		   foregroundColor:(NSColor*)	fcol 
		   backgroundColor:(NSColor*)	bcol;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Actions
//
- (IBAction) open:(id)sender;

- (IBAction) close:(id)sender;

- (IBAction) cut:(id)sender;

- (IBAction) copy:(id)sender;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// General interface
//
- (ArkLinePrefs*)	channelSeparatorPrefs;

- (ArkLinePrefs*)	channelCenterPrefs;

- (NSColor*)		backgroundColor;

- (void)			setBackgroundColor:(NSColor*)color;

- (NSColor*)		waveColor;

- (void)			setWaveColor:(NSColor*)color;

- (BOOL)			smoothWave;

- (void)			setSmoothWave:(BOOL)doSmooth;

- (float)			waveAmplitudeMod;

- (void)			setWaveAmplitudeMod:(float)mod;

- (unsigned)		playCursor;

- (void)			setPlayCursor:(unsigned)pc;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

- (void) updateFromX:(unsigned int)begin toX:(unsigned int)end;

- (void) updateFromX:(unsigned int)begin toX:(unsigned int)end inChannel:(int)chan;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Performance/Caching interface
//
- (BOOL)		useCache;

- (void)		setUseCache:(BOOL)useIt;

- (BOOL)		drawsWaveWithAntialiasing;

- (void)		setDrawsWaveWithAntialiasing:(BOOL)anti;

- (BOOL)		useImageCache;

- (void)		setUseImageCache:(BOOL)useIt;

- (NSSize)		imageCacheThreshold;

- (void)		setImageCacheThreshold:(NSSize)threshold;

- (NSImage*)	imageCache;

- (void)		createImageCacheWithSize:(NSSize)size;

- (void)		destroyImageCache;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Data Source/Delegate
//
- (id<ArkWaveDataSource>) dataSource;

- (void) setDataSource:(id<ArkWaveDataSource>)src;

- (id)		delegate;

- (void)	setDelegate:(id)sender;

- (void)	reloadData;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Diagnostics/Debugging
//
- (void) printGeneralInfo;

@end