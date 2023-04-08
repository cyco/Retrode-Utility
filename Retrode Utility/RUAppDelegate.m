//
//  RUAppDelegate.m
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RUAppDelegate.h"
#import "RURetrode.h"
#import "RURetrode_IOLevel.h"
#import "RURetrode_Configuration.h"

#import "RUFirmwareUpdater.h"

#import "NS(Attributed)String+Geometrics.h"
#import <Quartz/Quartz.h>

NSString * const kRUCopyFileToRetrodeNotificationName = @"kRUCopyFileToRetrodeNotificationName";
@interface RUAppDelegate ()
{
    NSMutableData *firmwareUpdateData;
}
@end
@implementation RUAppDelegate
- (id)init
{
    self = [super init];
    if (self != nil)
    {
        [self addObserver:self forKeyPath:@"currentRetrode" options:NSKeyValueObservingOptionNew context:nil];
        [self addObserver:self forKeyPath:@"currentRetrode.deviceVersion" options:0 context:nil];
        RUFirmwareUpdater *sharedFirmwareUpdater = [RUFirmwareUpdater sharedFirmwareUpdater];
        [sharedFirmwareUpdater addObserver:self forKeyPath:@"availableFirmwareVersions" options:0 context:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(retrodesDidConnect:) name:RURetrodesDidConnectNotificationName object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(copyFile:) name:kRUCopyFileToRetrodeNotificationName object:nil];
        
        firmwareUpdateData = [NSMutableData data];
    }
    return self;
}

- (void)dealloc
{
    [self removeObserver:self forKeyPath:@"currentRetrode"];
    [self removeObserver:self forKeyPath:@"currentRetrode.deviceVersion"];
    
    RUFirmwareUpdater *sharedFirmwareUpdater = [RUFirmwareUpdater sharedFirmwareUpdater];
    [sharedFirmwareUpdater removeObserver:self forKeyPath:@"availableFirmwareVersions"];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){ [[RURetrodeManager sharedManager] startRetrodeSupport]; });
    
    [[RUFirmwareUpdater sharedFirmwareUpdater] updateAvailableFirmwareVersionsWithError:nil];
    
    
    NSViewController *viewController = [[NSViewController alloc] initWithNibName:@"fileSelectionViewController" bundle:[NSBundle mainBundle]];
    [self setFileSelectionViewController:viewController];
    [[self fileSelectionViewController] view];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [[RURetrodeManager sharedManager] stopRetrodeSupport];
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

- (IBAction)installCustomFirmware:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setAllowedContentTypes:@[[UTType typeWithFilenameExtension:@"hex"
                                                     conformingToType:UTTypeData]]];
    if([panel runModal] != NSModalResponseOK) {
        [[self firmwareButton] selectItemAtIndex:0];
        [sender setRepresentedObject:nil];
        return;
    }

    NSLog(@"install custom firmware: %@", [panel URL]);
    RUFirmware *firmware = [[RUFirmwareUpdater sharedFirmwareUpdater] makeCustomFirmwareWithURL:panel.URL forRetrode:self.currentRetrode];
    [sender setRepresentedObject:firmware];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self firmwareDrawer] open:self];
        [self installFirmware:sender];
    });
}

- (IBAction)discardConfig:(id)sender
{
    [[self currentRetrode] readConfiguration];
}

- (IBAction)saveConfig:(id)sender
{
    [[self currentRetrode] writeConfiguration];
}

- (IBAction)showOfficialRetrodeManual:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.retrode.com/uploads/Retrode2-Manual-April2012.pdf"]];
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
    
    RURetrode *retrode = [self currentRetrode];
    RUFirmwareUpdater *firmwareUpdater = [RUFirmwareUpdater sharedFirmwareUpdater];
    NSArray *availableFirmwareVersions = [firmwareUpdater availableFirmwareVersions];
    if([retrode deviceVersion] == nil || [availableFirmwareVersions count]==0)
    {
        [[self firmwareButton] setEnabled:NO];
        [[self firmwareButton] selectItemAtIndex:0];
        [[[self firmwareButton] itemAtIndex:0] setEnabled:NO];
    }
    else
    {
        NSArray *suitableFirmwareVersions  = [availableFirmwareVersions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RUFirmware *evaluatedObject, NSDictionary *bindings) {
            return [[evaluatedObject deviceVersion] isEqualTo:[retrode deviceVersion]];
        }]];
        
        [suitableFirmwareVersions enumerateObjectsUsingBlock:^(RUFirmware *obj, NSUInteger idx, BOOL *stop) {
            NSMenuItem *item = [[NSMenuItem alloc] init];
            [item setTitle:[obj version]];
            [item setRepresentedObject:obj];
            [item setEnabled:YES];
            
            [itemMenu addItem:item];
        }];
    }
    [itemMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *customFirmwareItem = [[NSMenuItem alloc] initWithTitle:@"Custom firmware…" action:@selector(installCustomFirmware:) keyEquivalent:@""];
    [itemMenu addItem:customFirmwareItem];

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
        
        RUFirmware *firmware = [[[self firmwareButton] selectedItem] representedObject];
        [[self firmwareProgressIndicator] setDoubleValue:0.0];
        [[self firmwareProgressOperationField] setStringValue:@"Starting..."];
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [[RUFirmwareUpdater sharedFirmwareUpdater] installFirmware:firmware toRetrode:[self currentRetrode] withCallback:^(double progress, id status) {
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
                }
                else if([status isEqualTo:@"Extracting"])
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

- (void)copyFile:(NSNotification*)notification
{
    NSError   *error   = nil;
    NSURL     *fileURL = [notification object];
    RURetrode *retrode = [self currentRetrode];
    NSArray   *availableFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[retrode mountPath] error:&error];
    if(availableFiles == nil)
    {
        [NSApp presentError:error];
        return;
    }
    
    NSString *extension = [fileURL pathExtension];
    NSArray  *filesOfSameType = [availableFiles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [[evaluatedObject pathExtension] isEqualToString:extension];
    }]];
        
    NSString *fileToReplace = nil;
    if([filesOfSameType count] == 0)
    {
        NSString *localizedDescription = [NSString stringWithFormat:@"There are not %@ files on the retrode that you could replace.", extension];
        error = [NSError errorWithDomain:@"RUDomain" code:1000 userInfo:@{ NSLocalizedDescriptionKey : localizedDescription }];
        [NSApp presentError:error];
    }
    else if([filesOfSameType count] == 1 || [filesOfSameType containsObject:[fileURL lastPathComponent]])
    {
        NSString *message = [NSString stringWithFormat:@"Are you sure you want to replace %@ with %@?", [filesOfSameType lastObject], [fileURL lastPathComponent]];
        NSAlert *alert = [NSAlert alertWithMessageText:message defaultButton:@"No" alternateButton:@"Yes" otherButton:@"" informativeTextWithFormat:@"You should be absolutely sure that the file is compatible with the game"];
        if([alert runModal] == NSAlertAlternateReturn)
            fileToReplace = [filesOfSameType lastObject];
    }
    else
    {
        NSString *message = [NSString stringWithFormat:@"Please select the file you want to replace"];
        NSAlert *alert = [NSAlert alertWithMessageText:message defaultButton:@"Cancel" alternateButton:@"Replace" otherButton:@"" informativeTextWithFormat:@"You should be absolutely sure that the file is compatible with the game"];
        [[self fileSelectionViewController] setRepresentedObject:filesOfSameType];
        [alert setAccessoryView:[[self fileSelectionViewController] view]];
        if([alert runModal] == NSAlertAlternateReturn)
        {
            NSIndexSet* selection = (NSIndexSet*)[[self fileSelectionViewController] title];
            fileToReplace = [filesOfSameType objectAtIndex:[selection firstIndex]];
        }
    }
    
    if(fileToReplace)
    {
        NSData *data = [NSData dataWithContentsOfURL:fileURL];
        
        NSString *fullPath = [[retrode mountPath] stringByAppendingPathExtension:fileToReplace];
        [[NSFileManager defaultManager] setAttributes:@{ NSFileImmutable: @(FALSE) } ofItemAtPath:fullPath error:nil];
        if(![data writeToFile:fullPath options:0 error:&error])
        {
            [NSApp presentError:error];
        }
        [[NSFileManager defaultManager] setAttributes:@{ NSFileImmutable: @(YES) } ofItemAtPath:fullPath error:nil];
    }
}
#pragma mark - Notifications and Callbacks -
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if(object==self && [keyPath isEqualToString:@"currentRetrode"])
    {
        RURetrode *newRetrode            = [change objectForKey:NSKeyValueChangeNewKey];
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
            || (object == [RUFirmwareUpdater sharedFirmwareUpdater] && [keyPath isEqualToString:@"availableFirmwareVersions"]))
    {
        [self updateFirmwareSelection];
    }
}

-(void)retrodesDidConnect:(NSNotification*)notification
{
    RURetrodeManager *sharedManager     = [RURetrodeManager sharedManager];
    NSArray          *connectedRetrodes = [sharedManager connectedRetrodes];
    RURetrode        *retrode           = [connectedRetrodes lastObject];
    if([self currentRetrode] == nil)
    {
        [self setCurrentRetrode:retrode];
        [retrode setDelegate:self];
    }
    
    [[self configDrawer]   close:self];
    [[self firmwareDrawer] close:self];
}

#pragma mark - Retrode Delegate -
- (void)retrodeDidConnect:(RURetrode *)retrode
{
    DLog();
}

- (void)retrodeDidDisconnect:(RURetrode *)retrode
{
    DLog();
    [self setCurrentRetrode:nil];
    
    [[self configDrawer]   close:self];
    [[self firmwareDrawer] close:self];
}

- (void)retrodeHardwareDidBecomeAvailable:(RURetrode*)retrode
{
    DLog();
}

- (void)retrodeHardwareDidBecomeUnavailable:(RURetrode*)retrode
{
    DLog();
}

- (void)retrodeDidMount:(RURetrode *)retrode
{
    DLog();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [retrode readConfiguration];
    });
}

- (void)retrodeDidUnmount:(RURetrode *)retrode
{
    DLog();
}
- (void)retrodeDidEnterDFUMode:(RURetrode*)retrode
{
    DLog();
    NSInteger drawerState = [[self firmwareDrawer] state];
    if((drawerState == NSDrawerOpeningState || drawerState == NSDrawerOpenState) && [[self firmwareDFUInstructionsView] isDescendantOf:[self firmwareDrawerView]])
    {
        [self showFirmwareDrawerSubview:[self firmwareProgressView]];
    }
}

- (void)retrodeDidLeaveDFUMode:(RURetrode*)retrode
{
    DLog();
    
    [[self firmwareDrawer] close:self];
    [[self firmwareButton] selectItemAtIndex:0];
}
#pragma mark - NSDrawer Delegate -

- (void)drawerWillOpen:(NSNotification *)notification
{
    NSDrawer *drawer = [notification object];
    if(drawer == [self configDrawer])
        [[self firmwareDrawer] close:self];
    else if(drawer == [self firmwareDrawer])
    {
        [self showFirmwareDrawerSubview:[self firmwareReleaseNotesView]];
        [[self configDrawer] close:self];
    }
    
    if([drawer edge] == NSMaxYEdge)
    {
        NSWindow *drawerWindow = [[drawer contentView] window];
        NSRect  frame        = [drawerWindow frame];
        frame.origin.y -= 53.0;
        [drawerWindow setFrame:frame display:YES animate:YES];
    }
}

- (void)drawerDidOpen:(NSNotification *)notification
{
    NSDrawer *drawer = [notification object];
    if(drawer == [self configDrawer])
        [[self configButton] setState:NSOnState];
    else if(drawer == [self firmwareDrawer])
    {
    }
    
    if([drawer edge] == NSMaxYEdge)
    {
        NSWindow *drawerWindow = [[drawer contentView] window];
        NSRect  frame        = [drawerWindow frame];
        frame.origin.y -= 53.0;
        [drawerWindow setFrame:frame display:YES animate:NO];
    }
}

- (void)drawerDidClose:(NSNotification *)notification
{
    if([notification object] == [self configDrawer])
        [[self configButton] setState:NSControlStateValueOff];
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
#pragma mark - NSURLDownloadDelegate -
- (void)downloadDidBegin:(NSURLDownload *)download
{}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
    
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    
}
@end
