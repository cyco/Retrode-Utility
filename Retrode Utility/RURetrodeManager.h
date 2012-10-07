//
//  RURetrodeManager.h
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IOKit/usb/IOUSBLib.h>

extern NSString * const RURetrodesDidConnectNotificationName;

typedef struct RUDeviceData {
    io_object_t				notification;
    IOUSBDeviceInterface	**deviceInterface;
    io_service_t            ioService;
    UInt32					locationID;
}RUDeviceData;

@class RURetrode;
@interface RURetrodeManager : NSObject
+ (RURetrodeManager*)sharedManager;

- (void)startRetrodeSupport;
- (void)stopRetrodeSupport;

- (NSArray*)connectedRetrodes;
@end
