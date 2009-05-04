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

#import "ArkLinePrefs.h"

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Init, copy and destroy
//
@implementation ArkLinePrefs

- (id) init
{
	if(self = [super init]) {
		drawLine	= YES;
		width		= 2.0;
		isDashed	= NO;
		dash		= 0;
		dashLength	= 0;
		color		= [[NSColor blackColor] retain];
		
		notifyDelegate = NO;
	}
	return self;
}

- (void) dealloc
{
	if(dash) free(dash);
	[color release];
	[super dealloc];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Accessors
//
- (id) delegate
{
	return del;
}

- (void) setDelegate:(id)newDel
{
	if(newDel != del) {
		del = newDel;
		if(del == nil || [del respondsToSelector:@selector(linePrefsDidChange:)] == NO) {
			notifyDelegate = NO;
			NSLog(@"ArkLinePrefs delegate does not respond to selector, or is nil.");
		}
		else notifyDelegate = YES;
	}
}

- (BOOL) drawLine
{
	return drawLine;
}

- (void) setDrawLine:(BOOL)draw
{
	if(draw != drawLine) {
		drawLine = draw;
		
		if(notifyDelegate)
			[del linePrefsDidChange:self];
	}
}

- (float) width
{
	return width;
}

- (void) setWidth:(float)newWidth
{
	if(newWidth != width) {
		width = newWidth;
		
		if(notifyDelegate)
			[del linePrefsDidChange:self];
	}	
}

- (BOOL) isDashed
{
	return isDashed;
}

- (BOOL) getDash:(float**)dashPtr count:(int*)len
{
	if(dashPtr && len) 
	{
		if(*dashPtr == NULL) {
			*dashPtr = dash;
			*len = dashLength;
			return YES;
		}
		else if(*len >= dashLength) {
			int l = dashLength;
			while(l--) (*dashPtr)[l] = dash[l];
			*len = dashLength;
			return YES;
		}
	}
	// The user only wants the length of dash
	else if(len)
	{
		*len = dashLength;
		return YES;
	}
	return NO;
}

- (void) setDash:(float*)newDash count:(int)len
{
	if(dash) {
		free(dash);
		dash = 0;
		dashLength = 0;
	}
	if(newDash && len) {
		dash = malloc(len*sizeof(float));
		dashLength = len;
		while(len) { 
			len -= 1;
			dash[len] = newDash[len];
		}
		isDashed = YES;
	}
	else isDashed = NO;
	
	if(notifyDelegate)
		[del linePrefsDidChange:self];
}

- (NSColor*) color
{
	return color;
}

- (void) setColor:(NSColor*)newColor
{
	if(newColor != color) {
		[color autorelease];
		color = [newColor retain];
		
		if(notifyDelegate)
			[del linePrefsDidChange:self];
	}
}

@end