//
//  NSString+RangeAdditions.m
//  Retrode
//
//  Created by Christoph Leimbrock on 29.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "NSString+NSRangeAdditions.h"

@implementation NSString (NSRangeAdditions)
- (NSRange)fullRange
{
    return NSMakeRange(0, [self length]);
}
@end
