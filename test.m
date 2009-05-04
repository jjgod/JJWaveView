/* test.m */

#include <Cocoa/Cocoa.h>
#include "ArkWaveView.h"

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    ArkWaveView *view = [[ArkWaveView alloc] initWithFrame: NSMakeRect(0, 0, 200, 50)];

    [view release];
    [pool release];
    return 0;
}

