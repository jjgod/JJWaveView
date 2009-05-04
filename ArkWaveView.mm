// vim:ft=objcpp
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

// Cocoa Includes
#import "ArkWaveView.h"
#import "ArkLinePrefs.h"

// Project C++ Includes
#include "Utility.h"

// Standard library Includes
#include <list>
#include <vector>
#include <iostream>
#include <sstream>
#include <algorithm>
#include <functional>
#include <stdexcept>

// Boost Includes
#include <boost/shared_ptr.hpp>
#include <boost/function.hpp>
#include <boost/bind.hpp>
#include <boost/thread.hpp>
#include <boost/thread/mutex.hpp>

void nothing ( ) { } // For null boost::functions

using namespace ark;
using namespace std;
using namespace boost;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
inline ArkWaveRegion ArkMakeWaveRegion(int b, int l, int chans)
{
    ArkWaveRegion ret;
    ret.begin = b;
    ret.length = l;
    ret.channel = chans;
    return ret;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Cache atom and representation
//
struct MinMax {
    MinMax( ): min(numeric_limits<float>::max()), max(numeric_limits<float>::min()) { }
    MinMax(float n, float x): min(n), max(x) { }
    float min;
    float max;
};
typedef vector<MinMax>  MinMaxVec;
typedef MinMaxVec       Cache;
typedef Cache*          CachePtr;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Core C++ Class
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
struct ArkWaveViewCore
{
private:
    // This stores the actual cached data.
    MinMaxVec       _minmax[ARK_MAX_CHANNELS];
    unsigned int    _maxLength;
    unsigned int    _length;

    // This keeps track of what is and is not cached. It is kept in a sorted vector.
    struct CachedRange {
        CachedRange(unsigned int f, unsigned int l): first(f), last(l) { }
        unsigned int first;
        unsigned int last;

        inline int  length      ( ) const                       { return last - first; }
        inline bool operator <  (CachedRange const& r) const    { return first < r.first; }
        inline bool operator <  (unsigned int s) const          { return first < s; }
    };
    typedef list<CachedRange> RangeList;
    RangeList _cachedRanges;

    // The object with which the user data source communicates, which separates C++ imp from cocoa coders.
    ArkWaveView *           _clientView;
    id<ArkWaveDataSource>   _dataSource;

    // Implementation details.
    void cacheRegion_imp (unsigned int beginX, unsigned int endX);
    void reloadData_imp  ( );

public:

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Construction
//
    ArkWaveViewCore (ArkWaveView* client);

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// readyCacheWithLength
///     Prepares a cache with the desired length. If such a cache is already prepared, returns
///     immediately.
/// @param length The length of the cache to prepare
/// @return True if a cache was prepared
///
    bool readyCacheWithLength (const unsigned length);

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// cache
///     Returns the cache representation with the specified length for the specified channel, if it
///     exists. Otherwise throws a runtime_error.
/// @param channel The channel to get a cache for
/// @param length The length of the cache to get
/// @return A reference to the cache representation
///
    Cache& cache (const unsigned int channel, const unsigned int length);

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// cacheLength
/// @return The length of the currently prepared cache
///
    unsigned int cacheLength ( ) const;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// cacheRegion
///     Caches the region delimited by beginX and endX using the currently installed data source.
///     Skips currently cached data for speedup.
/// @param beginX The beginning of the region to cache
/// @param endX The end of the region to cache
///
    void cacheRegion (unsigned int beginX, unsigned int endX);

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// reloadData
///     Rereads the pertinant data from the data source and prepares the cache buffer. After this is
///     called the cache is empty.
///
    void reloadData ( );

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// channelCount
/// @return The number of channels the data source provides
///
    inline unsigned int channelCount ( ) const
    { return [_dataSource waveChannelCountForObject:_clientView]; }

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// frameCount
/// @return The number of frames the data source provides
///
    inline unsigned int frameCount ( ) const
    { return [_dataSource waveFrameCountForObject:_clientView]; }

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// dataSource
/// @return The data source for this core
///
    inline id<ArkWaveDataSource> dataSource ( ) { return _dataSource; }

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// setDataSource
///     Sets the data source for this core, and if it is different from the old one, calls
///     the reloadData() function.
/// @param src The new data source for this core
/// @see reloadData()
///
    inline void setDataSource (id<ArkWaveDataSource> src)
    {
        if (src != _dataSource) {
            _dataSource = src;
            reloadData();
        }
    }

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// printRangeInfo
///     Prints the currently cached ranges to cout.
///
    inline void printRangeInfo ( ) const
    {
        for(RangeList::const_iterator i = _cachedRanges.begin(); i != _cachedRanges.end(); i++)
            cout << "Range (" << i->first << ", " << i->last << ")\n";
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// ArkWaveViewCore implementation
//
ArkWaveViewCore::ArkWaveViewCore (ArkWaveView * client):
    _clientView(client)
{
    assert(client);

    _dataSource = nil;
    _maxLength  = 0;
    _length     = 0;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Prepares a cache with desired length
//
bool ArkWaveViewCore::readyCacheWithLength(const unsigned length)
{
    // DEBUG
    // cout << "Readying cache with length " << length << ".\n";

    if (_length != length && length <= _maxLength)
    {
        _length = length;
        _cachedRanges.clear();
    }
    return length <= _maxLength;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
Cache& ArkWaveViewCore::cache(const unsigned int channel, const unsigned int length)
{
    if (length == _length && channel < this->channelCount())
        return _minmax[channel];

    stringstream msg;
    msg << "No cache with length " << length
        << " exists for channel "  << channel << " : " << SOURCE_LOC << endl;
    throw logic_error(msg.str());
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
unsigned int ArkWaveViewCore::cacheLength ( ) const
{
    return _length;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
void ArkWaveViewCore::cacheRegion (unsigned int beginX, unsigned int endX)
{
    this->cacheRegion_imp(beginX, endX);
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
void ArkWaveViewCore::cacheRegion_imp(unsigned int beginX, unsigned int endX)
{
    // Get important data first.
    const unsigned int frameCount = [_dataSource waveFrameCountForObject:_clientView];

    const float  clientViewWidth = NSWidth([_clientView frame]);
    const double samplesPerPixel = static_cast<float>(frameCount)/clientViewWidth;

    // Lets check what we have previously cached, and adjust our request to avoid recaches.
    RangeList::iterator closest = lower_bound(_cachedRanges.begin(), _cachedRanges.end(), beginX);
    if (closest != _cachedRanges.end())
    {
        // The end of this region overlaps the beginning of the next. Adjust and continue.
        if (closest->first < endX)
            endX = closest->first;
    }
    if (closest != _cachedRanges.begin() && !_cachedRanges.empty())
    {
        closest--;

        // The beginning of this region overlaps the end of the last.
        if (beginX < closest->last)
           beginX = closest->last;
    }
    // Now that we have adjusted our values, lets make sure that we still have anything to cache!
    if (beginX >= endX) return;

// DEBUG:
////////////////////////////////////////////////////////////////////////////////////////////////////
//
    cout << "Caching pixel " << beginX << " to pixel " << endX << ".\n";
//
////////////////////////////////////////////////////////////////////////////////////////////////////

    const unsigned int firstSample = static_cast<unsigned int>(beginX * samplesPerPixel);
    const unsigned int  lastSample = MIN(static_cast<unsigned int>(endX*samplesPerPixel), frameCount);

    // Now that we know which samples we need, we should lock that region of sound data.
    ArkWaveRegion reg = ArkMakeWaveRegion(firstSample, lastSample-firstSample, ArkWaveChannel_All);
    ArkWaveData waveData;

    if ([_dataSource lockWaveForObject:_clientView
                            selection:reg
                             waveData:&waveData])
    {
        // This float counter will keep track of whether or not we should add a sample to the
        // rastererizer in order to keep the wave drawing proportional.
              double intPart                    = 0;
              float  totalIncrease              = beginX * samplesPerPixel;
        const float  samplesPerPixelFraction    = modf(samplesPerPixel,&intPart);
              float  collectedSampleFractions   = modf(totalIncrease,  &intPart);

              unsigned int    N = beginX;
        const unsigned int endN = endX;

        ////////////////////////////////////////////////////////////
        // MONO cache
        ////////////////////////////////////////////////////////////

        if (waveData.bufferCount == 1)
        {
            // NOTE: I know this is horrible, but it is the price I pay for having generic type compatibility with
            // Objective-C.
            const float * i               = reinterpret_cast<float**>(waveData.buffers)[0];
            const float * iend            = reinterpret_cast<float**>(waveData.buffers)[0] + static_cast<unsigned int>(samplesPerPixel);
            const float * const bufferEnd = reinterpret_cast<float**>(waveData.buffers)[0] + waveData.frameCount;

            while(N <= endN)
            {
                // If we have collected enough sample 'fractions' to make a whole sample, then
                // we should add one sample to our search scope.
                unsigned int sampAddition = 0;
                collectedSampleFractions += samplesPerPixelFraction;
                if (collectedSampleFractions >= 1.0)
                {
                    sampAddition = 1;
                    collectedSampleFractions = modf(collectedSampleFractions,&intPart);
                }
                iend += sampAddition;

                // Make sure we do not overwrite anything.
                if (iend > bufferEnd)
                   iend = bufferEnd;

                // Prepare the min and max with some default values.
                float greatest = numeric_limits<float>::min();
                float least    = numeric_limits<float>::max();
                if (i != iend) {
                    greatest = *i++;
                    least = greatest;
                }

                for(; i != iend; ++i)
                {
                    const float val = *i; // This const helps my compiler optimize this loop.
                    if (val > greatest  )    greatest = val;
                    else if (val < least)    least    = val;
                }
                iend += static_cast<unsigned int>(samplesPerPixel);

// boost::minmax
////////////////////////////////////////////////////////////////////////////////////////////////////
//              pair<float const*, float const*> min_max = minmax_element(i, iend);
//              i = iend;
//              iend += static_cast<unsigned int>(samplesPerPixel);
////////////////////////////////////////////////////////////////////////////////////////////////////

                MinMax& mm = _minmax[0][N];
                mm.max = greatest;
                mm.min = least;

                // Finally increment the pixel counter
                N++;
            }
        }

        ////////////////////////////////////////////////////////////
        // STEREO cache
        ////////////////////////////////////////////////////////////

        else if (waveData.bufferCount == 2)
        {
            const float * il                = reinterpret_cast<float**>(waveData.buffers)[0];
            const float * ilend             = reinterpret_cast<float**>(waveData.buffers)[0] + static_cast<unsigned int>(samplesPerPixel);
            const float * const lbufferEnd  = reinterpret_cast<float**>(waveData.buffers)[0] + waveData.frameCount;
            const float * ir                = reinterpret_cast<float**>(waveData.buffers)[1];
            const float * irend             = reinterpret_cast<float**>(waveData.buffers)[1] + static_cast<unsigned int>(samplesPerPixel);
            const float * const rbufferEnd  = reinterpret_cast<float**>(waveData.buffers)[1] + waveData.frameCount;

            while(N <= endN)
            {
                // If we have collected enough sample 'fractions' to make a whole sample, then
                // we should add one sample to our search scope.
                unsigned int sampAddition = 0;
                collectedSampleFractions += samplesPerPixelFraction;
                if (collectedSampleFractions >= 1.0)
                {
                    sampAddition = 1;
                    collectedSampleFractions = modf(collectedSampleFractions,&intPart);
                }
                ilend += sampAddition;
                irend += sampAddition;

                // Make sure we do not overwrite anything.
                if (ilend > lbufferEnd) ilend = lbufferEnd;
                if (irend > rbufferEnd) irend = rbufferEnd;

                // Prepare with default values.
                float lgreatest = numeric_limits<float>::min();
                float lleast    = numeric_limits<float>::max();
                float rgreatest = numeric_limits<float>::min();
                float rleast    = numeric_limits<float>::max();
                if (il != ilend && ir != irend) {
                    lgreatest = *il++;
                    lleast = lgreatest;
                    rgreatest = *ir++;
                    rleast = rgreatest;
                }

                for(; il != ilend; ++il)
                {
                    const float val = *il; // This const helps my compiler optimize this loop.
                    if (val > lgreatest  )   lgreatest = val;
                    else if (val < lleast)   lleast    = val;
                }
                ilend += static_cast<unsigned int>(samplesPerPixel);

                for(; ir != irend; ++ir)
                {
                    const float val = *ir;
                    if (val > rgreatest  )   rgreatest = val;
                    else if (val < rleast)   rleast    = val;
                }
                irend += static_cast<unsigned int>(samplesPerPixel);

// boost::minmax
////////////////////////////////////////////////////////////////////////////////////////////////////
//              pair<float const*,float const*> min_max_left = minmax_element(il, ilend);
//              il = ilend;
//              ilend += static_cast<unsigned int>(samplesPerPixel);
//
//              pair<float const*,float const*> min_max_right = minmax_element(ir, irend);
//              ir = irend;
//              irend += static_cast<unsigned int>(samplesPerPixel);
////////////////////////////////////////////////////////////////////////////////////////////////////

                MinMax& lmm = _minmax[0][N];
                lmm.max = lgreatest;
                lmm.min = lleast;

                MinMax& rmm = _minmax[1][N];
                rmm.max = rgreatest;
                rmm.min = rleast;

                // Finally increment the pixel counter
                N++;
            }
        }

        // Unconditionally unlock locked data.
        [_dataSource unlockWaveForObject:_clientView selection:reg];
    }
    else {
        stringstream msg;
        msg << "Failed to lock wave region for reading : ("
            << reg.begin << "," << reg.begin + reg.length << "] :" << SOURCE_LOC;
        throw runtime_error(msg.str());
    }

    // Now that we have built the cached section, we can note it down.
    closest = lower_bound(_cachedRanges.begin(), _cachedRanges.end(), beginX);
    closest = _cachedRanges.insert(closest, CachedRange(beginX, endX));

    // And finally make sure that the list of cached ranges makes sense.
    RangeList::iterator last, temp;
    for(RangeList::iterator j = _cachedRanges.begin(); j != _cachedRanges.end(); j++)
    {
        // We calculate first once in the foor loop statement
        if (j == _cachedRanges.begin()) {
            // If this is the first one, it cannot be overlapping its non existant predecessor.
            last = j;
        }
        else if (j->first <= last->last)
        {
            if (j->last <= last->last) {
                // Remove this entry as it is completely contained.
                temp = j;
                --temp;
                _cachedRanges.erase(j);
                j = temp;
            }
            else {
                // we can merge these two ranges, and remove this one.
                last->last = j->last;
                temp = j; --temp;
                _cachedRanges.erase(j);
                j = temp;
            }
        }
        // No overlapping here, so we just update the temp iter.
        else last = j;
    }
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
void ArkWaveViewCore::reloadData ( )
{
    this->reloadData_imp();
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
void ArkWaveViewCore::reloadData_imp ( )
{
    const unsigned frameCount   = [_dataSource   waveFrameCountForObject:_clientView];
    const unsigned channelCount = [_dataSource waveChannelCountForObject:_clientView];

    _maxLength  = frameCount; // TODO
    _length     = 0;

    MinMaxVec(_maxLength).swap(_minmax[0]);
    if (channelCount == 2)
        MinMaxVec(_maxLength).swap(_minmax[1]);

    // Reset cache data to reflect empty cache.
    _cachedRanges.clear();
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Instance Private Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
typedef unsigned int uint;
@interface ArkWaveView(Private)

// Delegate method for the ArkLinePrefs class.
- (void) linePrefsDidChange:(ArkLinePrefs*)prefs;

- (void) updateChannelSeparator;

- (void) updateChannelCenter:(ArkWaveChannel)chan;

- (void) updateFromX:(uint)begin toX:(uint)end;

- (void) updateFromX:(uint)begin toX:(uint)end inChannel:(ArkWaveChannel)chan;

- (void) drawRangeFromX:(uint)begin
                    toX:(uint)end;

- (void) drawRangeFromX:(uint)begin
                    toX:(uint)end
                channel:(uint)chan
             usingCache:(CachePtr)cachePtr
              cgContext:(CGContextRef)contextRef
                lastMin:(float*)lMin
                lastMax:(float*)lMax;

- (NSImage*) createImageCache;

@end
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Class Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Dummy data source used for when ArkWaveView wants to handle its own buffers
@interface DummyDataSource : NSObject
{
    void ** data;
    int channelCount;
    int frameCount;
    ArkWaveSampleFormat sampFmt;
}
- (id) initWithData:(void**)dat channels:(int)chan frames:(int)frms sampleFormat:(ArkWaveSampleFormat)fmt;
@end
@implementation DummyDataSource
- (id) initWithData:(void**)dat channels:(int)chan frames:(int)frms sampleFormat:(ArkWaveSampleFormat)fmt
{
    if ((self = [super init])) {
        data = dat;
        channelCount = chan;
        frameCount = frms;
        sampFmt = fmt;
    }
    return self;
}
- (int) waveFrameCountForObject:  (id)owner { return frameCount; }
- (int) waveChannelCountForObject:(id)owner { return channelCount; }
- (BOOL) lockWaveForObject:(id)             owner       // The object which is requesting data.
                 selection:(ArkWaveRegion)  reg         // The region of data requested
                  waveData:(ArkWaveData*)   outData
{
    if (!outData) return NO;

    const uint elemTypeSize = (sampFmt == (int)ArkWaveSampleFormat_32BitFloat ?
        sizeof(float) : sizeof(short));

    for(int i = 0; i != channelCount && i != ARK_MAX_CHANNELS; i++)
        outData->buffers[i] = reinterpret_cast<unsigned char*>(data[i]) + (reg.begin * elemTypeSize);

    outData->bufferCount = channelCount;
    outData->frameCount  = reg.length;
    outData->sampleFormat= sampFmt;

    return YES;
}
- (void) unlockWaveForObject:(id)owner selection:(ArkWaveRegion)reg { }

@end
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation ArkWaveView

///
/// Class method for drawing a buffer one time, in an arbitrary (predefined) context.
/// useful for generating NSImage's.
///
/// TODO: Consider creating a single static tempView instance and using it for drawing
/// repeatedly. This would save time in an application that draws a lot of buffers, but
/// would waste memory for an app that only draws once or twice.
///
+ (BOOL) drawSampleBuffers:(void**)     buffs
          withChannelCount:(int)        chans
                frameCount:(int)        frms
              sampleFormat:(ArkWaveSampleFormat)fmt
                    inRect:(NSRect)     rect
           foregroundColor:(NSColor*)   fcol
           backgroundColor:(NSColor*)   bcol;
{
    id tempDataSource = [[[DummyDataSource alloc] initWithData:buffs
        channels:chans frames:frms sampleFormat:fmt] autorelease];

    ArkWaveView * tempView = [[[ArkWaveView alloc] initWithFrame:rect] autorelease];
    [tempView setDataSource:tempDataSource];

    if (fcol) [tempView setWaveColor:fcol];
    if (bcol) [tempView setBackgroundColor:bcol];

    uint startX = (uint)(NSMinX(rect));
    uint stopX  = (uint)(NSMaxX(rect));

    try { // Prepare a suitable cache, and cache the right data in it.

        // Prepare a cache with the suitable length
        uint myWidth = (uint)(floor(NSWidth(rect)));
        tempView->core->readyCacheWithLength(myWidth);

        // Cache and draw
        tempView->core->cacheRegion(startX, stopX);
        [tempView drawRangeFromX:startX toX:stopX];

    } CATCH_AND_REPORT;

    return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Instance Construction/Destruction
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
- (id) initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        // Create a new core object, with ourself as the core client.
        try { core = new ArkWaveViewCore(self); }
        catch(...) {
            // If we fail to allocate a core, then we become useless. Time to die :(
            cerr << "Failed to create C++ core object. Aborting : " << SOURCE_LOC << endl;
            [self release];
            return nil;
        }

        // TODO: Preferences
        NSColor * blue = [NSColor colorWithCalibratedRed:0.07 green:0.45 blue:0.8 alpha:1.0];
        backgroundColor = [[NSColor whiteColor] retain];
        waveColor = [blue retain];

        channelSepPrefs     = [[ArkLinePrefs alloc] init];
        channelCenterPrefs  = [[ArkLinePrefs alloc] init];
        playCursorPrefs     = [[ArkLinePrefs alloc] init];
        playCursor = 0;
        cursorLock          = [[NSLock alloc] init];

        [channelCenterPrefs setDrawLine:NO];
        [channelSepPrefs    setDelegate:self];
        [channelCenterPrefs setDelegate:self];
        [playCursorPrefs    setDelegate:self];

        smoothWave  = YES;
        ampMod      = 1.0;

        imageCacheThreshold = NSMakeSize(512, 128);
        useImageCache       = NO;
        drawIntoImageCache  = NO;
        createImageCache    = NO;

        // Performance flags.
        useCache        = YES;
        shouldAntialias = NO;
        isOpaque        = YES;  // You can go transparent, but this speeds things up on my system.
    }
    return self;
}

- (void) dealloc
{
    [backgroundColor release];
    [waveColor       release];

    [channelSepPrefs    release];
    [channelCenterPrefs release];
    [cursorLock         release];

    delete core;

    [imageCache release];
    [super dealloc];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Action Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
- (IBAction) open:(id)sender
{
    if (delegate) {
        if ([delegate respondsToSelector:@selector(waveView:openWave:)])
            if ([delegate waveView:self openWave:sender])
                [self reloadData];
    }
}

- (IBAction) close:(id)sender
{
    if (delegate) {
        if ([delegate respondsToSelector:@selector(waveViewCloseWave:)])
            if ([delegate waveViewCloseWave:sender])
                [self reloadData];
    }
}

- (IBAction) cut:(id)sender
{
    if (delegate) {
        if ([delegate respondsToSelector:@selector(waveViewCutSelection:)])
            if ([delegate waveViewCutSelection:self])
                [self reloadData];
    }
}

- (IBAction) copy:(id)sender
{
    if (delegate) {
        if ([delegate respondsToSelector:@selector(waveViewCopiedSelection:)])
            if ([delegate waveViewCopiedSelection:sender])
                [self reloadData];
    }
}

- (IBAction) delete:(id)sender
{
    if (delegate) {
        if ([delegate respondsToSelector:@selector(waveViewDeletedSelection:)])
            if ([delegate waveViewDeletedSelection:self])
                [self reloadData];
    }
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Preference Accessor Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
- (void) linePrefsDidChange:(ArkLinePrefs*)prefs
{
    if (prefs == channelSepPrefs)
        [self updateChannelSeparator];
    else
    if (prefs == channelCenterPrefs)
        [self updateChannelCenter:ArkWaveChannel_All];
}

- (ArkLinePrefs*) channelSeparatorPrefs
{
    return channelSepPrefs;
}

- (ArkLinePrefs*) channelCenterPrefs
{
    return channelCenterPrefs;
}

- (NSColor*) backgroundColor
{
    return backgroundColor;
}

- (void) setBackgroundColor:(NSColor*)color
{
    if (backgroundColor != color) {
        [backgroundColor autorelease];
        backgroundColor = [color retain];

        [self setNeedsDisplay:YES];
    }
}

- (NSColor*) waveColor
{
    return waveColor;
}

- (void) setWaveColor:(NSColor*)color
{
    if (waveColor != color) {
        [waveColor autorelease];
        waveColor = [color retain];

        [self setNeedsDisplay:YES];
    }
}

- (BOOL) smoothWave
{
    return smoothWave;
}

- (void) setSmoothWave:(BOOL)doSmooth
{
    if (smoothWave != doSmooth) {
        smoothWave = doSmooth;
        [self setNeedsDisplay:YES];
    }
}

- (float) waveAmplitudeMod
{
    return ampMod;
}

- (void) setWaveAmplitudeMod:(float)mod
{
    if (mod != ampMod)
    {
        ampMod = mod;
        [self setNeedsDisplay:YES];
    }
}

- (unsigned) playCursor
{
    return playCursor;
}

- (void) setPlayCursor:(unsigned)pc
{
    [cursorLock lock];
    unsigned oldPC = playCursor;
    playCursor = pc;

    const float antialiasFudge = 2.0;
    const float samplesPerPixel = static_cast<float>(core->frameCount()) / NSWidth([self bounds]);
    const float oldCursorX = static_cast<float>(oldPC) / samplesPerPixel;
    const float newCursorX = static_cast<float>(playCursor) / samplesPerPixel;
    [cursorLock unlock];

    NSRect redrawR = NSMakeRect(
        MIN(oldCursorX, newCursorX) - antialiasFudge, 0,
       (MAX(oldCursorX, newCursorX) - MIN(oldCursorX, newCursorX)) + antialiasFudge,
        NSHeight([self bounds]));

    [self displayRect:redrawR];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Performance Accessor Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //

- (BOOL) useCache
{
    return useCache;
}

- (void) setUseCache:(BOOL)useIt
{
    if (useIt != useCache) {
        useCache = useIt;

        // TODO: Why is this accessor even here if it can't do anything? To motivate me to finish it!
        if (useCache == NO) {
            cerr << "Sorry! This framework is not finished yet, can only draw from Cache : "
                 << SOURCE_LOC << endl;

            useCache = YES;
        }
    }
}

- (BOOL) drawsWaveWithAntialiasing
{
    return shouldAntialias;
}

- (void) setDrawsWaveWithAntialiasing:(BOOL)anti
{
    if (anti != shouldAntialias) {
        shouldAntialias = anti;
        [self setNeedsDisplay:YES];
    }
}

- (BOOL) useImageCache
{
    return useImageCache;
}

- (void) setUseImageCache:(BOOL)useIt
{
    useImageCache = useIt;
    NSRect myBounds = [self bounds];

    if (useImageCache &&
       (NSWidth (myBounds) <= imageCacheThreshold.width && NSHeight(myBounds) <= imageCacheThreshold.height) ||
       (imageCacheThreshold.width < 1 && imageCacheThreshold.height < 1)) // cache threshold of 0/0 means always.
    {
        drawIntoImageCache  = YES;
        createImageCache    = YES;
    }
}

- (NSSize) imageCacheThreshold
{
    return imageCacheThreshold;
}

- (void) setImageCacheThreshold:(NSSize)threshold
{
    imageCacheThreshold = threshold;

    if (imageCacheThreshold.width < 1 && imageCacheThreshold.height < 1)
        useImageCache = YES;

    // This will start the cache creation process if our frame fits in the
    // new image cache threshold.
    [self setUseImageCache:[self useImageCache]];
}

- (NSImage*) imageCache
{
    return imageCache;
}

- (void) destroyImageCache
{
    [imageCache autorelease];
    imageCache = nil;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Drawing Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
- (void) drawRangeFromX:(uint)begin
                    toX:(uint)end
                channel:(uint)chan
              cgContext:(CGContextRef)contextRef
                lastMin:(float*)lMin
                lastMax:(float*)lMax
{
    unsigned int        pixel           = begin;
    const unsigned int  viewHeight      = static_cast<int>(NSHeight([self bounds]));
    float               viewMidPoint    = viewHeight/2;
    float               viewHeightRatio = viewMidPoint;

    if (core->channelCount() == 2) {
        if (chan == 0) {
            viewMidPoint    /= 2;
            viewHeightRatio /= 2;
        }
        else if (chan == 1) {
            viewMidPoint    += viewMidPoint/2;
            viewHeightRatio /= 2;
        }
    }

    float lastMin = *lMin;
    float lastMax = *lMax;

    Cache& cache = core->cache(chan, static_cast<unsigned int>(NSWidth([self frame])));
    while(pixel != end) {
        float max = cache[pixel].max;
        float min = cache[pixel].min;

        if (smoothWave) {
            if (max < lastMin) max = lastMin;
            if (min > lastMax) min = lastMax;

            lastMax = max;
            lastMin = min;
        }

        float maxPt = viewMidPoint + max*viewHeightRatio*ampMod;
        float minPt = viewMidPoint + min*viewHeightRatio*ampMod;
        if (maxPt == minPt) {
            maxPt += 0.5;
            minPt -= 0.5;
        }

        // And now draw the wave peice.
        CGContextBeginPath(contextRef);

        CGContextMoveToPoint   (contextRef,pixel, minPt);
        CGContextAddLineToPoint(contextRef,pixel, maxPt);

        CGContextClosePath (contextRef);
        CGContextStrokePath(contextRef);

        pixel++;
    }

    *lMin = lastMin;
    *lMax = lastMax;
}

- (void) drawRangeFromX:(uint)begin
                    toX:(uint)end
{
    assert(!(end < begin));

    // Get the drawing context, so we can use quartz directly, and
    // avoid some of the Cocoa overhead.
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    CGContextRef contextRef    = (CGContextRef)[context graphicsPort];
    if (shouldAntialias == NO)
        CGContextSetShouldAntialias(contextRef,false);

    // if our view width is equal to our cache size, we do not have to resize
    // the cache and we can proceed at once.
    if (static_cast<unsigned int>(NSWidth([self frame])) == core->cacheLength())
    {
        float lastMin = numeric_limits<float>::min(),
              lastMax = numeric_limits<float>::max();

        [self drawRangeFromX:begin toX:end channel:0 cgContext:contextRef
            lastMin:&lastMin lastMax:&lastMax];

        // If we have another channel, draw that too. Layout is taken care of by
        // the drawing subsystem.
        if (core->channelCount() == 2)
        {
            lastMax = numeric_limits<float>::max();
            lastMin = numeric_limits<float>::min();
            [self drawRangeFromX:begin toX:end channel:1
                cgContext:contextRef lastMin:&lastMin lastMax:&lastMax];
        }
    }
    else // We have to draw with the cache, and just round till it fits.
    {
        cerr << "Sorry, this feature not implemented yet : " << SOURCE_LOC << endl;
    }

    // This looks funny, but shouldAntialias only affects waveform anitaliasing,
    // everything else is drawn all nice and fuzzy. So if we have turned off
    // antialiasing at the beginning of theis function, we need to turn it back on.
    if (shouldAntialias == NO)
        CGContextSetShouldAntialias(contextRef,true);
}

- (void) createImageCacheWithSize:(NSSize)size
{
    NSRect oldFrame = [self frame];

    // We invoke super's setFrame because our own will make needless alterations
    // to the non-image cache.
    [super setFrame:NSMakeRect(oldFrame.origin.x, oldFrame.origin.y, size.width, size.height)];

    [imageCache release];
    imageCache = [[self createImageCache] retain];

    [super setFrame:oldFrame];
}

- (NSImage*) createImageCache
{
    // Create a cache of our current size.  BEWARE (TODO:), this means that this
    // method should only be called on small views, as sometimes views can get
    // enormous in size (due to our custom zooming).
    const NSSize size = [self frame].size;

    const NSRect rect = NSMakeRect(0,0,size.width,size.height);
    NSImage* imgCache = [[[NSImage alloc] initWithSize:size] autorelease];
    [imgCache lockFocus];

    // Draw only the wave itself, as decorators do not need to be cached.
    try {
        [self drawRangeFromX:0 toX:(unsigned int)size.width];

    } CATCH_AND_REPORT;

    // Store as a bitmap.
    NSBitmapImageRep* rep = [[[NSBitmapImageRep alloc]
        initWithFocusedViewRect:
        NSMakeRect(0,0,size.width,size.height)] autorelease];

    [imgCache unlockFocus];
    [imgCache addRepresentation:rep];

    return imgCache;
}

- (void) drawRect:(NSRect)rect
{
    // If we have no data, then erase and exit.
    if (core->frameCount() == 0) {
        // Clear to background color before we exit.
        [backgroundColor set];
        NSRectFill(rect);
        return;
    }

    // If we are caching into an image, then we create an image to hold the cache,
    // Lock focus on it.
    NSAttributedString * msg = nil;
    if (drawIntoImageCache && core->frameCount() != 0) {
        [imageCache release];
        imageCache = [[self createImageCache] retain];
        drawIntoImageCache = NO;
    }

    // Get stats for draw routines.
    int firstX = static_cast<int>(rect.origin.x);
    int width  = static_cast<int>(NSWidth(rect));

    // Clear to background color.
    [backgroundColor set];
    NSRectFill(rect);

    if (imageCache && useImageCache) {
        NSRect myBounds = [self bounds];
        NSSize imgSize  = [imageCache size];
        NSSize stretchFactor = NSMakeSize(NSWidth(myBounds)/imgSize.width, NSHeight(myBounds)/imgSize.width);

        NSRect srcRect = NSMakeRect(
            rect.origin.x/stretchFactor.width,   rect.origin.y/stretchFactor.height,
            rect.size.width/stretchFactor.width, rect.size.height/stretchFactor.height);
        [imageCache drawInRect:rect fromRect:srcRect operation:NSCompositeSourceOver fraction:1.0];

// DEBUG: Print "Image" overtop the image, so I can see when we are using the image cache
////////////////////////////////////////////////////////////////////////////////////////////////////
        NSMutableDictionary * attribs = [NSMutableDictionary dictionaryWithCapacity:2];
        [attribs setObject:[NSFont labelFontOfSize:18.0] forKey:NSFontAttributeName];
        [attribs setObject:[[NSColor blackColor] colorWithAlphaComponent:0.33]
            forKey:NSForegroundColorAttributeName];
        msg = [[[NSAttributedString alloc] initWithString:[NSString stringWithString:@"Image"]
            attributes:attribs] autorelease];
////////////////////////////////////////////////////////////////////////////////////////////////////
    }
    else { // Draw it from the cache (non-image)
        [waveColor set];

// DEBUG
////////////////////////////////////////////////////////////////////////////////////////////////////
//      cout << "Drawing wave view with bounds width " << NSWidth([self bounds])
//           << ", frame width " << NSWidth([self frame]) << ", from " << firstX
//           << " to " << firstX+width << ".\n";
////////////////////////////////////////////////////////////////////////////////////////////////////
        if (useCache)
        {
            try { // Prepare a suitable cache, and cache the right data in it.

                // Prepare a cache with the suitable length
                uint myWidth = static_cast<uint>(floor(NSWidth([self bounds])));
                core->readyCacheWithLength(myWidth);

                // Finally, do the actual caching before starting on the drawing.
                core->cacheRegion(firstX, firstX+width);

                [self drawRangeFromX:firstX
                                 toX:firstX+width];

            } CATCH_AND_REPORT;
        }
    }

    // Decorators
    if (core->channelCount() == 2)
    {
        if ([channelSepPrefs drawLine]) {
            const float channelSepY  = [self bounds].size.height/2;
            const NSPoint startPoint = NSMakePoint(firstX, channelSepY);
            const NSPoint endPoint   = NSMakePoint(firstX+width, channelSepY);

            NSBezierPath * seppath = [NSBezierPath bezierPath];

            // Customize seppath
            [seppath setLineWidth:[channelSepPrefs width]];
            if ([channelSepPrefs isDashed]) {
                float * dash = NULL;
                int size = 0;

                [channelSepPrefs getDash:&dash count:&size];
                [seppath setLineDash:dash count:size phase:0.0];
            }

            [seppath moveToPoint:startPoint];
            [seppath lineToPoint:endPoint];

            [[channelSepPrefs color] set];
            [seppath stroke];
        }
        if ([channelCenterPrefs drawLine]) {
            const float ly = NSHeight([self bounds])/4;
            const float ry = ly*3;

            NSBezierPath * chancen = [NSBezierPath bezierPath];

            [chancen setLineWidth:[channelCenterPrefs width]];
            if ([channelCenterPrefs isDashed]) {
                float * dash = NULL;
                int size = 0;

                [channelCenterPrefs getDash:&dash count:&size];
                [chancen setLineDash:dash count:size phase:0.0];
            }

            [chancen moveToPoint:NSMakePoint(firstX, ly)];
            [chancen lineToPoint:NSMakePoint(firstX+width, ly)];
            [chancen moveToPoint:NSMakePoint(firstX, ry)];
            [chancen lineToPoint:NSMakePoint(firstX+width, ry)];

            [[channelCenterPrefs color] set];
            [chancen stroke];
        }
    }
    else if (core->channelCount() == 1)
    {
        if ([channelCenterPrefs drawLine]) {
            const float y = NSHeight([self bounds])/2;

            NSBezierPath * chancen = [NSBezierPath bezierPath];

            [chancen setLineWidth:[channelCenterPrefs width]];
            if ([channelCenterPrefs isDashed]) {
                float * dash = NULL;
                int size = 0;

                [channelCenterPrefs getDash:&dash count:&size];
                [chancen setLineDash:dash count:size phase:0.0];
            }

            [chancen moveToPoint:NSMakePoint(firstX, y)];
            [chancen lineToPoint:NSMakePoint(firstX+width, y)];

            [[channelCenterPrefs color] set];
            [chancen stroke];
        }
    }

    [cursorLock lock];
    // Draw the play cursor at .5 increments, to keep a consistent look.
    float cursorX =
        static_cast<float>(playCursor) / (static_cast<float>(core->frameCount()) / NSWidth([self bounds]));
    [cursorLock unlock];

    double fractPart, intPart;
    fractPart = modf(cursorX, &intPart);
    cursorX = static_cast<float>(intPart + 0.5);
    if (cursorX >= NSMinX(rect) && cursorX <= NSMaxX(rect))
    {
        NSBezierPath * cursorPath = [NSBezierPath bezierPath];
        [cursorPath moveToPoint:NSMakePoint(cursorX, NSMinY(rect))];
        [cursorPath lineToPoint:NSMakePoint(cursorX, NSMaxY(rect))];
        [cursorPath setLineWidth:[playCursorPrefs width]];
        [[playCursorPrefs color] set];
        [cursorPath stroke];
    }

    // Finally print any text messages that have been prepared overtop the whole view
    if (msg) [msg drawAtPoint:NSMakePoint(10, 10)];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Update Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
- (void) updateChannelSeparator
{
    [self updateFromX:0 toX:static_cast<uint>(NSWidth([self bounds]))];
}

- (void) updateChannelCenter:(ArkWaveChannel)chan
{
    [self updateFromX:0 toX:static_cast<uint>(NSWidth([self bounds]))];
}

- (void) updateFromX:(uint)begin toX:(uint)end
{
    NSRect rect;
    rect.origin      = NSMakePoint(begin,0);
    rect.size.width  = end - begin;
    rect.size.height = [self bounds].size.height;

    [self setNeedsDisplayInRect:rect];
}

- (void) updateFromX:(uint)begin toX:(uint)end inChannel:(int)chan
{
    [self updateFromX:begin toX:end];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Mouse Actions
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
enum {
    ArkWaveView_SelectRegion,
    ArkWaveView_SelectRegionBegin,
    ArkWaveView_SelectRegionEnd,
    ArkWaveView_ShiftRegion
};

- (void) mouseDown:(NSEvent*)evt
{
//  const NSPoint localPt = [self convertPoint:[evt mouseLocation] fromView:nil];
//  const unsigned flags = [evt modifierFlags];
//  if (flags & NSCommandKeyFlag)
//  {
//
//  }
//  else
//  if (flags & NSAlternateKeyFlag)
//  {
//
//  }
//  else
//  if (flags & NSShiftKeyFlag)
//  {
//
//  }

//  // Before we modify the region data, we now have enough info to erase the correct portion
//  // of the view.
//  if (endX - startX > 0)
//      [self setNeedsDisplayInRect:NSMakeRect(startX, 0, endX - startX, NSHeight([self bounds]))];
//
//  const float framesPerPix = static_cast<float>(core->frameCount()) / NSWidth([self bounds]);
//  const unsigned startFrame = localPt.x * framesPerPix;
//
//  [delegate waveView:self selectedRegion:ArkMakeWaveRegion(0, 0, 0)];
//
//  mouseOp = ArkWaveView_SelectingRegion;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) mouseUp:(NSEvent*)evt
{

}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) mouseDragged:(NSEvent*)evt
{
//  const float framesPerPix = static_cast<float>(core->frameCount()) / NSWidth([self bounds]);
//  const unsigned startFrame = localPt.x * framesPerPix;
//
//  if (mouseOp == ArkWaveView_SelectingRegion)
//  {
//      const float minX = MIN(startX, localPt.x);
//      const float maxX = MAX(startX, localPt.x);
//      ArkWaveRegion reg = ArkMakeWaveRegion(minX*framesPerPixel, maxX - minX
//      [delegate waveView:self selectedRegion:ArkMakeWaveRegion(0, 0, 0)];
//  }
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Base Overrides
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
- (void) setFrame:(NSRect)frame
{
    cout << "Changing frame width to " << NSWidth(frame) << ".\n";

    // If the size of the wave view is larger than the number of samples in our data source,
    // then we have to shrink it down. Don't bother if we don't have any data yet.
    if (static_cast<uint>(frame.size.width) > core->frameCount() && core->frameCount()) {
        cout << "Cannot set frame to size bigger than wave sample count : " << SOURCE_LOC << endl;
        frame.size.width = core->frameCount();
    }

    NSRect old = [self frame];
    [super setFrame:frame];

    // We only need to proceed if the width has changed.
    if (NSWidth(old) == NSWidth([self frame]))
        return;

    // First check to see if we should be using an image cache.
    if (useImageCache) {

        // If we should be, check the new size against our image cache threshold.
        if ((NSWidth (frame) <= imageCacheThreshold.width   &&
            NSHeight(frame) <= imageCacheThreshold.height) ||
           (imageCacheThreshold.width < 1 && imageCacheThreshold.height < 1))
        {
            [imageCache release];
             imageCache = nil;

            // This flag tells the draw system to render into an image on the next drawRect pass.
            // OPTION: Maybe put the cache rendering into another thread, rather than drawing it
            // on our next pass.
            drawIntoImageCache = YES;
        }
    }

    // Otherwise ready a cache of suitable length.
    core->readyCacheWithLength(static_cast<unsigned>(NSWidth(frame)));
}

- (BOOL) isOpaque
{
    return isOpaque;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Data Source and Delegate Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
- (id<ArkWaveDataSource>) dataSource
{
    return core->dataSource();
}

- (void) setDataSource:(id<ArkWaveDataSource>)src
{
    if (src != core->dataSource()) {
        core->setDataSource(src);
        [self reloadData];
    }
}

- (id) delegate
{
    return delegate;
}

- (void) setDelegate:(id)sender
{
    delegate = sender;
}

- (void) reloadData
{
    core->reloadData();

    [imageCache release];
    imageCache = nil;
    if (useImageCache)
    {
        NSRect frame = [self frame];
        if ((NSWidth(frame) <= imageCacheThreshold.width &&
             NSHeight(frame) <= imageCacheThreshold.height) ||
            (imageCacheThreshold.width < 1 && imageCacheThreshold.height < 1))
        {
            drawIntoImageCache = YES;
        }
    }

    [self setNeedsDisplay:YES];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
//          Diagnostic Methods
// 01 //
// 02 //
// 03 //
// 04 //
// 05 //
// 06 //
// 07 //
// 08 //
// 09 //
// 10 //
- (void) printGeneralInfo
{
    try
    {
        NSRect vis = [self visibleRect];

        cout
        << "ArkWaveView info\n"
        << "===========================\n"
        << "Cocoa Class:     "  << [self className] << endl
        << "View width:      "  << NSWidth([self bounds]) << endl
        << "Image cache:     "  << (imageCache != nil) << endl
        << "Use image cache: "  << useImageCache << endl
        << "Visible range:   (" << NSMinX(vis) << "," << NSMaxX(vis) << ")" << endl
        << "Cache length:    "  << core->cacheLength() << endl
        << "Cached ranges:   "  << endl;
        core->printRangeInfo();

    } CATCH_AND_REPORT;
}

@end
