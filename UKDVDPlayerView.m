//
//  UKDVDPlayerView.m
//  MovieTheatre
//
//  Created by Uli Kusterer on 12.06.05.
//  Copyright 2005 M. Uli Kusterer. All rights reserved.
//

// -----------------------------------------------------------------------------
//  Headers:
// -----------------------------------------------------------------------------

#import "UKDVDPlayerView.h"
#import "NSString+CarbonUtilities.h"
#import "NSNumber+Minutes.h"
#import "NSWorkspace+TypeOfVolumeAtPath.h"
#import <Carbon/Carbon.h>


// -----------------------------------------------------------------------------
//  Globals:
// -----------------------------------------------------------------------------

static NSMutableArray*  gUKDVDPlayerViewBookmarks = nil;        // List of all bookmarks, for all DVDs.


// -----------------------------------------------------------------------------
//  Class methods:
// -----------------------------------------------------------------------------

@implementation UKDVDPlayerView

// -----------------------------------------------------------------------------
//  initialize:
//      Class is first used. Register DVDPlayback framework and load prefs.
// -----------------------------------------------------------------------------

+(void) initialize
{
    //NSLog(@"+) Registered DVD Framework.");
    DVDInitialize();    // Comment out to be able to debug.
    DVDEnableWebAccess( true );
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(applicationWillTerminate:) name: NSApplicationWillTerminateNotification object: NSApp];
    [UKDVDPlayerView loadBookmarksFromPrefs];
}


// -----------------------------------------------------------------------------
//  applicationWillTerminate:
//      App will quit. Save prefs and unregister with DVDPlayback framework.
// -----------------------------------------------------------------------------

+(void) applicationWillTerminate: (NSNotification*)notification
{
    [self saveBookmarksToPrefs];
    DVDDispose();
    //NSLog(@"-) Unregistered DVD Framework.");
}


// -----------------------------------------------------------------------------
//  loadBookmarksFromPrefs:
//      Called by +initialize to load the prefs.
// -----------------------------------------------------------------------------

+(void) loadBookmarksFromPrefs
{
    if( !gUKDVDPlayerViewBookmarks )
    {
        NSData*     archivedBookmarks = [[NSUserDefaults standardUserDefaults] objectForKey: @"UKDVDPlayerBookmarks"];
        if( archivedBookmarks )
            gUKDVDPlayerViewBookmarks = [[NSUnarchiver unarchiveObjectWithData: archivedBookmarks] retain];

        if( !gUKDVDPlayerViewBookmarks )
            gUKDVDPlayerViewBookmarks = [[NSMutableArray alloc] init];
    }
}


// -----------------------------------------------------------------------------
//  saveBookmarksToPrefs:
//      Called by +applicationWillTerminate to save the prefs.
// -----------------------------------------------------------------------------

+(void) saveBookmarksToPrefs
{
    NSData* archivedBookmarks = [NSArchiver archivedDataWithRootObject: gUKDVDPlayerViewBookmarks];
    
    [[NSUserDefaults standardUserDefaults] setObject: archivedBookmarks forKey: @"UKDVDPlayerBookmarks"];
}


// -----------------------------------------------------------------------------
//  UKDVDEventCallback:
//      Callbacks from DVDPlayback framework end up here, which forwards them
//      to our DVD view class like a real OO event.
// -----------------------------------------------------------------------------

void    UKDVDEventCallback( DVDEventCode inEventCode, DVDEventValue inEventValue1, DVDEventValue inEventValue2, void* inRefCon )
{
    UKDVDPlayerView*    view = (UKDVDPlayerView*) inRefCon;
    NSAutoreleasePool*  pool = [[NSAutoreleasePool alloc] init];
    
    NS_DURING
        [view dispatchDVDEvent: [[[UKDVDEvent alloc] initWithEventCode: inEventCode value1: inEventValue1 value2: inEventValue2] autorelease]];
    NS_HANDLER
        NSLog( @"Uncaught exception in DVD Event Callback: %@", localException );
    NS_ENDHANDLER
    
    [pool release];
}


// -----------------------------------------------------------------------------
//  Instance methods:
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
//  * CONSTRUCTOR:
//      Register our callback and register for all the notifications we need
//      to hear about to react to new DVDs. or computer going to sleep.
// -----------------------------------------------------------------------------

-(id)   initWithFrame: (NSRect)frame
{
    if( (self = [super initWithFrame: frame]) )
    {
        OSStatus        err;
        DVDEventCode    codesToRegister[] = {
                                                kDVDEventTitle,
                                                kDVDEventPTT,
                                                kDVDEventAngle,
                                                kDVDEventAudioStream,
                                                kDVDEventSubpictureStream,
                                                kDVDEventDisplayMode,
                                                kDVDEventStill,
                                                kDVDEventPlayback,
                                                kDVDEventVideoStandard,
                                                kDVDEventScanSpeed,
                                                kDVDEventMenuCalled,
                                                kDVDEventTitleTime,
                                                kDVDEventError,
                                                kDVDEventChapterTime
                                            };
        
        NSNotificationCenter*   fileNC = [[NSWorkspace sharedWorkspace] notificationCenter];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(viewFrameDidChange:) name: NSViewFrameDidChangeNotification object: self];
        [fileNC addObserver: self selector: @selector(volumeDidMount:) name: NSWorkspaceDidMountNotification object: nil];
        [fileNC addObserver: self selector: @selector(computerWillSleep:) name: NSWorkspaceWillSleepNotification object: nil];
        [fileNC addObserver: self selector: @selector(computerDidWakeUp:) name: NSWorkspaceDidWakeNotification object: nil];
        err = DVDRegisterEventCallBack( UKDVDEventCallback, codesToRegister, sizeof(codesToRegister) / sizeof(DVDEventCode), self, &eventCallbackID );
        if( err != noErr )
            NSLog( @"initWithFrame DVDRegisterEventCallback() returned Error ID= %ld", err );
        aspectRatio = NSMakeSize(1,1);
    }
    return self;
}


// -----------------------------------------------------------------------------
//  * DESTRUCTOR:
//      Unregister our callback and unregister for all those notifications.
//      Kill our owned objects.
// -----------------------------------------------------------------------------

-(void) dealloc
{
    DVDUnregisterEventCallBack( eventCallbackID );
    
    [filteredBookmarks release];
    filteredBookmarks = nil;
    
    [dvdPath release];
    dvdPath = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    
    [super dealloc];
}


// -----------------------------------------------------------------------------
//  setupDVDPlaying:
//      Register the DVD playing window. Called whenever we move to a new
//      window.
// -----------------------------------------------------------------------------

-(void) setupDVDPlaying
{
    OSStatus        err = noErr;
    
    if( [self window] )
    {
		if( ![[self window] isVisible] )
		{
			NSLog( @"Postponing setup, window not yet visible" );
			return;
		}
		
        err = DVDSetVideoWindowID( [[self window] windowNumber] );
        if( err != noErr )
        {
		    NSLog(@"setupDVDPlaying DVDSetVideoWindowID() returned Error ID= %ld", err);
			return;
		}
        
		NSDictionary*       dict = [[[self window] screen] deviceDescription];
        CGDirectDisplayID   screenNum = (CGDirectDisplayID) [[dict objectForKey: @"NSScreenNumber"] unsignedIntValue];
        NSLog(@"setupDVDPlaying screenNum = %lx",screenNum);
		Boolean				isSupported = false;
        err = DVDSwitchToDisplay( screenNum, &isSupported );
        if( err != noErr )
        {
		    NSLog(@"setupDVDPlaying DVDSetVideoDisplay() returned Error ID= %ld", err);
			return;
		}
        if( !isSupported )
        {
		    NSLog(@"setupDVDPlaying DVD playback not supported on this display.");
			return;
		}

		didInitializeDVDForThisView = YES;
		NSLog( @"Setup completed." );
    }
}


// -----------------------------------------------------------------------------
//  dispatchDVDEvent:
//      React to events sent to us from the DVDPlayback framework.
// -----------------------------------------------------------------------------

-(void) dispatchDVDEvent: (UKDVDEvent*)evt
{
    switch( [evt type] )
    {
        // Track number changed:
        case kDVDEventPTT:
            [trackNumberField setIntValue: [evt chapterNumber]];
            [self viewFrameDidChange: nil];
            break;
            
        // Title ("sub-movie") changed:
        case kDVDEventTitle:
            [self viewFrameDidChange: nil];
            break;
        
        // The time in this chapter changed (called ~ every second):
        case kDVDEventChapterTime:
           break;
        
        // The time in this title changed (called ~ every second):
        case kDVDEventTitleTime:
        {
            NSString*   titleTimeStr = [NSString stringWithFormat: @"%@ (%@)", [NSNumber secondsStringForInt: [evt elapsedTime] / 1000], [NSNumber secondsStringForInt: [evt titleDuration] / 1000] ];
            [timePassedField setStringValue: titleTimeStr];
            break;
        }
        
        // Display mode changed (size of movie playing):
        // Make sure we scale our display accordingly.
        case kDVDEventDisplayMode:
        {
            NSString*   strs[] = { 	@"kDVDAspectRatioUninitialized",
                                    @"kDVDAspectRatio4x3",
	                                @"kDVDAspectRatio4x3PanAndScan",
	                                @"kDVDAspectRatio16x9",
	                                @"kDVDAspectRatioLetterBox"
                                 };
            
            switch( [evt aspectRatio] )
            {
                case kDVDAspectRatio16x9:
                    aspectRatio.width = 16;
                    aspectRatio.height = 9;
                    break;
                    
                case kDVDAspectRatio4x3:
                    aspectRatio.width = 4;
                    aspectRatio.height = 3;
                    break;
                    
                default:
                    aspectRatio = NSMakeSize(1,1);
                    NSLog( @"%@", strs[ [evt aspectRatio] ] );
            }
            [self viewFrameDidChange: nil];
            break;
        }
        
        // Playback state changed, make sure UI is synced:
        case kDVDEventPlayback:
            switch( [evt playbackState] )
            {
                case kDVDStatePlaying:
                case kDVDStatePlayingStill:
                    [playStopButton setTitle: @"Stop"];
                    [playStopButton setEnabled: YES];
                    [pauseResumeButton setTitle: @"Pause"];
                    [pauseResumeButton setEnabled: YES];
                    [skipFwdButton setEnabled: YES];
                    [skipBackButton setEnabled: YES];
                    [scanFwdButton setEnabled: YES];
                    [scanBackButton setEnabled: YES];
                    [stepFwdButton setEnabled: YES];
                    [stepBackButton setEnabled: YES];
                    break;
                
                case kDVDStatePaused:
                    [playStopButton setTitle: @"Play"];
                    [playStopButton setEnabled: YES];
                    [pauseResumeButton setTitle: @"Resume"];
                    [pauseResumeButton setEnabled: YES];
                    [skipFwdButton setEnabled: YES];
                    [skipBackButton setEnabled: YES];
                    [scanFwdButton setEnabled: YES];
                    [scanFwdButton setState: 0];
                    [scanBackButton setEnabled: YES];
                    [scanBackButton setState: 0];
                    [stepFwdButton setEnabled: YES];
                    [stepBackButton setEnabled: YES];
                    break;
                
                case kDVDStateStopped:
                    [playStopButton setTitle: @"Play"];
                    [playStopButton setEnabled: YES];
                    [pauseResumeButton setTitle: @"Pause"];
                    [pauseResumeButton setEnabled: NO];
                    [skipFwdButton setEnabled: NO];
                    [skipBackButton setEnabled: NO];
                    [scanFwdButton setEnabled: NO];
                    [scanFwdButton setState: 0];
                    [scanBackButton setEnabled: NO];
                    [scanBackButton setState: 0];
                    [stepFwdButton setEnabled: NO];
                    [stepBackButton setEnabled: NO];
                    break;
                
                case kDVDStateScanning:
                    [playStopButton setTitle: @"Play"];
                    [playStopButton setEnabled: YES];
                    [pauseResumeButton setTitle: @"Pause"];
                    [pauseResumeButton setEnabled: YES];
                    [skipFwdButton setEnabled: YES];
                    [skipBackButton setEnabled: YES];
                    [scanFwdButton setEnabled: YES];
                    [scanBackButton setEnabled: YES];
                    if( [self scanRate] > 0 )
                    {
                        DVDScanDirection dir = [self scanDirection];
                        [scanFwdButton setState: (dir == kDVDScanDirectionForward)];
                        [scanBackButton setState: (dir == kDVDScanDirectionBackward)];
                    }
                    [stepFwdButton setEnabled: YES];
                    [stepBackButton setEnabled: YES];
                    break;
            }
            break;
        
        default:
            //NSLog(@"%@",evt);
            break;
    }
}


// -----------------------------------------------------------------------------
//  volumeDidMount:
//      A new DVD was inserted? If we had no DVD set up yet, this is the
//      opportunity to grab that DVD and start playing.
// -----------------------------------------------------------------------------

-(void) volumeDidMount: (NSNotification*)notif
{
    // Force bookmark menu to show the ones for this DVD:
    [filteredBookmarks release];
    filteredBookmarks = nil;
    
    // No DVD yet? Get one!
    if( dvdPath == nil )
    {
        dvdPath = [[notif userInfo] objectForKey: @"NSDevicePath"];
        NSString*   volType = [[NSWorkspace sharedWorkspace] typeOfVolumeAtPath: dvdPath];
        if( ![volType isEqualToString: UKVolumeDVDMediaType] )  // Not a DVD?
            dvdPath = nil;                                      // Go back to NIL, we don't play audio CDs.
    }
    
    // Cause the path change and start playing:
    [self takePathFrom: nil];
    if( dvdPath && ![self isPlaying] )
        [self play: nil];
}


// -----------------------------------------------------------------------------
//  computerWillSleep:
//      Computer about to go to sleep. Show our status message and tell
//      DVDPlayback framework to save its buffers.
//
//      Waking up again can take a while for the drive to spin up again, so we
//      show a "Please wait" status message on sleep so it's visible upon wake-
//      up until DVDPlayback framework is ready again.
// -----------------------------------------------------------------------------

-(void) computerWillSleep: (NSNotification*)notif
{
    DVDSleep();
    isAsleep = YES;
    [self setNeedsDisplay: YES];
}


// -----------------------------------------------------------------------------
//  computerDidWakeUp:
//      Computer about to wake from sleep. Tell DVDPlayback framework to restore
//      its buffers and once that is done, turn off our status message again.
// -----------------------------------------------------------------------------

-(void) computerDidWakeUp: (NSNotification*)notif
{
    DVDWakeUp();
    isAsleep = NO;
    [self setNeedsDisplay: YES];
}


// -----------------------------------------------------------------------------
//  viewDidMoveToWindow:
//      This view was moved to another window. Tell DVDPlayer framework so it
//      will play in the right place.
// -----------------------------------------------------------------------------

-(void) viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
	
	didInitializeDVDForThisView = NO;
    
    [self setupDVDPlaying];
    [self viewFrameDidChange: nil];
    [[self window] setAcceptsMouseMovedEvents: YES];
}


// -----------------------------------------------------------------------------
//  takePathFrom:
//      Action for file path field. When the field changes, call this to update
//      the DVD and open the appropriate DVD or media.
// -----------------------------------------------------------------------------

-(void) takePathFrom: (id)sender
{
    NSString*       path = nil;
    
    if( sender == nil )
        path = dvdPath;
    else
    {
        if( [sender respondsToSelector: @selector(stringValue)] )
            path = [sender stringValue];
        else
            path = [sender string];
    }
    
    FSRef           ref;
    
    if( path && [path getFSRef: &ref] )
    {
        OSStatus err;
        if( [[path lastPathComponent] isEqualToString: @"VIDEO_TS"] )
            err = DVDOpenMediaFile( &ref );
        else
            err = DVDOpenMediaVolume( &ref );
        if( err != kDVDErrorPlaybackOpen )
            [UKDVDPlayerView logCarbonErr: err withPrefix: @"takeVolumePathFrom: DVDOpenMediaVolume(): "];
        
        dvdPath = path;
    }
    
    [self reloadBookmarkMenu];
	[self setNeedsDisplay: YES];
}


// -----------------------------------------------------------------------------
//  videoSize:
//      Size of the video currently playing. This is effectively the ideal size
//      of the current view.
// -----------------------------------------------------------------------------

-(NSSize)   videoSize
{
    UInt16          fullWidth, fullHeight;
    float           wd, hg;
    
    DVDGetNativeVideoSize( &fullWidth, &fullHeight );
    wd = fullWidth;
    hg = fullHeight;
    
    if( aspectRatio.width != aspectRatio.height )
        hg = (wd / aspectRatio.width) * aspectRatio.height;
    
    return NSMakeSize( wd, hg );
}


// -----------------------------------------------------------------------------
//  viewFrameDidChange:
//      The view was resized. Tell DVDPlayer framework about it.
// -----------------------------------------------------------------------------

-(void) viewFrameDidChange: (NSNotification*)notif
{
    Rect            box;
    NSView*         contView = [[self window] contentView];
    NSRect          frm = [self convertRect: [self bounds] toView: contView];
    NSRect          displayFrm = frm;
    float           height = [contView bounds].size.height;
    NSSize          videoSize = [self videoSize];
    
    // Calculate best size that still fits in our rect:
    float           heightFactor = frm.size.height / videoSize.height;

    displayFrm.size.height = videoSize.height * heightFactor;
    displayFrm.size.width = videoSize.width * heightFactor;
    
    if( displayFrm.size.width > frm.size.width )
    {
        heightFactor = frm.size.width / videoSize.width;
        
        displayFrm.size.height = videoSize.height * heightFactor;
        displayFrm.size.width = videoSize.width * heightFactor;
    }
	
	CGRect		cgBounds = NSRectToCGRect(displayFrm);
    OSStatus err = DVDSetVideoCGBounds( &cgBounds );
    if( err != noErr )
        NSLog(@"viewFrameDidChange DVDSetVideoBounds() returned Error ID= %ld", err);
}

// -----------------------------------------------------------------------------
//  drawRect:
//      Draw the view's contents.
// -----------------------------------------------------------------------------

-(void) drawRect: (NSRect)rect
{
	if( !didInitializeDVDForThisView )
		[self setupDVDPlaying];
	
    // Set that color and fill:
    [[NSColor blackColor] set];
    [NSBezierPath fillRect: rect];
    
    // If we're about to sleep or in the process of waking up, ...
    if( isAsleep )  // Display a "please wait" string.
        [@"Please Wait..." drawAtPoint: NSMakePoint(16,16) withAttributes: [NSDictionary dictionaryWithObjectsAndKeys: [NSColor whiteColor], NSForegroundColorAttributeName, nil]];
}


// -----------------------------------------------------------------------------
//  Utility methods for mouse tracking:
// -----------------------------------------------------------------------------

Point   QDPointFromNSPoint( NSPoint nsp )
{
    Point       qdp;
    
    qdp.h = nsp.x;
    qdp.v = nsp.y;
    
    return qdp;
}


// Main coordinate-conversion bottleneck:
Point   HitPointFromEventInView( NSEvent* evt, NSView* self )
{
    NSView*     contView = [[self window] contentView];
    NSPoint     clickPos = [evt locationInWindow];
    //NSLog( @"%@", NSStringFromPoint(clickPos) );
    
    clickPos.x += [self frame].origin.x;
    clickPos.y -= [self frame].origin.y;
    
    return QDPointFromNSPoint( clickPos );
}


// -----------------------------------------------------------------------------
//  mouseDown:
//      On mouseDown, highlight whatever the mouse is over, but don't trigger
//      a click (we save that for mouseUp).
// -----------------------------------------------------------------------------

-(void) mouseDown: (NSEvent*)evt
{
    [[self window] makeFirstResponder: self];
    
    SInt32      outIndex = 0;
    
	CGPoint		pos = NSPointToCGPoint([evt locationInWindow]);
    DVDDoMenuCGMouseOver( &pos, &outIndex );
}

-(void) mouseUp: (NSEvent*)evt
{
    SInt32      outIndex = 0;
    
	CGPoint		pos = NSPointToCGPoint([evt locationInWindow]);
    DVDDoMenuCGClick( &pos, &outIndex );
}


-(void) mouseDragged: (NSEvent*)evt
{
    SInt32      outIndex = 0;
    
	CGPoint		pos = NSPointToCGPoint([evt locationInWindow]);
    DVDDoMenuCGMouseOver( &pos, &outIndex );
}


-(void) mouseMoved: (NSEvent*)evt
{
    SInt32      outIndex = 0;
    
	CGPoint		pos = NSPointToCGPoint([evt locationInWindow]);
    DVDDoMenuCGMouseOver( &pos, &outIndex );
}

- (void)mouseEntered:(NSEvent *)theEvent
{
    
}


- (void)mouseExited:(NSEvent *)theEvent
{
    
}


-(BOOL) acceptsFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    return YES;
}


- (BOOL)resignFirstResponder
{
    return YES;
}


// -----------------------------------------------------------------------------
//  Play/Stop and Pause/Resume + detect what state we're in:
// -----------------------------------------------------------------------------

-(BOOL) isPlaying
{
    Boolean     playing = NO;
    OSStatus err = DVDIsPlaying( &playing );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"isPlaying DVDIsPlaying(): "];
    
    return playing;
}


-(BOOL) isPaused
{
    Boolean     paused = YES;
    OSStatus err = DVDIsPaused( &paused );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"isPaused DVDIsPaused(): "];
    
    return paused;
}


-(void) play: (id)sender
{
    OSStatus    err = noErr;
    if( ![self isPlaying] )
        err = DVDPlay();
    else if( [self scanRate] != 0
            || [self isPaused] )
    {
        err = DVDPause();
        if( err == noErr )
            err = DVDResume();
    }
    else
        err = DVDStop();
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"pause: DVDPlay(): "];
}


-(void) pause: (id)sender
{
    OSStatus    err = noErr;
    if( ![self isPaused] )
        err = DVDPause();
    else
        err = DVDResume();
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"pause: DVDPause(): "];
}


-(void) ejectDVD: (id)sender
{
    DVDStop();
    DVDCloseMediaVolume();
    if( ![[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath: dvdPath] )
        NSLog(@"Couldn't eject DVD %@", dvdPath);
    
    [filteredBookmarks release];
    filteredBookmarks = nil;
    dvdPath = nil;
    
    [self reloadBookmarkMenu];
}


-(void) goNextChapter: (id)sender
{
    OSStatus err = DVDNextChapter();
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"goNextChapter: DVDNextChapter(): "];
}


-(void) goPrevChapter: (id)sender
{
    OSStatus err = DVDPreviousChapter();
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"goPrevChapter: DVDPreviousChapter(): "];
}


// -----------------------------------------------------------------------------
//  Scan/Step through track:
// -----------------------------------------------------------------------------

-(void) stepForward: (id)sender
{
    OSStatus err = DVDStepFrame( kDVDScanDirectionForward );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"stepForward: DVDStepFrame(): "];
}


-(void) stepBackward: (id)sender
{
    OSStatus err = DVDStepFrame( kDVDScanDirectionBackward );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"stepBackward: DVDStepFrame(): "];
}


-(void) scanInDirection: (DVDScanDirection)wantDirection rate: (DVDScanRate)wantRate
{
    DVDScanRate         outRate;
    DVDScanDirection    outDirection;
    
    OSStatus err = DVDGetScanRate( &outRate, &outDirection );
    if( err == noErr && (outRate != wantRate || outDirection != wantDirection) )
        err = DVDScan( wantRate, wantDirection );
    else
        DVDResume();
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"scanInDirection:rate: DVDScan(): "];
}


-(void) scanForwardOneEighth: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRateOneEigth];
}


-(void) scanBackwardOneEighth: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRateOneEigth];
}


-(void) scanForwardOneFourth: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRateOneFourth];
}


-(void) scanBackwardOneFourth: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRateOneFourth];
}


-(void) scanForwardOneHalf: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRateOneHalf];
}


-(void) scanBackwardOneHalf: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRateOneHalf];
}


-(void) scanForward: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRate1x];
}


-(void) scanBackward: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRate1x];
}


-(void) scanForwardWithSpeedFromTag: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: [sender tag]];
}


-(void) scanBackwardWithSpeedFromTag: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: [sender tag]];
}


-(void) scanForward2x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRate2x];
}


-(void) scanBackward2x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRate2x];
}


-(void) scanForward4x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRate4x];
}


-(void) scanBackward4x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRate4x];
}


-(void) scanForward8x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRate8x];
}


-(void) scanBackward8x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRate8x];
}


-(void) scanForward16x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRate16x];
}


-(void) scanBackward16x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRate16x];
}


-(void) scanForward32x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionForward rate: kDVDScanRate32x];
}


-(void) scanBackward32x: (id)sender
{
    [self scanInDirection: kDVDScanDirectionBackward rate: kDVDScanRate32x];
}


-(DVDScanRate)    scanRate
{
    DVDScanRate         rate;
    DVDScanDirection    dir;
    DVDState            state;
    
    if( DVDGetState( &state ) != noErr )
        return 0;
    
    if( state != kDVDStateScanning )
        return 0;
    
    if( DVDGetScanRate( &rate, &dir ) != noErr )
        return 0;
    else
        return rate;
}


-(DVDScanDirection)    scanDirection
{
    DVDScanRate         rate;
    DVDScanDirection    dir;
    DVDState            state;
    
    if( DVDGetState( &state ) != noErr || state != kDVDStateScanning )
        return 0;
    
    if( DVDGetScanRate( &rate, &dir ) != noErr )
        return 0;
    else
        return dir;
}


// -----------------------------------------------------------------------------
//  Menu navigation buttons (called by arrow key calls below etc.):
// -----------------------------------------------------------------------------

-(void) remoteHitUpButton: (id)sender
{
    OSStatus err = DVDDoUserNavigation( kDVDUserNavigationMoveUp );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitUpButton: DVDDoUserNavigation(): "];
}


-(void) remoteHitDownButton: (id)sender
{
    OSStatus err = DVDDoUserNavigation( kDVDUserNavigationMoveDown );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitDownButton: DVDDoUserNavigation(): "];
}


-(void) remoteHitLeftButton: (id)sender
{
    OSStatus err = DVDDoUserNavigation( kDVDUserNavigationMoveLeft );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitLeftButton: DVDDoUserNavigation(): "];
}


-(void) remoteHitRightButton: (id)sender
{
    OSStatus err = DVDDoUserNavigation( kDVDUserNavigationMoveRight );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitRightButton: DVDDoUserNavigation(): "];
}


-(void) remoteHitEnterButton: (id)sender
{
    OSStatus err = DVDDoUserNavigation( kDVDUserNavigationEnter );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitEnterButton: DVDDoUserNavigation(): "];
}


// -----------------------------------------------------------------------------
//  Short access buttons for menus:
// -----------------------------------------------------------------------------

-(void) remoteHitTitleButton: (id)sender
{
    OSStatus err = DVDGoToMenu( kDVDMenuTitle );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitTitleButton: DVDGoToMenu(): "];
}


-(void) remoteHitMenuButton: (id)sender
{
    OSStatus err = DVDGoToMenu( kDVDMenuRoot );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitMenuButton: DVDGoToMenu(): "];
}


-(void) remoteHitAudioButton: (id)sender
{
    OSStatus err = DVDGoToMenu( kDVDMenuAudio );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitAudioButton: DVDGoToMenu(): "];
}


-(void) remoteHitAngleButton: (id)sender
{
    OSStatus err = DVDGoToMenu( kDVDMenuAngle );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitAngleButton: DVDGoToMenu(): "];
}


-(void) remoteHitSubPictureButton: (id)sender
{
    OSStatus err = DVDGoToMenu( kDVDMenuSubPicture );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"remoteHitSubPictureButton: DVDGoToMenu(): "];
}


// -----------------------------------------------------------------------------
//  Arrow keys & Return key -> remote navigation mapping:
// -----------------------------------------------------------------------------

- (void)moveRight:(id)sender
{
    [self remoteHitRightButton: sender];
}


- (void)moveLeft:(id)sender
{
    [self remoteHitLeftButton: sender];
}


- (void)moveUp:(id)sender
{
    [self remoteHitUpButton: sender];
}


- (void)moveDown:(id)sender
{
    [self remoteHitDownButton: sender];
}


- (void)insertNewline:(id)sender
{
    [self remoteHitEnterButton: sender];
}

/*- (void)insertNewlineIgnoringFieldEditor:(id)sender
{
    [self remoteHitEnterButton: sender];
}*/


-(void) keyDown: (NSEvent*)evt
{
    NSString*   str = [evt characters];

    if( [str isEqualToString: @"\n"] || [str isEqualToString: @"\r"] )
        [self insertNewline: nil];
    else
        [super keyDown: evt];
}


// -----------------------------------------------------------------------------
//  Bookmarks:
// -----------------------------------------------------------------------------

-(NSArray*)     allBookmarks
{
    return gUKDVDPlayerViewBookmarks;
}

-(NSArray*)     bookmarks
{
    NSString*       dvdName = [self currentDVDName];

    if( !filteredBookmarks )
    {
        NSMutableArray* bms = [NSMutableArray array];
        NSEnumerator*   enny = [gUKDVDPlayerViewBookmarks objectEnumerator];
        UKDVDBookmark*  bm = nil;
        
        while( (bm = [enny nextObject]) )
        {
            if( [dvdName isEqualToString: [bm dvdName]] )
                [bms addObject: bm];
        }
        
        filteredBookmarks = [bms retain];
    }
    
    return filteredBookmarks;
}


-(void)             addCurrentBookmark: (id)sender
{
    [self addBookmark: [self currentBookmark]];
}


-(void)             addBookmark: (UKDVDBookmark*)bm
{
    [gUKDVDPlayerViewBookmarks addObject: bm];

    [filteredBookmarks autorelease];
    filteredBookmarks = nil;

    [self reloadBookmarkMenu];
}


-(void)             removeBookmark: (UKDVDBookmark*)bm
{
    [gUKDVDPlayerViewBookmarks removeObject: bm];

    [filteredBookmarks autorelease];
    filteredBookmarks = nil;

    [self reloadBookmarkMenu];
}


-(NSMenu*)  bookmarkMenu
{
    NSArray*        bms = [self bookmarks];
    NSEnumerator*   enny = [bms objectEnumerator];
    UKDVDBookmark*  bm = nil;
    NSMenu*         bmMenu = [[[NSMenu alloc] initWithTitle: @"Bookmarks"] autorelease];
    NSMenuItem*		item = nil;
    
    while( (bm = [enny nextObject]) )
    {
        NSString*   nm = [bm stringValue];
        if( nm )
        {
            item = [bmMenu addItemWithTitle: nm action: @selector(set) keyEquivalent: @""];
            [item setTarget: bm];
        }
    }
    
    return bmMenu;
}


-(UKDVDBookmark*)   currentBookmark
{
    DVDTimePosition pos;
    UInt16          frm;
    UInt16          chapter;
    UInt16          title;
    
    OSStatus err = DVDGetTime( kDVDTimeCodeElapsedSeconds, &pos, &frm );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"currentBookmark DVDGetTime(): "];

    err = DVDGetChapter( &chapter );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"currentBookmark DVDGetChapter(): "];

    err = DVDGetTitle( &title );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"currentBookmark DVDGetTitle(): "];
    
    return [[[UKDVDBookmark alloc] initWithName: nil position: pos frames: frm title: title chapter: chapter dvdName: [self currentDVDName]] autorelease];
}


-(NSString*)    currentDVDName
{
    NSString*   nm = [dvdPath lastPathComponent];
    if( [nm isEqualToString: @"VIDEO_TS"] )
        nm = [[dvdPath stringByDeletingLastPathComponent] lastPathComponent];
    
    return nm;
}


-(void) setBookmarkMenu: (NSMenu*)mnu
{
    [bookmarkMenu autorelease];
    bookmarkMenu = [mnu retain];
}

-(void) reloadBookmarkMenu
{
    bookmarkMenu = [self releaseBookmarkMenuAndAllocNewOne: bookmarkMenu];
}


-(NSMenu*)  releaseBookmarkMenuAndAllocNewOne: (NSMenu*)bmMenu
{
    if( !bookmarkMenu )
    {
        NSLog(@"Bookmark menu outlet not hooked up.");
        return nil;
    }
    
    // Find old menu and create a new one:
    NSMenu* sup = [bmMenu supermenu];
    int ind = [sup indexOfItemWithSubmenu: bmMenu];
    NSMenuItem* item = [sup itemAtIndex: ind];
    NSString*   mnuName = [item title];
    if( !mnuName )
        mnuName = @"BOOKMARKS";
    NSMenuItem* newItem = [[[NSMenuItem alloc] initWithTitle: mnuName action:0 keyEquivalent:@""] autorelease];
    NSMenu* oldMenu = [bmMenu retain];
    bmMenu = [[self bookmarkMenu] retain];
    
    [sup removeItem: item];
    [sup insertItem: newItem atIndex: ind];
    [newItem setSubmenu: bmMenu];
    
    // Move over old menu items:
    NSEnumerator*	enny = [[oldMenu itemArray] objectEnumerator];
    NSMenuItem*		currItem = nil;
    
    while( (currItem = [enny nextObject]) )
    {
        if( [currItem action] != @selector(set) )
        {
            [currItem retain];
            [oldMenu removeItem: currItem];
            [bmMenu addItem: currItem];
            [currItem release];
        }
    }
    
    // Replace old menu with new one:
    [oldMenu autorelease];
    
    return bmMenu;
}


// -----------------------------------------------------------------------------
//  Utility method:
// -----------------------------------------------------------------------------

+(void) logCarbonErr: (OSStatus)err withPrefix: (NSString*)errPrefix
{
    if( err != noErr )
    {
        NSString*   errMsg = nil;
        switch( err )
        {
            case kDVDErrorNoValidMedia:
                errMsg = @"No valid media selected. Select a DVD or VIDEO_TS folder to play.";
                break;
            
            case kDVDErrorUserActionNoOp:
                errMsg = @"Operation not Permitted at this time.";
                break;
            
            default:
                errMsg = [NSString stringWithFormat: @"MacOS Error ID=%ld", err];
                break;
        }
        
        NSLog( @"Error: %@%@", errPrefix, errMsg );
    }
}

@end


// -----------------------------------------------------------------------------
//  DVDBookmark Class:
// -----------------------------------------------------------------------------

@implementation UKDVDBookmark

-(id) initWithName: (NSString*)nm position: (unsigned int)pos frames: (unsigned short)frp title: (unsigned short)ttl chapter: (unsigned short)chap dvdName: (NSString*)dnm
{
    if( (self = [super init]) )
    {
        name = [nm retain];
        position = pos;
        framePosition = frp;
        titleNum = ttl;
        chapterNum = chap;
        dvdName = [dnm retain];
    }
    
    return self;
}


-(id)   initWithCoder: (NSCoder*)coder
{
    self = [super init];
    if( !self )
        return nil;
    
    [coder decodeValueOfObjCType: @encode(unsigned int) at: &position];
    [coder decodeValueOfObjCType: @encode(unsigned short) at: &framePosition];
    [coder decodeValueOfObjCType: @encode(unsigned short) at: &titleNum];
    [coder decodeValueOfObjCType: @encode(unsigned short) at: &chapterNum];
    [self setName: [coder decodeObject]];
    dvdName = [[coder decodeObject] retain];
    
    return self;
}


-(void) dealloc
{
    [name release];
    name = nil;
    [dvdName release];
    dvdName = nil;
    
    [super dealloc];
}

-(void) encodeWithCoder: (NSCoder*)coder
{
    [coder encodeValueOfObjCType: @encode(unsigned int) at: &position];
    [coder encodeValueOfObjCType: @encode(unsigned short) at: &framePosition];
    [coder encodeValueOfObjCType: @encode(unsigned short) at: &titleNum];
    [coder encodeValueOfObjCType: @encode(unsigned short) at: &chapterNum];
    [coder encodeObject: name];
    [coder encodeObject: dvdName];
}


-(unsigned int)         seconds
{
    return position;
}


-(unsigned short)       framePosition
{
    return framePosition;
}


-(unsigned short)         titleNum
{
    return titleNum;
}

-(unsigned short)         chapterNum
{
    return chapterNum;
}

-(NSString*)            stringValue
{
    if( name != nil )
        return name;
    else
        return [self summaryString];
}


-(NSString*)    name
{
    return name;
}


-(void)         setName: (NSString*)nm
{
    [nm retain];
    [name release];
    name = nm;
}


-(NSString*)    summaryString
{
    return [NSString stringWithFormat: @"%d/%d %@ (Frame %d) - %@", titleNum, chapterNum, [NSNumber secondsStringForInt: position], framePosition, dvdName];
}

-(NSString*)            dvdName
{
    return dvdName;
}

-(void)                 set
{
    OSStatus    err = DVDStop();    // Stop movie, to work around some DVD's restrictions on when we can change tracks.
    if( err != noErr && err != kDVDErrorUserActionNoOp )
        [UKDVDPlayerView logCarbonErr: err withPrefix: @"set DVDStop(): "];
    
    err = DVDSetTitle( titleNum );
    if( err != noErr && err != kDVDErrorUserActionNoOp )
        [UKDVDPlayerView logCarbonErr: err withPrefix: @"set DVDSetTitle(): "];
    
    err = DVDSetChapter( chapterNum );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"set DVDSetChapter(): "];
    
    err = DVDSetTime( kDVDTimeCodeElapsedSeconds, position, framePosition );
    [UKDVDPlayerView logCarbonErr: err withPrefix: @"set DVDSetTime(): "];

    err = DVDPlay();                // Resume movie, to work around some DVD's restrictions on when we can change tracks.
    if( err != noErr && err != kDVDErrorUserActionNoOp )
        [UKDVDPlayerView logCarbonErr: err withPrefix: @"set DVDPlay(): "];
}


-(NSString*)    description
{
    return [NSString stringWithFormat: @"%@ { \"%@\", %@ }", NSStringFromClass([self class]), name, [self summaryString]];
}


@end


// -----------------------------------------------------------------------------
//  DVDEvent Class:
// -----------------------------------------------------------------------------

@implementation UKDVDEvent

-(id)   initWithEventCode: (DVDEventCode)ec value1: (UInt32)v1 value2: (UInt32)v2
{
    if( (self = [super init]) )
    {
        eventCode = ec;
        eventValue1 = v1;
        eventValue2 = v2;
    }
    
    return self;
}

-(DVDEventCode)         type            // eventCode.
{
    return eventCode;
}


-(unsigned long)        titleNumber         // eventValue1 for eventCode = kDVDEventTitle.
{
    return( (eventCode == kDVDEventTitle) ? eventValue1 : 0 );
}

-(unsigned long)        chapterNumber       // eventValue1 for eventCode = kDVDEventPTT.
{
    return( (eventCode == kDVDEventPTT) ? eventValue1 : 0 );
}

-(unsigned long)        streamID            // eventValue1 for eventCode = kDVDEventAngle or kDVDEventAudioStream or kDVDEventSubpictureStream.
{
    return( (eventCode == kDVDEventAngle || eventCode == kDVDEventAudioStream || eventCode == kDVDEventSubpictureStream) ? eventValue1 : 0 );
}

-(BOOL)                 streamVisible       // eventValue2 != 0 for eventCode = kDVDEventSubpictureStream
{
    return( (eventCode == kDVDEventSubpictureStream) ? (eventValue2 != 0) : -1 );
}

-(DVDAspectRatio)       aspectRatio         // eventValue1 for eventCode = kDVDEventDisplayMode
{
    return( (eventCode == kDVDEventDisplayMode) ? eventValue1 : kDVDAspectRatioUninitialized );
}

-(BOOL)                 isStill             // eventValue1 for eventCode = kDVDEventStill
{
    return( (eventCode == kDVDEventStill) ? eventValue1 : -1 );
}

-(DVDState)             playbackState       // eventValue1 for eventCode = kDVDEventPlayback
{
    return( (eventCode == kDVDEventPlayback) ? eventValue1 : kDVDStateUnknown );
}

-(DVDFormat)            videoFormat         // eventValue1 for eventCode = kDVDEventVideoStandard
{
    return( (eventCode == kDVDEventVideoStandard) ? eventValue1 : kDVDFormatUninitialized );
}

-(DVDScanRate)          scanRate            // eventValue1 for eventCode = kDVDEventScanSpeed
{
    return( (eventCode == kDVDEventScanSpeed) ? eventValue1 : kDVDFormatUninitialized );
}

-(DVDMenu)              menuNumber          // eventValue1 for eventCode = kDVDEventMenuCalled
{
    return( (eventCode == kDVDEventMenuCalled) ? eventValue1 : kDVDMenuNone );
}

-(DVDRegionCode)        discRegion          // eventValue1 for eventCode = kDVDEventRegionMismatch
{
    return( (eventCode == kDVDEventRegionMismatch) ? eventValue1 : kDVDRegionCodeUninitialized );
}

-(unsigned long)        elapsedTime         // eventValue1 for eventCode = kDVDEventTitleTime or kDVDEventChapterTime
{
    return( (eventCode == kDVDEventTitleTime || eventCode == kDVDEventChapterTime) ? eventValue1 : 0 );
}

-(unsigned long)        titleDuration       // eventValue2 for eventCode = kDVDEventTitleTime
{
    return( (eventCode == kDVDEventTitleTime) ? eventValue2 : 0 );
}

-(unsigned long)        chapterDuration     // eventValue2 for eventCode = kDVDEventChapterTime
{
    return( (eventCode == kDVDEventChapterTime) ? eventValue2 : 0 );
}

-(DVDErrorCode)         errorCode;          // eventValue1 for eventCode = kDVDEventError
{
    return( (eventCode == kDVDEventError) ? eventValue1 : noErr );
}


-(NSString*)    eventName
{
    NSString*   strs[] = {
                            @"kDVDEventTitle",
                            @"kDVDEventPTT",
                            @"kDVDEventValidUOP",
                            @"kDVDEventAngle",
                            @"kDVDEventAudioStream",
                            @"kDVDEventSubpictureStream",
                            @"kDVDEventDisplayMode",
                            @"kDVDEventDomain",
                            @"kDVDEventBitrate",
                            @"kDVDEventStill",
                            @"kDVDEventPlayback",
                            @"kDVDEventVideoStandard",
                            @"kDVDEventStreams",
                            @"kDVDEventScanSpeed",
                            @"kDVDEventMenuCalled",
                            @"kDVDEventParental",
                            @"kDVDEventPGC",
                            @"kDVDEventGPRM",
                            @"kDVDEventRegionMismatch",
                            @"kDVDEventTitleTime",
                            @"kDVDEventSubpictureStreamNumbers",
                            @"kDVDEventAudioStreamNumbers",
                            @"kDVDEventAngleNumbers",
                            @"kDVDEventError",
                            @"kDVDEventCCInfo",
                            @"kDVDEventChapterTime"
                        };
    if( eventCode <= 0 || (eventCode -1) > (sizeof(strs) / sizeof(NSString*)) )
        return [NSString stringWithFormat: @"UNKNOWN (%ld)", eventCode];
    else
        return( [NSString stringWithFormat: @"%@ (%ld)", strs[ eventCode -1 ], eventCode] );
}


-(NSString*)    description
{
    return [NSString stringWithFormat: @"%@ { type = %@; value1 = %lu, value2 = %lu }", NSStringFromClass([self class]), [self eventName], eventValue1, eventValue2];
}


@end
