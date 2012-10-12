//
//  RUAppDelegate.h
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RURetrodeManager.h"
#import "RURetrode.h"
#import "RUSplashWindow.h"
extern NSString  * const kRUCopyFileToRetrodeNotificationName;
@interface RUAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, RURetrodeDelegate, NSDrawerDelegate, NSURLDownloadDelegate>

@property BOOL firmwareUpdateInProgress;
#pragma mark - 
@property IBOutlet NSButton       *configButton;
@property IBOutlet NSPopUpButton  *firmwareButton;
@property IBOutlet NSTableView    *releaseNotesTableView;
@property IBOutlet NSView         *instructionsContainer;
@property IBOutlet NSView         *deviceInfoContainer;
@property IBOutlet NSDrawer       *configDrawer;
@property IBOutlet NSDrawer       *firmwareDrawer;
@property IBOutlet NSView         *firmwareDrawerView;
@property IBOutlet NSView         *firmwareReleaseNotesView;
@property IBOutlet NSView         *firmwareDFUInstructionsView;
@property IBOutlet NSView         *firmwareProgressView;
@property IBOutlet NSTextField    *firmwareProgressOperationField;
@property IBOutlet NSView         *firmwareFailView;
@property IBOutlet NSTextField    *firmwareFailReasonField;
@property IBOutlet NSProgressIndicator *firmwareProgressIndicator;
@property IBOutlet NSView         *firmwareFinishedView;

@property IBOutlet NSViewController *fileSelectionViewController;
#pragma mark - User Interface -
- (IBAction)firmwareButtonAction:(id)sender;
- (IBAction)installFirmware:(id)sender;

- (IBAction)discardConfig:(id)sender;
- (IBAction)saveConfig:(id)sender;

- (IBAction)showOfficialRetrodeManual:(id)sender;

@property (strong) RURetrode *currentRetrode;
@end
