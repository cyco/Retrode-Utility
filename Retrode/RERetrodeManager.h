//
//  RERetrodeManager.h
//  Retrode
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IOKit/usb/IOUSBLib.h>

typedef struct REDeviceData {
    io_object_t				notification;
    IOUSBDeviceInterface	**deviceInterface;
    io_service_t            ioService;
    UInt32					locationID;
} REDeviceData;

@class RERetrode;
@interface RERetrodeManager : NSObject
+ (RERetrodeManager*)sharedManager;

- (void)startRetrodeSupport;
- (void)stopRetrodeSupport;

- (NSArray*)connectedRetrodes;
@end
