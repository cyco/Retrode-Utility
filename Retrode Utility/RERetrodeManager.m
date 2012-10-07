//
//  RERetrodeManager.m
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RERetrodeManager.h"
#import "RERetrode.h"
#import "RERetrode_IOLevel.h"
#import "RERetrode_ManagerPrivate.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <IOKit/IOCFPlugIn.h>

#import <paths.h>
#import <IOKit/IOBSD.h>

NSString * const RERetrodesDidConnectNotificationName = @"RERetrodesDidConnectNotificationName";
@interface RERetrodeManager ()
{
    BOOL retrodeSupportActive;
    NSMutableDictionary     *retrodes;
    
    CFRunLoopRef			runLoop;
    IONotificationPortRef	notificationPort;
    io_iterator_t			matchedItemsIterator, matchedDFUItemsIterator;
}
BOOL addDevice(void *refCon, io_service_t usbDevice);

- (NSDictionary*)RE_mainMatchingCriteria;
- (NSDictionary*)RE_mainMatchingCriteriaWithLocationID:(UInt32)locationID;
- (NSDictionary*)RE_dfuMatchingCriteria;
- (NSDictionary*)RE_dfuMatchingCriteriaWithLocationID:(UInt32)locationID;
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
    CFDictionaryRef mainMatchingCriteria = CFBridgingRetain([self RE_mainMatchingCriteria]);
    CFDictionaryRef dfuMatchingCriteria = CFBridgingRetain([self RE_dfuMatchingCriteria]);
    notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
    CFRunLoopSourceRef runLoopSource = IONotificationPortGetRunLoopSource(notificationPort);
    
    runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);
    
    // Now set up a notification to be called when a device is first matched by I/O Kit.
    error = IOServiceAddMatchingNotification(notificationPort, kIOMatchedNotification, mainMatchingCriteria, DeviceAdded, NULL, &matchedItemsIterator);
    NSAssert(error==noErr, @"Could not register main matching notification");
    error = IOServiceAddMatchingNotification(notificationPort, kIOMatchedNotification, dfuMatchingCriteria, DeviceAdded, NULL, &matchedDFUItemsIterator);
    NSAssert(error==noErr, @"Could not register dfu matching notification");
    
    // Iterate once to get already-present devices and arm the notification
    DeviceAdded(NULL, matchedItemsIterator);
    DeviceAdded(NULL, matchedDFUItemsIterator);
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
    IOObjectRelease(matchedDFUItemsIterator);
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
        DLog();
        RERetrodeManager    *self              = [RERetrodeManager sharedManager];
        NSMutableDictionary *retrodes          = self->retrodes;
        NSString            *retrodeIdentifier = [RERetrode generateIdentifierFromDeviceData:deviceData];
        RERetrode           *retrode           = [retrodes objectForKey:retrodeIdentifier];
        
        [retrode setupWithDeviceData:NULL];
        
        if (deviceData->deviceInterface)
            (*deviceData->deviceInterface)->Release(deviceData->deviceInterface);
        IOObjectRelease(deviceData->notification);
        IOObjectRelease(deviceData->ioService);
        free(deviceData);
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, kREDisconnectDelay * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            RERetrodeManager *self        = [RERetrodeManager sharedManager];
            NSMutableDictionary *retrodes = self->retrodes;
            RERetrode  *retrode           = [retrodes objectForKey:retrodeIdentifier];
            if([retrode deviceData] == NULL)
            {
                // try to recover one last time
                io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, CFBridgingRetain([self RE_mainMatchingCriteriaWithLocationID:[retrode locationID]]));
                if(service == 0)
                {
                    service = IOServiceGetMatchingService(kIOMasterPortDefault, CFBridgingRetain([self RE_dfuMatchingCriteriaWithLocationID:[retrode locationID]]));
                }
                if(service == 0)
                {
                    [retrode disconnect];
                    [retrodes removeObjectForKey:retrodeIdentifier];
                }
                else
                    addDevice((__bridge void *)(self), service);
            }
        });
    }
}

void DeviceAdded(void *refCon, io_iterator_t iterator)
{
    RERetrodeManager *self = [RERetrodeManager sharedManager];
    BOOL sendNotification = NO;
    io_service_t  usbDevice;
    while ((usbDevice = IOIteratorNext(iterator))) {
        sendNotification = addDevice((__bridge void *)(self), usbDevice);
    }
    
    if(sendNotification)
        [[NSNotificationCenter defaultCenter] postNotificationName:RERetrodesDidConnectNotificationName object:self];
}

BOOL addDevice(void *refCon, io_service_t usbDevice)
{
    BOOL sendNotification = NO;
    RERetrodeManager *self = [RERetrodeManager sharedManager];
    kern_return_t error;
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
    
    UInt16 productID;
    error = (*deviceDataRef->deviceInterface)->GetDeviceProduct(deviceDataRef->deviceInterface, &productID);
    assert(error == noErr);
    BOOL isDFUDevice = (productID == kREProductIDVersion2DFU);
    
    // Register for device removal notification (keeps notification ref in device data)
    error = IOServiceAddInterestNotification(self->notificationPort, usbDevice, kIOGeneralInterest, DeviceNotification, deviceDataRef, &(deviceDataRef->notification));
    assert(error == noErr);
    
    deviceDataRef->ioService = usbDevice;
    
    // Create Retrode objc object
    NSString  *identifier = [RERetrode generateIdentifierFromDeviceData:deviceDataRef];
    RERetrode *retrode    = [self->retrodes objectForKey:identifier];
    if(!retrode && !isDFUDevice)
    {
        DLog(@"create new retrode");
        retrode = [[RERetrode alloc] init];
        [self->retrodes setObject:retrode forKey:identifier];
        sendNotification = YES;
    }
    else if(!retrode && isDFUDevice)
    {
        DLog(@"Ignoring DFU device because we can't be sure that it's a retrode");
        if (deviceDataRef->deviceInterface)
            (*deviceDataRef->deviceInterface)->Release(deviceDataRef->deviceInterface);
        IOObjectRelease(deviceDataRef->notification);
        IOObjectRelease(deviceDataRef->ioService);
        free(deviceDataRef);
        return sendNotification;
    }
    
    if(isDFUDevice)
    {
        DLog(@"found dfu device");
    } else {
        DLog(@"found normal device");
    }
    [retrode setupWithDeviceData:deviceDataRef];
    [retrode setDFUMode:isDFUDevice];
    
    return sendNotification;
}
#pragma mark -
- (NSDictionary*)RE_mainMatchingCriteria
{
    return [self RE_mainMatchingCriteriaWithLocationID:0];
}
- (NSDictionary*)RE_mainMatchingCriteriaWithLocationID:(UInt32)locationID
{
    if(locationID == 0)
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kREVendorIDVersion2), @kUSBProductID : @(kREProductIDVersion2) };
    else
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kREVendorIDVersion2), @kUSBProductID : @(kREProductIDVersion2), @kIOLocationMatchKey : @(locationID) };
    
}

- (NSDictionary*)RE_dfuMatchingCriteria
{
    return [self RE_dfuMatchingCriteriaWithLocationID:0];
}

- (NSDictionary*)RE_dfuMatchingCriteriaWithLocationID:(UInt32)locationID
{
    if(locationID == 0)
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kREVendorIDVersion2DFU), @kUSBProductID : @(kREProductIDVersion2DFU) };
    else
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kREVendorIDVersion2DFU), @kUSBProductID : @(kREProductIDVersion2DFU), @kIOLocationMatchKey : @(locationID) };
}
@end
