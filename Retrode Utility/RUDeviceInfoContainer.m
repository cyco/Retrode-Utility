//
//  REDeviceInfoContainer.m
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 09.10.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RUDeviceInfoContainer.h"
#import "RUAppDelegate.h"
@interface RUDeviceInfoContainer ()
@property (nonatomic) BOOL draggingActive;
@end
@implementation RUDeviceInfoContainer

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addObserver:self forKeyPath:@"hidden" options:0 context:nil];
    }
    
    return self;
}
- (void)dealloc
{
    [self removeObserver:self forKeyPath:@"hidden"];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor clearColor] setFill];
    NSRectFill(dirtyRect);
    
    if([self draggingActive])
    {
        NSRect rect = NSInsetRect([self bounds], 4, 4);
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:8.0 yRadius:8.0];
        [path setLineWidth:2.0];
        
        [[NSColor colorWithDeviceRed:20.0/255.0 green:95.0/255.0 blue:185.0/255.0 alpha:1.0] setStroke];
        [path stroke];
        
        [[NSColor colorWithDeviceRed:171.0/255.0 green:194.0/255.0 blue:228.0/255.0 alpha:0.3] setFill];
        [path fill];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if(object == self && [keyPath isEqualToString:@"hidden"])
    {
        if(![self isHidden])
            [self registerForDraggedTypes:@[NSPasteboardTypeURL]];
        else
        {
            [self unregisterDraggedTypes];
            [self setDraggingActive:NO];
        }
    }
}
#pragma mark - Dragging -
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    BOOL draggingValid = [self RU_draggingIsValid:sender];
    if(draggingValid)
    {
        [self setDraggingActive:YES];
        return NSDragOperationCopy;
    }
    else
    {
        [self setDraggingActive:NO];
        return NSDragOperationNone;
    }
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSPasteboardTypeURL]) {
        NSURL *fileURL = [NSURL URLFromPasteboard:pboard];
        [[NSNotificationCenter defaultCenter] postNotificationName:kRUCopyFileToRetrodeNotificationName object:fileURL];
    }
    [self setDraggingActive:NO];
    return YES;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
    [self setDraggingActive:NO];
}

#define LogAndReturn(VAL, REASON) return VAL
- (BOOL)RU_draggingIsValid:(id<NSDraggingInfo>)sender
{
    // For dragging to be valid we need a .srm file that is not already on the retrode
    // also the retrode hardware has to be available mounted
    
    RUAppDelegate *appDelegate = (RUAppDelegate*)[NSApp delegate];
    RURetrode     *retrode     = [appDelegate currentRetrode];
    
    if([retrode mountPath] == nil) LogAndReturn(NO, @"not mounted"); // make sure retrode is mounted
    
    NSPasteboard  *pboard  = [sender draggingPasteboard];
    NSURL         *fileURL = [NSURL URLFromPasteboard:pboard];
    if(fileURL == nil) LogAndReturn(NO, @"no url"); // make sure a file was dragged
    
    // make sure file is not already on the retrode
    if([[fileURL path] rangeOfString:[retrode mountPath]].location == 0) LogAndReturn(NO, @"is on retrode");
    
    // make sure file is srm
    if([[fileURL pathExtension] isNotEqualTo:@"srm"]) LogAndReturn(NO, @"not .srm");
    
    LogAndReturn(YES, @"ALL OK");
}

- (void)setDraggingActive:(BOOL)flag
{
    BOOL display = flag != _draggingActive;
    _draggingActive = flag;
    if(display) [self setNeedsDisplay:YES];
}

@end
