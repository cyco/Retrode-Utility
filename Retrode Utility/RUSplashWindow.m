//
//  RUSplashWindow.m
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 05.10.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RUSplashWindow.h"

@interface RUSplashWindowContentView : NSView
@end
@implementation RUSplashWindow

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)windowStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)deferCreation
{
    contentRect.size = (NSSize){469, 178};
    
    self = [super initWithContentRect:contentRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    
    if(self != nil)
    {
        [self setBackgroundColor:[NSColor clearColor]];
        [self setAlphaValue:1.0];
        [self setOpaque:NO];
        [self setHasShadow:NO];
        [self setMovableByWindowBackground:YES];
    }
    
    return self;
}

+ (NSRect)contentRectForFrameRect:(NSRect)fRect styleMask:(NSWindowStyleMask)aStyle
{
    return fRect;
}

+ (NSRect)frameRectForContentRect:(NSRect)cRect styleMask:(NSWindowStyleMask)aStyle
{
    return cRect;
}

- (NSRect)contentRectForFrameRect:(NSRect)frameRect
{
    return frameRect;
}

- (NSRect)frameRectForContentRect:(NSRect)contentRect
{
    return contentRect;
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return YES;
}

#pragma mark -
- (void)expand:(id)sender
{
    DLog();
    float newHeight = 278.0;
    NSRect frame = [self frame];
    frame.origin.y -= (newHeight-frame.size.height)/2;
    frame.size.height = newHeight;
    [self setFrame:frame display:YES animate:YES];
}

- (void)colapse:(id)sender
{
    DLog();
    float newHeight = 178.0;
    NSRect frame = [self frame];
    frame.origin.y -= (newHeight-frame.size.height)/2;
    frame.size.height = newHeight;
    [self setFrame:frame display:YES animate:YES];
}
@end

@implementation RUSplashWindowContentView
- (BOOL)canBecomeKeyView
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor clearColor] setFill];
    NSRectFillUsingOperation([self bounds], NSCompositingOperationClear);
    NSRect    backgroundRect = NSMakeRect(0, 0, 400, [self bounds].size.height-53);
    NSBezierPath *bezierPath = [NSBezierPath bezierPathWithRoundedRect:backgroundRect xRadius:10.0 yRadius:10.0];
    
    NSColor      *startColor = [NSColor colorWithDeviceWhite:0.90 alpha:1.0];
    NSColor      *endColor   = [NSColor colorWithDeviceWhite:0.60 alpha:1.0];
    NSGradient   *gradient   = [[NSGradient alloc] initWithColors:@[startColor, endColor]];
    [gradient drawInBezierPath:bezierPath angle:270.0];
}

@end
