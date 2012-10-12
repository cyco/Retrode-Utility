//
//  RUImageView.m
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 10.10.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RUImageView.h"

@implementation RUImageView
- (void)awakeFromNib
{
    [super awakeFromNib];
    [self unregisterDraggedTypes];
}
- (BOOL)becomeFirstResponder
{
    return NO;
}

- (BOOL)canBecomeKeyView
{
    return NO;
}
- (BOOL)mouseDownCanMoveWindow
{
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return NO;
}
@end
