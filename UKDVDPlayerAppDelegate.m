//
//  UKDVDPlayerAppDelegate.m
//  MovieTheatre
//
//  Created by Uli Kusterer on 12.06.05.
//  Copyright 2005 M. Uli Kusterer. All rights reserved.
//

// -----------------------------------------------------------------------------
//  Headers:
// -----------------------------------------------------------------------------

#import "UKDVDPlayerAppDelegate.h"
#import "UKDVDPlayerView.h"
#import "NSWorkspace+TypeOfVolumeAtPath.h"
#import "NSView+SizeWindowForViewSize.h"


@implementation UKDVDPlayerAppDelegate

// -----------------------------------------------------------------------------
//  * CONSTRUCTOR
//      Pretty pointless right now.
// -----------------------------------------------------------------------------

-(id)   init
{
    if( (self = [super init]) )
    {
        
    }
    
    return self;
}


// -----------------------------------------------------------------------------
//  awakeFromNib
//      Set up the path display control to allow choosing VIDEO_TS etc.
// -----------------------------------------------------------------------------

-(void) awakeFromNib
{
    [filePathView setAction: @selector(takePathFrom:)];
    [filePathView setCanChooseFiles: NO];
    [filePathView setCanChooseDirectories: YES];
    [filePathView setTreatsFilePackagesAsDirectories: YES];
	
	[[playerView window] setBackgroundColor: [NSColor colorWithPatternImage: [NSImage imageNamed: @"tv_background"]]];
}


// -----------------------------------------------------------------------------
//  application:openFile:
//      Allow dropping a volume or VIDEO_TS folder on this app to open it.
// -----------------------------------------------------------------------------

-(BOOL) application: (NSApplication*)sender openFile: (NSString*)path
{
    [filePathView setStringValue: path];
    [[filePathView target] performSelector: [filePathView action] withObject: filePathView];
}


// -----------------------------------------------------------------------------
//  applicationShouldTerminateAfterLastWindowClosed:
//      Make sure our app closes when the window goes away.
// -----------------------------------------------------------------------------

-(BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication*)sender
{
    return YES;
}


// -----------------------------------------------------------------------------
//  applicationDidFinishLaunching:
//      Set up a default DVD path if available on startup.
// -----------------------------------------------------------------------------

-(void) applicationDidFinishLaunching: (NSNotification*)notification
{
    if( [filePathView stringValue] != nil )
        return;
    
    // Restore saved DVD path if available:
    NSString*   path = [[NSUserDefaults standardUserDefaults] objectForKey: @"UKMovieTheatreDVDPath"];
    if( !path || ![[NSFileManager defaultManager] fileExistsAtPath: path] )
    {
        // Otherwise find first inserted DVD:
        NSArray*    dvds = [[NSWorkspace sharedWorkspace] mountedMediaOfType: UKVolumeDVDMediaType];
        
        if( [dvds count] > 0 )
            path = [dvds objectAtIndex: 0];
        else
            path = nil;
    }
    
    // Have a valid path? Make it current one:
    if( path )
    {
        NS_DURING
            [filePathView setStringValue: path];
            [[filePathView target] performSelector: [filePathView action] withObject: filePathView];
        NS_HANDLER
            NSLog(@"Couldn't load DVD: %@", localException);
        NS_ENDHANDLER
    }
    
    [playerView reloadBookmarkMenu];
    
    // Have a path? Start playing!
    if( [filePathView stringValue] != nil )
        [playerView play: nil];
}


// -----------------------------------------------------------------------------
//  applicationWillTerminate:
//      Save current DVD path to prefs to be able to get back to it on relaunch.
// -----------------------------------------------------------------------------

-(void) applicationWillTerminate: (NSNotification*)notification
{
    NSString*       path = [filePathView stringValue];
    
    if( path )
        [[NSUserDefaults standardUserDefaults] setObject: path forKey: @"UKMovieTheatreDVDPath"];
}


// -----------------------------------------------------------------------------
//  toggleKeepWindowFrontmost:
//      Action for the "float on top" checkbox to make the window stay on top.
// -----------------------------------------------------------------------------

-(void) toggleKeepWindowFrontmost: (id)sender
{
    int     newLevel = ([[playerView window] level] == NSNormalWindowLevel) ? NSFloatingWindowLevel : NSNormalWindowLevel;
    [[playerView window] setLevel: newLevel];
}


// -----------------------------------------------------------------------------
//  setWindowSize:
//      Action for the window size menu items. The menu item's tag property
//      indicates which size to pick.
// -----------------------------------------------------------------------------

// Sender's tag must be 0-4 to indicate size
-(void) setWindowSize: (id)sender
{
    float       factors[5] = {
                                0.5,
                                0.75,
                                1.0,
                                1.5,
                                2.0,
                             };
    NSWindow*   win = [playerView window];
    float       factor = factors[ [sender tag] ];
    NSRect      newFrame = [win frame];
    NSSize      vidSize = [playerView videoSize];
    vidSize.width *= factor;
    vidSize.height *= factor;
    newFrame.size = [playerView windowSizeForViewSize: vidSize];
    
    [[playerView window] setFrame: newFrame display: YES];
}


// -----------------------------------------------------------------------------
//  windowWillUseStandardFrame:defaultFrame:
//      Offer sensible sizes for the "zoom" button.
//
//      TO DO: Find a way to make the modifier keys *force* that rect, instead
//      of only working half the time.
// -----------------------------------------------------------------------------

-(NSRect)   windowWillUseStandardFrame: (NSWindow*)window defaultFrame: (NSRect)newFrame
{
    NSSize      vidSize = [playerView videoSize];
    
    if( ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) == NSAlternateKeyMask )
    {
        vidSize.width /= 2;
        vidSize.height /= 2;
    }
    else if( ([[NSApp currentEvent] modifierFlags] & NSControlKeyMask) == NSControlKeyMask )
    {
        vidSize.width /= 1.5;
        vidSize.height /= 1.5;
    }
    else if( ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) == NSShiftKeyMask )
    {
        vidSize.width *= 2;
        vidSize.height *= 2;
    }
    newFrame.size = [playerView windowSizeForViewSize: vidSize];
    
    return newFrame;
}

@end


