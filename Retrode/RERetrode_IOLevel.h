//
//  RERetrode_Device.h
//  Retrode
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RERetrode.h"
#import "RERetrodeManager.h"

#import <IOKit/IOKitLib.h>
#import <DiskArbitration/DiskArbitration.h>
@interface RERetrode ()
@property UInt32 locationID;
@property (nonatomic) BOOL DFUMode;
@property REDeviceData *deviceData;

- (void)setupWithDeviceData:(REDeviceData*)deviceData;
+ (NSString*)generateIdentifierFromDeviceData:(REDeviceData*)deviceData;
- (NSDictionary*)diskDescription;
@end
