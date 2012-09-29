//
//  REAppDelegate.m
//  Retrode
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "REAppDelegate.h"
#import "RERetrode.h"
#import "RERetrode_Configuration.h"

#import "REFirmwareUpdater.h"
@implementation REAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[RERetrodeManager sharedManager] startRetrodeSupport];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [[RERetrodeManager sharedManager] stopRetrodeSupport];
}

- (IBAction)logRetrodeDescriptions:(id)sender
{
    for(RERetrode *obj in [[RERetrodeManager sharedManager] connectedRetrodes])
        DLog(@"%@", obj);
}

- (IBAction)unmountRetrodes:(id)sender
{
    for(RERetrode *obj in [[RERetrodeManager sharedManager] connectedRetrodes])
        [obj unmountFilesystem];
}
- (IBAction)mountRetrodes:(id)sender
{
    for(RERetrode *obj in [[RERetrodeManager sharedManager] connectedRetrodes])
        [obj mountFilesystem];
}

- (IBAction)readConfigurations:(id)sender
{
    for(RERetrode *obj in [[RERetrodeManager sharedManager] connectedRetrodes])
        [obj readConfiguration];
}

- (IBAction)writeConfigurations:(id)sender
{
    for(RERetrode *obj in [[RERetrodeManager sharedManager] connectedRetrodes])
        [obj writeConfiguration];
}

- (IBAction)updateAvailableFirmwareVersion:(id)sender
{
    [[REFirmwareUpdater sharedFirmwareUpdater] updateAvailableFirmwareVersionsWithError:nil];
    DLog(@"%@", [[REFirmwareUpdater sharedFirmwareUpdater] availableFirmwareVersions]);
}

@end
