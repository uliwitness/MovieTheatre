//
//  main.m
//  MovieTheatre
//
//  Created by Uli Kusterer on 12.06.05.
//  Copyright M. Uli Kusterer 2005. All rights reserved.
//

// -----------------------------------------------------------------------------
//  Headers:
// -----------------------------------------------------------------------------

#import <Cocoa/Cocoa.h>
#import "UKCustomWindowFrame.h"


// -----------------------------------------------------------------------------
//  main:
//      Main entry point. Take care of installing our window pattern override
//      before any other applications get instantiated.
// -----------------------------------------------------------------------------

int main(int argc, char *argv[])
{
    NSAutoreleasePool*  pool = [[NSAutoreleasePool alloc] init];
    [UKCustomWindowFrame installCustomWindowFrame];
    [UKCustomWindowFrame setCustomWindowColor: [NSColor colorWithPatternImage: [NSImage imageNamed: @"tv_background"]]];
    [pool release];
    
    return NSApplicationMain(argc,  (const char **) argv);
}
