//
//  UKDVDPlayerView.h
//  MovieTheatre
//
//  Created by Uli Kusterer on 12.06.05.
//  Copyright 2005 M. Uli Kusterer. All rights reserved.
//

// -----------------------------------------------------------------------------
//  Headers:
// -----------------------------------------------------------------------------

#import <Cocoa/Cocoa.h>
#import <DVDPlayback/DVDPlayback.h>


// -----------------------------------------------------------------------------
//  DVD Bookmark for returning to a previous play position:
// -----------------------------------------------------------------------------

@interface UKDVDBookmark : NSObject <NSCoding>
{
    unsigned int        position;           // Seconds into the chapter the bookmark is at.
    unsigned short      framePosition;      // Frame position the bookmark is at.
    unsigned short      titleNum;           // Title number the bookmark is in.
    unsigned short      chapterNum;         // Chapter number the bookmark is in.
    NSString*           name;               // Name of this bookmark (user-specified, displayed in menu).
    NSString*           dvdName;            // Name of DVD this bookmark is for.
}

// Constructor is private. Use UKDVDPlayerView::currentBookmark instead!
-(id) initWithName: (NSString*)nm position: (unsigned int)pos frames: (unsigned short)frp title: (unsigned short)ttl chapter: (unsigned short)chap dvdName: (NSString*)dnm;

// Users may specify human-readable names for their bookmarks:
-(NSString*)            name;
-(void)                 setName: (NSString*)nm;

-(NSString*)            stringValue;    // Returns name if set, summaryString otherwise. Used for menu item names.

-(unsigned int)         seconds;
-(unsigned short)       framePosition;
-(unsigned short)       titleNum;
-(unsigned short)       chapterNum;
-(NSString*)            dvdName;

-(void)                 set;    // Go to bookmark location.

// private:
-(NSString*)    summaryString;

@end


// -----------------------------------------------------------------------------
//  DVD Event reflecting something that happened during playback:
// -----------------------------------------------------------------------------

@interface UKDVDEvent : NSObject
{
    DVDEventCode        eventCode;      // DVDEventCode.
    DVDEventValue       eventValue1;
    DVDEventValue       eventValue2;
}

-(id)   initWithEventCode: (DVDEventCode)ec value1: (UInt32)v1 value2: (UInt32)v2; // Private.

-(DVDEventCode)         type;               // eventCode.

-(unsigned long)        titleNumber;        // eventValue1 for eventCode = kDVDEventTitle.
-(unsigned long)        chapterNumber;      // eventValue1 for eventCode = kDVDEventPTT.
-(unsigned long)        streamID;           // eventValue1 for eventCode = kDVDEventAngle or kDVDEventAudioStream or kDVDEventSubpictureStream.
-(BOOL)                 streamVisible;      // eventValue2 != 0 for eventCode = kDVDEventSubpictureStream
-(DVDAspectRatio)       aspectRatio;        // eventValue1 for eventCode = kDVDEventDisplayMode
-(BOOL)                 isStill;            // eventValue1 for eventCode = kDVDEventStill
-(DVDState)             playbackState;      // eventValue1 for eventCode = kDVDEventPlayback
-(DVDFormat)            videoFormat;        // eventValue1 for eventCode = kDVDEventVideoStandard
-(DVDScanRate)          scanRate;           // eventValue1 for eventCode = kDVDEventScanSpeed
-(DVDMenu)              menuNumber;         // eventValue1 for eventCode = kDVDEventMenuCalled
-(DVDRegionCode)        discRegion;         // eventValue1 for eventCode = kDVDEventRegionMismatch
-(unsigned long)        elapsedTime;        // eventValue1 for eventCode = kDVDEventTitleTime or kDVDEventChapterTime
-(unsigned long)        titleDuration;      // eventValue2 for eventCode = kDVDEventTitleTime
-(unsigned long)        chapterDuration;    // eventValue2 for eventCode = kDVDEventChapterTime
-(DVDErrorCode)         errorCode;          // eventValue1 for eventCode = kDVDEventError

/*
    Most of the accessors are only valid for a particular type of event. If you call them on another
    type of event, they'll try to return some "invalid" value. For most numbers that is 0. For the
    DVDxxx types, it's usually some "Unknown" or "Invalid" constant. BOOLs return -1 in that case.
    
    This may change in future versions, so don't rely on it for your apps. This is just here to help
    you in debugging.
*/

// private:
-(NSString*)    eventName;

@end


// -----------------------------------------------------------------------------
//  DVD Player View (main class):
// -----------------------------------------------------------------------------

@interface UKDVDPlayerView : NSView
{
    NSString*               dvdPath;            // Path of DVD being played.
    NSMutableArray*         filteredBookmarks;  // Cached lists of bookmarks applying to the current DVD.
    DVDEventCallBackRef     eventCallbackID;    // Reference to our event callback so we can uninstall it again.
    NSSize                  aspectRatio;        // Aspect Ratio.
    BOOL                    isAsleep;           // Did the Mac just go to sleep?
	BOOL					didInitializeDVDForThisView;
    IBOutlet NSMenu*        bookmarkMenu;       // The bookmark menu.
    IBOutlet NSTextField*   timePassedField;    // Time passed during playback.
    IBOutlet NSTextField*   trackNumberField;   // Track number currently playing.
    IBOutlet NSButton*      playStopButton;     // Play/Stop button.
    IBOutlet NSButton*      pauseResumeButton;  // Pause button.
    IBOutlet NSButton*      skipFwdButton;      // Jump to next track.
    IBOutlet NSButton*      skipBackButton;     // Jump to prev track.
    IBOutlet NSButton*      scanFwdButton;      // Fast forward with picture.
    IBOutlet NSButton*      scanBackButton;     // Fast rewind with picture.
    IBOutlet NSButton*      stepFwdButton;      // Frame-by-frame-stepping (forward).
    IBOutlet NSButton*      stepBackButton;     // Frame-by-frame-stepping (backwards).
}

// Select a DVD:
-(void) takePathFrom: (id)sender;     // Takes path to DVD itself, or to a VIDEO_TS folder.
-(void) ejectDVD: (id)sender;

// Play/Stop buttons (on "player device"):
-(void) play: (id)sender;   // If playing, stops.
-(void) pause: (id)sender;  // If paused, resumes.

// Menu navigation buttons (on "remote control"):
-(void) remoteHitEnterButton: (id)sender;
-(void) remoteHitRightButton: (id)sender;
-(void) remoteHitLeftButton: (id)sender;
-(void) remoteHitDownButton: (id)sender;
-(void) remoteHitUpButton: (id)sender;

-(void) remoteHitCenterButton: (id)sender;	// Depending on context, this is "enter" or "play/pause".
-(void) remoteHitBackButton: (id)sender;	// Depending on context, this is back, title, or menu.

-(void) remoteHitTitleButton: (id)sender;
-(void) remoteHitMenuButton: (id)sender;
-(void) remoteHitAudioButton: (id)sender;
-(void) remoteHitAngleButton: (id)sender;
-(void) remoteHitSubPictureButton: (id)sender;

// Slow Scan buttons:
-(void) stepForward: (id)sender;
-(void) scanForwardOneEighth: (id)sender;
-(void) scanForwardOneFourth: (id)sender;
-(void) scanForwardOneHalf: (id)sender;

-(void) stepBackward: (id)sender;
-(void) scanBackwardOneEighth: (id)sender;
-(void) scanBackwardOneFourth: (id)sender;
-(void) scanBackwardOneHalf: (id)sender;

// Fast Scan buttons:
-(void) scanForward: (id)sender;
-(void) scanForward2x: (id)sender;
-(void) scanForward4x: (id)sender;
-(void) scanForward8x: (id)sender;
-(void) scanForward16x: (id)sender;
-(void) scanForward32x: (id)sender;

-(void) scanBackward: (id)sender;
-(void) scanBackward2x: (id)sender;
-(void) scanBackward4x: (id)sender;
-(void) scanBackward8x: (id)sender;
-(void) scanBackward16x: (id)sender;
-(void) scanBackward32x: (id)sender;

-(void) scanInDirection: (DVDScanDirection)wantDirection rate: (DVDScanRate)wantRate;

-(DVDScanRate)          scanRate;
-(DVDScanDirection)     scanDirection;

-(void) goNextChapter: (id)sender;
-(void) goPrevChapter: (id)sender;

-(void)		setVolume: (float)volume;
-(float)	volume;


// Cool stuff:
-(NSMenu*)          releaseBookmarkMenuAndAllocNewOne: (NSMenu*)bookmarkMenu;   // Takes a retained NSMenu, releases it, creates a new retained menu and inserts that in its stead.
-(NSMenu*)          bookmarkMenu;

-(void)             addCurrentBookmark: (id)sender;
-(UKDVDBookmark*)   currentBookmark;
-(void)             addBookmark: (UKDVDBookmark*)bm;
-(void)             removeBookmark: (UKDVDBookmark*)bm;
-(NSArray*)         bookmarks;      // Only bookmarks for current CD.
-(NSArray*)         allBookmarks;

-(NSString*)        currentDVDName;
-(NSSize)           videoSize;      // Actual size of the video currently playing.

// Events:
-(void) dispatchDVDEvent: (UKDVDEvent*)evt;

// Accessors:
-(BOOL) isPlaying;
-(BOOL) isPaused;

// private:
-(void) viewFrameDidChange: (NSNotification*)notif;

+(void) logCarbonErr: (OSStatus)err withPrefix: (NSString*)errPrefix;
+(void) applicationWillTerminate: (NSNotification*)notification;

+(void) loadBookmarksFromPrefs;
+(void) saveBookmarksToPrefs;

-(void) reloadBookmarkMenu;

@end
