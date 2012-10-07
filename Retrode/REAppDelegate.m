//
//  REAppDelegate.m
//  Retrode
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "REAppDelegate.h"
#import "RERetrode.h"
#import "RERetrode_IOLevel.h"
#import "RERetrode_Configuration.h"

#import "REFirmwareUpdater.h"

#import "NS(Attributed)String+Geometrics.h"
#import <Quartz/Quartz.h>
@implementation REAppDelegate

- (id)init
{
    self = [super init];
    if (self != nil)
    {
        [self addObserver:self forKeyPath:@"currentRetrode" options:NSKeyValueObservingOptionNew context:nil];
        [self addObserver:self forKeyPath:@"currentRetrode.deviceVersion" options:0 context:nil];
        REFirmwareUpdater *sharedFirmwareUpdater = [REFirmwareUpdater sharedFirmwareUpdater];
        [sharedFirmwareUpdater addObserver:self forKeyPath:@"availableFirmwareVersions" options:0 context:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(retrodesDidConnect:) name:RERetrodesDidConnectNotificationName object:nil];
    }
    return self;
}

- (void)dealloc
{
    [self removeObserver:self forKeyPath:@"currentRetrode"];
    [self removeObserver:self forKeyPath:@"currentRetrode.deviceVersion"];
    
    REFirmwareUpdater *sharedFirmwareUpdater = [REFirmwareUpdater sharedFirmwareUpdater];
    [sharedFirmwareUpdater removeObserver:self forKeyPath:@"availableFirmwareVersions"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){ [[RERetrodeManager sharedManager] startRetrodeSupport]; });
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error  = nil;
        BOOL    success = [[REFirmwareUpdater sharedFirmwareUpdater] updateAvailableFirmwareVersionsWithError:&error];
        if(!success)
            [NSApp presentError:error];
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [[RERetrodeManager sharedManager] stopRetrodeSupport];
}
#pragma mark - User Interface -
- (IBAction)firmwareButtonAction:(id)sender
{
    if([[[[self firmwareButton] selectedItem] title] isEqualToString:@"Select Firmware"])
        [[self firmwareDrawer] close:self];
    else
        [[self firmwareDrawer] open:self];
    
    [[self releaseNotesTableView] reloadData];
}
- (IBAction)installFirmware:(id)sender
{
    if([[self currentRetrode] DFUMode])
        [self showFirmwareDrawerSubview:[self firmwareProgressView]];
    else
        [self showFirmwareDrawerSubview:[self firmwareDFUInstructionsView]];
}

- (IBAction)discardConfig:(id)sender
{
    [[self currentRetrode] readConfiguration];
}

- (IBAction)saveConfig:(id)sender
{
    [[self currentRetrode] writeConfiguration];
}
#pragma mark - Managing UI -
- (void)updateFirmwareSelection
{
    NSString *selectedTitle = [[[self firmwareButton] selectedItem] title];
    
    [[self firmwareButton] removeAllItems];
    NSMenu *itemMenu = [[self firmwareButton] menu];
    NSMenuItem *noSelection = [[NSMenuItem alloc] init];
    [noSelection setTitle:@"Select Firmware"];
    [noSelection setEnabled:YES];
    [itemMenu addItem:noSelection];
    [itemMenu addItem:[NSMenuItem separatorItem]];
    
    RERetrode *retrode = [self currentRetrode];
    REFirmwareUpdater *firmwareUpdater = [REFirmwareUpdater sharedFirmwareUpdater];
    NSArray *availableFirmwareVersions = [firmwareUpdater availableFirmwareVersions];
    if([retrode deviceVersion] == nil || [availableFirmwareVersions count]==0)
    {
        [[self firmwareButton] setEnabled:NO];
        [[self firmwareButton] selectItemAtIndex:0];
        [[[self firmwareButton] itemAtIndex:0] setEnabled:NO];
        return;
    }
    NSArray *suitableFirmwareVersions  = [availableFirmwareVersions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(REFirmware *evaluatedObject, NSDictionary *bindings) {
        return [[evaluatedObject deviceVersion] isEqualTo:[retrode deviceVersion]];
    }]];
    
    [suitableFirmwareVersions enumerateObjectsUsingBlock:^(REFirmware *obj, NSUInteger idx, BOOL *stop) {
        NSMenuItem *item = [[NSMenuItem alloc] init];
        [item setTitle:[obj version]];
        [item setRepresentedObject:obj];
        [item setEnabled:YES];
        
        [itemMenu addItem:item];
    }];
    
    [[self firmwareButton] selectItemWithTitle:selectedTitle];
    if([[self firmwareButton] selectedItem] == nil)
    {
        [[self firmwareButton] selectItemAtIndex:0];
    }
    [[self firmwareButton] setEnabled:YES];
}

- (void)showFirmwareDrawerSubview:(NSView*)view
{
    if(view != [self firmwareReleaseNotesView])
    {
        DLog();
        CATransition *transition = [CATransition animation];
        [transition setType:kCATransitionPush];
        [transition setSubtype:kCATransitionFromRight];
        [transition setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];
        [transition setDuration:2.0];
        [[self firmwareDrawerView] setAnimations:@{ @"subviews" : transition }];
    }
    
    if(view==[self firmwareProgressView])
    {
        if([self firmwareUpdateInProgress] != NO)
            return;
        [self setFirmwareUpdateInProgress:YES];
        
        REFirmware *firmware = [[[self firmwareButton] selectedItem] representedObject];
        [[self firmwareProgressIndicator] setDoubleValue:0.0];
        [[self firmwareProgressOperationField] setStringValue:@"Starting..."];
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [[REFirmwareUpdater sharedFirmwareUpdater] installFirmware:firmware toRetrode:[self currentRetrode] withCallback:^(double progress, id status) {
                if([status isKindOfClass:[NSString class]])
                {
                    [[self firmwareProgressOperationField] setStringValue:status];
                }
                else if([status isKindOfClass:[NSError class]])
                {
                    [[self firmwareFailReasonField] setStringValue:[status localizedDescription]?:@""];
                    [self showFirmwareDrawerSubview:[self firmwareFailView]];
                    return;
                }
                
                if([status isEqualTo:@"Downloading"])
                {
                    [[self firmwareProgressIndicator] setDoubleValue:progress/3.0];
                } else if([status isEqualTo:@"Extracting"])
                {
                    [[self firmwareProgressIndicator] setDoubleValue:1/3.0+progress/3.0];
                } else
                {
                    [[self firmwareProgressIndicator] setDoubleValue:2/3.0+progress/3.0];
                }
                
                if([status isEqualTo:@"Done"])
                {
                    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC);
                    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                        [self showFirmwareDrawerSubview:[self firmwareFinishedView]];
                        [self setFirmwareUpdateInProgress:NO];
                    });
                }
            }];
        });
    }
    else if(view == [self firmwareFinishedView])
    {
        [self setFirmwareUpdateInProgress:NO];
    }
    
    if([[[self firmwareDrawerView] subviews] count] == 0)
        [[[self firmwareDrawerView] animator] addSubview:view];
    else
        [[[self firmwareDrawerView] animator] replaceSubview:[[[self firmwareDrawerView] subviews] lastObject] with:view];
}

#pragma mark - Notifications and Callbacks -
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if(object==self && [keyPath isEqualToString:@"currentRetrode"])
    {
        RERetrode *newRetrode            = [change objectForKey:NSKeyValueChangeNewKey];
        BOOL      showControls           = newRetrode != nil && [newRetrode isNotEqualTo:[NSNull null]];
        NSView    *controlsContainer     = [[self configButton] superview];
        NSView    *instructionsContainer = [self instructionsContainer];
        NSView    *deviceInfoContainer   = [self deviceInfoContainer];
        
        [controlsContainer setHidden:NO];
        [instructionsContainer setHidden:NO];
        [deviceInfoContainer setHidden:NO];
        
        NSPoint newInstructionsOrigin;
        float   newControlsAlpha;
        if(showControls)
        {
            newControlsAlpha = 1.0;
            newInstructionsOrigin = (NSPoint){-1.0*[instructionsContainer frame].size.width, 0};
        }
        else
        {
            newControlsAlpha = 0.0;
            newInstructionsOrigin = (NSPoint){0, 0};
        }
        
        [NSAnimationContext beginGrouping];
        [[instructionsContainer animator] setFrameOrigin:newInstructionsOrigin];
        [[controlsContainer animator] setAlphaValue:newControlsAlpha];
        [[deviceInfoContainer animator] setAlphaValue:newControlsAlpha];
        void(^callback)();
        if(showControls)
            callback = ^{ [instructionsContainer setHidden:YES]; };
        else
            callback = ^{
                [controlsContainer   setHidden:YES];
                [deviceInfoContainer setHidden:YES];
            };
        [NSAnimationContext endGrouping];
    }
    else if((object == self && [keyPath isEqualToString:@"currentRetrode.deviceVersion"])
            || (object == [REFirmwareUpdater sharedFirmwareUpdater] && [keyPath isEqualToString:@"availableFirmwareVersions"]))
    {
        [self updateFirmwareSelection];
    }
}

-(void)retrodesDidConnect:(NSNotification*)notification
{
    RERetrodeManager *sharedManager     = [RERetrodeManager sharedManager];
    NSArray          *connectedRetrodes = [sharedManager connectedRetrodes];
    RERetrode        *retrode           = [connectedRetrodes lastObject];
    if([self currentRetrode] == nil)
    {
        [self setCurrentRetrode:retrode];
        [retrode setDelegate:self];
    }
    
    [[self configDrawer]   close:self];
    [[self firmwareDrawer] close:self];
}

#pragma mark - Retrode Delegate -
- (void)retrodeDidConnect:(RERetrode *)retrode
{
    DLog();
}

- (void)retrodeDidDisconnect:(RERetrode *)retrode
{
    DLog();
    [self setCurrentRetrode:nil];
    
    [[self configDrawer]   close:self];
    [[self firmwareDrawer] close:self];
}

- (void)retrodeHardwareDidBecomeAvailable:(RERetrode*)retrode
{
    DLog();
}

- (void)retrodeHardwareDidBecomeUnavailable:(RERetrode*)retrode
{
    DLog();
}

- (void)retrodeDidMount:(RERetrode *)retrode
{
    DLog();
    [retrode readConfiguration];
}

- (void)retrodeDidUnmount:(RERetrode *)retrode
{
    DLog();
}
- (void)retrodeDidEnterDFUMode:(RERetrode*)retrode
{
    DLog();
    NSInteger drawerState = [[self firmwareDrawer] state];
    if((drawerState == NSDrawerOpeningState || drawerState == NSDrawerOpenState) && [[self firmwareDFUInstructionsView] isDescendantOf:[self firmwareDrawerView]])
    {
        [self showFirmwareDrawerSubview:[self firmwareProgressView]];
    }
}

- (void)retrodeDidLeaveDFUMode:(RERetrode*)retrode
{
    DLog();
    
    [[self firmwareDrawer] close:self];
    [[self firmwareButton] selectItemAtIndex:0];
}
#pragma mark - NSDrawer Delegate -

- (void)drawerWillOpen:(NSNotification *)notification
{
    if([notification object] == [self configDrawer])
        [[self firmwareDrawer] close:self];
    else if([notification object] == [self firmwareDrawer])
    {
        [self showFirmwareDrawerSubview:[self firmwareReleaseNotesView]];
        [[self configDrawer] close:self];
    }
}

- (void)drawerDidOpen:(NSNotification *)notification
{
    if([notification object] == [self configDrawer])
        [[self configButton] setState:NSOnState];
    else if([notification object] == [self firmwareDrawer])
    {
    }
}

- (void)drawerDidClose:(NSNotification *)notification
{
    if([notification object] == [self configDrawer])
        [[self configButton] setState:NSOffState];
    else if([notification object] == [self firmwareDrawer])
    {
        [[self firmwareButton] selectItemAtIndex:0];
    }
}

#pragma mark - NSTableView DataSource -
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [[[[[self firmwareButton] selectedItem] representedObject] releaseNotes] count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSTableColumn *column = [[tableView tableColumns] lastObject];
    if(column == tableColumn)
    {
        NSArray *notes = [[[[self firmwareButton] selectedItem] representedObject] releaseNotes];
        if(row < [notes count]) return [notes objectAtIndex:row];
        else return @"";
    }
    return @" -\n";
}
#pragma mark - NSTableView Delegate -
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    NSTableColumn *column = [[tableView tableColumns] lastObject];
    
    NSString *value = [self tableView:tableView objectValueForTableColumn:column row:row];
    NSTextFieldCell *cell = [column dataCellForRow:row];
    NSDictionary *attributes = @{ NSFontAttributeName : [cell font] };
    
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:value attributes:attributes];
    CGFloat height = [attributedString heightForWidth:[tableView frame].size.width];
    return fmax(height+19.0-((int)height%19),19.0);
}
@end

