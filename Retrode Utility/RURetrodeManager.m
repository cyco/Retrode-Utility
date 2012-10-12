//
//  RURetrodeManager.m
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RURetrodeManager.h"
#import "RURetrode.h"
#import "RURetrode_IOLevel.h"
#import "RURetrode_ManagerPrivate.h"
#import "RURetrode_Configuration.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <IOKit/IOCFPlugIn.h>

#import <paths.h>
#import <IOKit/IOBSD.h>

NSString * const RURetrodesDidConnectNotificationName = @"RURetrodesDidConnectNotificationName";
@interface RURetrodeManager ()
{
    BOOL retrodeSupportActive;
    NSMutableDictionary     *retrodes;
    
    CFRunLoopRef			runLoop;
    IONotificationPortRef	notificationPort;
    io_iterator_t			matchedRetrode1ItemsIterator, matchedRetrode2ItemsIterator, matchedDFUItemsIterator;
}
BOOL addDevice(void *refCon, io_service_t usbDevice);

- (NSDictionary*)RU_retrode2MatchingCriteria;
- (NSDictionary*)RU_retrode2MatchingCriteriaWithLocationID:(UInt32)locationID;
- (NSDictionary*)RU_dfuMatchingCriteria;
- (NSDictionary*)RU_dfuMatchingCriteriaWithLocationID:(UInt32)locationID;
@end
@implementation RURetrodeManager
+ (RURetrodeManager*)sharedManager
{
    static RURetrodeManager* sharedRetrodeManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedRetrodeManager = [[RURetrodeManager alloc] init];
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
    CFDictionaryRef re1MatchingCriteria = CFBridgingRetain([self RU_retrode1MatchingCriteria]);
    CFDictionaryRef re2MatchingCriteria = CFBridgingRetain([self RU_retrode2MatchingCriteria]);
    CFDictionaryRef dfuMatchingCriteria = CFBridgingRetain([self RU_dfuMatchingCriteria]);
    notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
    CFRunLoopSourceRef runLoopSource = IONotificationPortGetRunLoopSource(notificationPort);
    
    runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);
    
    // Now set up a notification to be called when a device is first matched by I/O Kit.
    error = IOServiceAddMatchingNotification(notificationPort, kIOMatchedNotification, re1MatchingCriteria, DeviceAdded, NULL, &matchedRetrode1ItemsIterator);
    NSAssert(error==noErr, @"Could not register main matching notification");
    error = IOServiceAddMatchingNotification(notificationPort, kIOMatchedNotification, re2MatchingCriteria, DeviceAdded, NULL, &matchedRetrode2ItemsIterator);
    NSAssert(error==noErr, @"Could not register main matching notification");
    error = IOServiceAddMatchingNotification(notificationPort, kIOMatchedNotification, dfuMatchingCriteria, DeviceAdded, NULL, &matchedDFUItemsIterator);
    NSAssert(error==noErr, @"Could not register dfu matching notification");
    
    // Iterate once to get already-present devices and arm the notification
    DeviceAdded(NULL, matchedRetrode1ItemsIterator);
    DeviceAdded(NULL, matchedRetrode2ItemsIterator);
    DeviceAdded(NULL, matchedDFUItemsIterator);
}

- (void)stopRetrodeSupport
{
    DLog(@"Not looking for Retrodes: %s", BOOL_STR(!retrodeSupportActive));
    if(!retrodeSupportActive) return;
    retrodeSupportActive = NO;
    
    [retrodes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        RURetrode    *aRetrode   = obj;
       RUDeviceData *deviceData = [aRetrode deviceData];
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
    
    IOObjectRelease(matchedRetrode1ItemsIterator);
    IOObjectRelease(matchedRetrode2ItemsIterator);
    IOObjectRelease(matchedDFUItemsIterator);
}

- (NSArray*)connectedRetrodes
{
    return [retrodes allValues];
}
#pragma mark - Callbacks
void DeviceNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument)
{
   RUDeviceData *deviceData = (RUDeviceData *)refCon;
    if (messageType == kIOMessageServiceIsTerminated) {
        DLog();
        RURetrodeManager    *self              = [RURetrodeManager sharedManager];
        NSMutableDictionary *retrodes          = self->retrodes;
        NSString            *retrodeIdentifier = [RURetrode generateIdentifierFromDeviceData:deviceData];
        RURetrode           *retrode           = [retrodes objectForKey:retrodeIdentifier];
        
        [retrode setupWithDeviceData:NULL];
        
        if (deviceData->deviceInterface)
            (*deviceData->deviceInterface)->Release(deviceData->deviceInterface);
        IOObjectRelease(deviceData->notification);
        IOObjectRelease(deviceData->ioService);
        free(deviceData);
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, kRUDisconnectDelay * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            RURetrodeManager *self        = [RURetrodeManager sharedManager];
            NSMutableDictionary *retrodes = self->retrodes;
            RURetrode  *retrode           = [retrodes objectForKey:retrodeIdentifier];
            if([retrode deviceData] == NULL)
            {
                // try to recover one last time
                io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, CFBridgingRetain([self RU_retrode2MatchingCriteriaWithLocationID:[retrode locationID]]));
                if(service == 0)
                {
                    service = IOServiceGetMatchingService(kIOMasterPortDefault, CFBridgingRetain([self RU_dfuMatchingCriteriaWithLocationID:[retrode locationID]]));
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
    RURetrodeManager *self = [RURetrodeManager sharedManager];
    BOOL sendNotification = NO;
    io_service_t  usbDevice;
    while ((usbDevice = IOIteratorNext(iterator))) {
        sendNotification = addDevice((__bridge void *)(self), usbDevice);
    }
    
    if(sendNotification)
        [[NSNotificationCenter defaultCenter] postNotificationName:RURetrodesDidConnectNotificationName object:self];
}

BOOL addDevice(void *refCon, io_service_t usbDevice)
{
    BOOL sendNotification = NO;
    RURetrodeManager *self = [RURetrodeManager sharedManager];
    kern_return_t error;
    IOCFPlugInInterface	**plugInInterface = NULL;
   RUDeviceData        *deviceDataRef    = NULL;
    UInt32			    locationID;
    
    // Prepare struct for device specific data
    deviceDataRef = malloc(sizeof(RUDeviceData));
    memset(deviceDataRef, '\0', sizeof(RUDeviceData));
    
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
    NSString *deviceVersion;
    BOOL isDFUDevice;
    if(productID == kRUProductIDVersion1)
        deviceVersion = @"1";
    else if(productID == kRUProductIDVersion2)
        deviceVersion = @"2";
    else if(productID == kRUProductIDVersion2DFU)
        isDFUDevice = YES;
    
    // Register for device removal notification (keeps notification ref in device data)
    error = IOServiceAddInterestNotification(self->notificationPort, usbDevice, kIOGeneralInterest, DeviceNotification, deviceDataRef, &(deviceDataRef->notification));
    assert(error == noErr);
    
    deviceDataRef->ioService = usbDevice;
    
    // Create Retrode objc object
    NSString  *identifier = [RURetrode generateIdentifierFromDeviceData:deviceDataRef];
    RURetrode *retrode    = [self->retrodes objectForKey:identifier];
    if(!retrode && !isDFUDevice)
    {
        DLog(@"create new retrode");
        retrode = [[RURetrode alloc] init];
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
        [retrode setDeviceVersion:deviceVersion];
        DLog(@"found normal device");
    }
    [retrode setupWithDeviceData:deviceDataRef];
    [retrode setDFUMode:isDFUDevice];
    
    return sendNotification;
}
#pragma mark -
- (NSDictionary*)RU_retrode2MatchingCriteria
{
    return [self RU_retrode2MatchingCriteriaWithLocationID:0];
}
- (NSDictionary*)RU_retrode2MatchingCriteriaWithLocationID:(UInt32)locationID
{
    if(locationID == 0)
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kRUVendorID), @kUSBProductID : @(kRUProductIDVersion2) };
    else
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kRUVendorID), @kUSBProductID : @(kRUProductIDVersion2), @kIOLocationMatchKey : @(locationID) };
    
}

- (NSDictionary*)RU_retrode1MatchingCriteria
{
    return [self RU_retrode1MatchingCriteriaWithLocationID:0];
}
- (NSDictionary*)RU_retrode1MatchingCriteriaWithLocationID:(UInt32)locationID
{
    if(locationID == 0)
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kRUVendorID), @kUSBProductID : @(kRUProductIDVersion1) };
    else
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kRUVendorID), @kUSBProductID : @(kRUProductIDVersion1), @kIOLocationMatchKey : @(locationID) };
    
}

- (NSDictionary*)RU_dfuMatchingCriteria
{
    return [self RU_dfuMatchingCriteriaWithLocationID:0];
}

- (NSDictionary*)RU_dfuMatchingCriteriaWithLocationID:(UInt32)locationID
{
    if(locationID == 0)
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kRUVendorIDVersion2DFU), @kUSBProductID : @(kRUProductIDVersion2DFU) };
    else
        return @{ @kIOProviderClassKey : @kIOUSBDeviceClassName, @kUSBVendorID : @(kRUVendorIDVersion2DFU), @kUSBProductID : @(kRUProductIDVersion2DFU), @kIOLocationMatchKey : @(locationID) };
}
@end
