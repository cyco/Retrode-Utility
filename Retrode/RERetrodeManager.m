//
//  RERetrodeManager.m
//  Retrode
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RERetrodeManager.h"
#import "RERetrode.h"
#import "RERetrode_IOLevel.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <IOKit/IOCFPlugIn.h>

#import <paths.h>
#import <IOKit/IOBSD.h>

const int32_t retrode2_vendor_id  = 0x0403;
const int32_t retrode2_product_id = 0x97c1;
@interface RERetrodeManager ()
{
    BOOL retrodeSupportActive;
    NSMutableDictionary     *retrodes;

    CFRunLoopRef			runLoop;
    IONotificationPortRef	notificationPort;
    io_iterator_t			matchedItemsIterator;
}
@end
@implementation RERetrodeManager
+ (RERetrodeManager*)sharedManager
{
    static RERetrodeManager* sharedRetrodeManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedRetrodeManager = [[RERetrodeManager alloc] init];
    });
    return sharedRetrodeManager;
}

- (id)init
{
    self = [super init];
    if(self != nil)
    {
        retrodes = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc
{
    [self stopRetrodeSupport];
}
#pragma mark -
- (void)startRetrodeSupport
{
    DLog(@"Already looking for Retrodes: %s", BOOL_STR(retrodeSupportActive));
    if(retrodeSupportActive) return;
    retrodeSupportActive = YES;
    
    kern_return_t error;
    
    // Setup dictionary to match USB device
    CFDictionaryRef matchingCriteria = CFBridgingRetain(@{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(retrode2_vendor_id), @kUSBProductID : @(retrode2_product_id) });
    
    notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
    CFRunLoopSourceRef runLoopSource = IONotificationPortGetRunLoopSource(notificationPort);
    
    runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);
    
    // Now set up a notification to be called when a device is first matched by I/O Kit.
    error = IOServiceAddMatchingNotification(notificationPort, kIOFirstMatchNotification, matchingCriteria, DeviceAdded, NULL, &matchedItemsIterator);
    NSAssert(error==noErr, @"Could not register matching notification");
    
    // Iterate once to get already-present devices and arm the notification
    DeviceAdded(NULL, matchedItemsIterator);
}

- (void)stopRetrodeSupport
{
    DLog(@"Not looking for Retrodes: %s", BOOL_STR(!retrodeSupportActive));
    if(!retrodeSupportActive) return;
    retrodeSupportActive = NO;
    
    [retrodes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        RERetrode    *aRetrode   = obj;
        REDeviceData *deviceData = [aRetrode deviceData];
        [aRetrode setupWithDeviceData:NULL];
        if(deviceData != NULL)
        {
            if (deviceData->deviceInterface)
                (*deviceData->deviceInterface)->Release(deviceData->deviceInterface);
            deviceData->deviceInterface = NULL;
            IOObjectRelease(deviceData->notification);
            free(deviceData);
        }
    }];
    [retrodes removeAllObjects];
   
    IONotificationPortDestroy(notificationPort);
    notificationPort = NULL;
    runLoop = NULL;
    
    IOObjectRelease(matchedItemsIterator);
}

- (NSArray*)connectedRetrodes
{
    return [retrodes allValues];
}
#pragma mark - Callbacks
void DeviceNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument)
{
    REDeviceData *deviceData = (REDeviceData *)refCon;
    if (messageType == kIOMessageServiceIsTerminated) {
        RERetrodeManager *self              = [RERetrodeManager sharedManager];
        NSString         *retrodeIdentifier = [RERetrode generateIdentifierFromDeviceData:deviceData];
        RERetrode        *retrode           = [self->retrodes objectForKey:retrodeIdentifier];
        
        [retrode setupWithDeviceData:NULL];
        
        if (deviceData->deviceInterface)
            (*deviceData->deviceInterface)->Release(deviceData->deviceInterface);
        IOObjectRelease(deviceData->notification);
        IOObjectRelease(deviceData->ioService);
        free(deviceData);
    }
}

void DeviceAdded(void *refCon, io_iterator_t iterator)
{
    RERetrodeManager *self = [RERetrodeManager sharedManager];
    
    kern_return_t error;
    io_service_t  usbDevice;

    while ((usbDevice = IOIteratorNext(iterator))) {
        IOCFPlugInInterface	**plugInInterface = NULL;
        REDeviceData        *deviceDataRef    = NULL;
        UInt32			    locationID;
        
        // Prepare struct for device specific data
        deviceDataRef = malloc(sizeof(REDeviceData));
        memset(deviceDataRef, '\0', sizeof(REDeviceData));
        
        // Get Interface Plugin
        SInt32 score; // unused
        error = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
        assert(error == noErr && plugInInterface!=NULL);
        
        // Get USB Device Interface
        error = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*) &deviceDataRef->deviceInterface);
        assert(error == noErr);
        
        IODestroyPlugInInterface(plugInInterface);

        // Get USB Location ID
        error = (*deviceDataRef->deviceInterface)->GetLocationID(deviceDataRef->deviceInterface, &locationID);
        assert(error == noErr);
        deviceDataRef->locationID = locationID;

        // Register for device removal notification (keeps notification ref in device data)
        error = IOServiceAddInterestNotification(self->notificationPort, usbDevice, kIOGeneralInterest, DeviceNotification, deviceDataRef, &(deviceDataRef->notification));
        assert(error == noErr);

        deviceDataRef->ioService = usbDevice;
        
        // Create Retrode objc object
        NSString  *identifier = [RERetrode generateIdentifierFromDeviceData:deviceDataRef];
        RERetrode *retrode    = [self->retrodes objectForKey:identifier];
        if(!retrode)
        {
            retrode = [[RERetrode alloc] init];
            [self->retrodes setObject:retrode forKey:identifier];
        }
        [retrode setupWithDeviceData:deviceDataRef];
    }
}
@end
