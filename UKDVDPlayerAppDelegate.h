//
//  UKDVDPlayerAppDelegate.h
//  MovieTheatre
//
//  Created by Uli Kusterer on 12.06.05.
//  Copyright 2005 M. Uli Kusterer. All rights reserved.
//

// -----------------------------------------------------------------------------
//  Headers:
// -----------------------------------------------------------------------------

#import <Cocoa/Cocoa.h>
#import "UKFilePathView.h"


// -----------------------------------------------------------------------------
//  Forward declarations:
// -----------------------------------------------------------------------------

@class  UKDVDPlayerView;


// -----------------------------------------------------------------------------
//  Class Declaration:
//      Application Delegate.
// -----------------------------------------------------------------------------

@interface UKDVDPlayerAppDelegate : NSObject
{
    IBOutlet UKFilePathView*    filePathView;       // Path of the DVD to play.
    IBOutlet UKDVDPlayerView*   playerView;         // The view where we'll be playing the DVD.
}

-(void) toggleKeepWindowFrontmost: (id)sender;
-(void) setWindowSize: (id)sender;

@end
