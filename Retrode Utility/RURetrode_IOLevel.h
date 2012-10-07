//
//  RURetrode_Device.h
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RURetrode.h"
#import "RURetrodeManager.h"

#import <IOKit/IOKitLib.h>
#import <DiskArbitration/DiskArbitration.h>
@interface RURetrode ()
@property UInt32 locationID;
@property (nonatomic) BOOL DFUMode;
@property RUDeviceData *deviceData;

- (void)setupWithDeviceData:(RUDeviceData*)deviceData;
+ (NSString*)generateIdentifierFromDeviceData:(RUDeviceData*)deviceData;
- (NSDictionary*)diskDescription;
@end
