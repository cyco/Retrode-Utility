//
//  REAppDelegate.h
//  Retrode
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RERetrodeManager.h"
@interface REAppDelegate : NSObject <NSApplicationDelegate>
- (IBAction)logRetrodeDescriptions:(id)sender;
- (IBAction)unmountRetrodes:(id)sender;
- (IBAction)mountRetrodes:(id)sender;
- (IBAction)readConfigurations:(id)sender;
- (IBAction)writeConfigurations:(id)sender;
- (IBAction)updateAvailableFirmwareVersion:(id)sender;
@end
