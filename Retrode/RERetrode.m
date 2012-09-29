//
//  RERetrode.m
//  Retrode
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RERetrode.h"
#import "RERetrode_IOLevel.h"
#import "RERetrode_Configuration.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/IOKitKeys.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOBSD.h>

#import <paths.h>
#import <DiskArbitration/DiskArbitration.h>

#import "NSString+NSRangeAdditions.h"

#define IfNotConnectedReturn(__RETURN_VALUE__) if([self deviceData] == NULL) return __RETURN_VALUE__;

#pragma mark Retrode Specific Constants
#define kREConfigurationEncoding NSASCIIStringEncoding
#define kREConfigurationLineSeparator @"\r\n"
#define kREConfigurationFileName @"RETRODE.CFG"

#pragma mark Error Constants
NSString * const kREDiskNotMounted = @"Not Mounted";
NSString * const kRENoBSDDevice    = @"No BSD device";

@interface RERetrode ()
{
    DASessionRef daSession;
}
@property (readwrite, strong) NSString *identifier;
@end

@implementation RERetrode
- (id)init
{
    self = [super init];
    if (self) {
        DLog(@"");
    }
    return self;
}

- (void)dealloc
{
    DLog(@"");
    // perform cleanup, eventhough this should have already been done by RetrodeManager
    [self setupWithDeviceData:NULL];
}

- (NSString*)description
{
    unsigned long address = (unsigned long)self;
    UInt32 locationID = [self locationID];
    NSString *bsdName = [self bsdDeviceName];
    NSString *firmwareVersion = [self firmwareVersion];
    NSString *mountLocation = (NSString*)[self mountPath];
    
    return [NSString stringWithFormat:@"<Retrode: 0x%lx> Firmware: <%@> Location ID: <0x%0x> DADisk available: <%s>, BSD name: <%@>, mounted: <%@>", address, firmwareVersion, locationID, BOOL_STR([self diskDescription]!=nil), bsdName, mountLocation];
}
#pragma mark - Configuration -
- (NSString*)configurationFilePath
{
    NSString *mountPath = [self mountPath];
    if(mountPath == kREDiskNotMounted || mountPath == kRENoBSDDevice)
        return mountPath;
    return [mountPath stringByAppendingPathComponent:kREConfigurationFileName];
}

- (void)readConfiguration
{
    NSError   *error                 = nil;
    NSString  *configurationFilePath = [self configurationFilePath];
    NSData    *configFileData        = [NSData dataWithContentsOfFile:configurationFilePath options:NSDataReadingUncached error:&error];
    if(configFileData == nil)
    {
        DLog(@"%@", error);
        return;
    }
    
    NSString  *configFile = [[NSString alloc] initWithData:configFileData encoding:kREConfigurationEncoding];
    NSArray   *lines      = [configFile componentsSeparatedByString:kREConfigurationLineSeparator];

    // Read firmware version from first line
    NSString * firmwareLine         = [lines objectAtIndex:0];
    NSString * const versionPattern = @"(?<=Retrode\\s)\\d*\\.\\d+\\w*(\\s\\w+)?";
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:versionPattern options:0 error:&error];
    NSArray *matches = [expression matchesInString:firmwareLine options:0 range:[firmwareLine fullRange]];
    if([matches count] != 1)
    {
        // TODO: Create proper error
        DLog(@"Unkown Firmware Version, that's a very bad sign");
        return;
    }
    NSTextCheckingResult *versionMatch = [matches lastObject];
    NSString *firmwareVersion          = [firmwareLine substringWithRange:[versionMatch range]];
     // Convert early firmware version that start with .xx to 0.xx
    if([firmwareVersion characterAtIndex:0] == '.')
        firmwareVersion = [NSString stringWithFormat:@"0%@", firmwareVersion];
    [self setFirmwareVersion:firmwareVersion];
    
    NSMutableArray      *configEnries = [NSMutableArray arrayWithCapacity:[lines count]];
    NSMutableDictionary *configValues = [NSMutableDictionary dictionaryWithCapacity:[lines count]];
    
    // Read configuration line by line
    NSString * const keyPattern   = @"(?<=\\[)\\w+(?=]\\s+)";
    NSString * const valuePattern = @"[^\\s;]+";
    
    for(NSString *line in lines)
    {
        NSRegularExpression  *keyExpression = [NSRegularExpression regularExpressionWithPattern:keyPattern options:0 error:nil];
        NSTextCheckingResult *keyMatch      = [keyExpression firstMatchInString:line options:0 range:[line fullRange]];
        if(keyMatch)
        {
            // Calculate range of line without key (and without ']' that comes after the key)
            NSRange keyRange   = [keyMatch range];
            NSRange valueRange = [line fullRange];
            valueRange.location += NSMaxRange(keyRange) + 1;
            valueRange.length   -= NSMaxRange(keyRange) + 1;
            
            NSRegularExpression  *valueExpression = [NSRegularExpression regularExpressionWithPattern:valuePattern options:0 error:nil];
            NSTextCheckingResult *valueMatch      = [valueExpression firstMatchInString:line options:0 range:valueRange];
            if(valueMatch)
            {
                NSString *key              = [line substringWithRange:[keyMatch range]];
                id       value             = [line substringWithRange:[valueMatch range]];
                NSString *linePlaceholder  = [line stringByReplacingCharactersInRange:[valueMatch range] withString:@"%@"];
                
                // Try to get an Integer value if that makes sense
                int intValue;
                NSScanner *scanner = [NSScanner scannerWithString:value];
                if([scanner scanInt:&intValue])
                    value = @(intValue);
                
                [configEnries addObject:@{ @"key":key, @"line":linePlaceholder }];
                [configValues setObject:value forKey:key];
            }
        }
        else
            [configEnries addObject:line];
    };
    
    [self setConfiguration:configValues];
    [self setConfigurationLineMapping:configEnries];
}

- (void)writeConfiguration
{
    NSError         *error              = nil;
    NSDictionary    *configuration      = [self configuration];
    NSArray         *lineMapping        = [self configurationLineMapping];
    NSMutableArray  *configurationLines = [NSMutableArray arrayWithCapacity:[lineMapping count]];
    
    for(id mapping in lineMapping)
    {
        if([mapping isKindOfClass:[NSString class]])
        {
            [configurationLines addObject:mapping];
        }
        else if([mapping isKindOfClass:[NSDictionary class]])
        {
            NSString *mappingKey  = [mapping objectForKey:@"key"];
            NSString *mappingLine = [mapping objectForKey:@"line"];
            
            id value = [configuration objectForKey:mappingKey];
            NSString *line = [NSString stringWithFormat:mappingLine, value];
            [configurationLines addObject:line];
        }
    }
    
    NSString *filePath     = [self configurationFilePath];
    NSString *fileContents = [configurationLines componentsJoinedByString:kREConfigurationLineSeparator];
    NSData   *fileData     = [fileContents dataUsingEncoding:kREConfigurationEncoding];
    BOOL writeSuccess      = [fileData writeToFile:filePath options:0 error:&error];
    if(!writeSuccess)
    {
        DLog(@"Error writing config file");
        DLog(@"%@", error);
    }
    
}
#pragma mark - I/O Level -
+ (NSString*)generateIdentifierFromDeviceData:(REDeviceData*)deviceData
{
    NSString *identifier = [NSString stringWithFormat:@"0x%x", deviceData->locationID];
    return identifier;
}

- (void)setupWithDeviceData:(REDeviceData*)deviceData
{
    DLog(@"%@", deviceData == NULL?@"Cleanup":@"Setup");
    [self setDeviceData:deviceData];
    if(deviceData != NULL)
    {
        [self setLocationID:(deviceData->locationID)];
        [self setIdentifier:[[self class] generateIdentifierFromDeviceData:deviceData]];
    }
    
    if(daSession == NULL && deviceData != NULL)
    {
        daSession = DASessionCreate(kCFAllocatorDefault);
        DASessionScheduleWithRunLoop(daSession, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    }
    else if(daSession != NULL && deviceData == NULL)
    {
        DASessionUnscheduleFromRunLoop(daSession, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(daSession);
        daSession = NULL;
    }
}

- (NSString*)bsdDeviceName
{
    IfNotConnectedReturn(kRENoBSDDevice);
    
    NSString *bsdName = nil;
    CFTypeRef bsdNameData = IORegistryEntrySearchCFProperty([self deviceData]->ioService, kIOServicePlane, CFSTR("BSD Name"), kCFAllocatorDefault, kIORegistryIterateRecursively);
    if (bsdNameData == NULL)
        bsdName = kRENoBSDDevice;
    else
        bsdName = (__bridge_transfer NSString*)bsdNameData;
    return bsdName;
}

- (NSString*)mountPath
{
    NSDictionary *diskDescription = [self diskDescription];
    if(!diskDescription) return kRENoBSDDevice;
    return [[diskDescription objectForKey:(__bridge NSString*)kDADiskDescriptionVolumePathKey] path]?:kREDiskNotMounted;
}

- (void)unmountFilesystem
{
    IfNotConnectedReturn();
    DLog();
    
    DADiskRef    disk_ref = DADiskCreateFromBSDName(kCFAllocatorDefault, daSession, [[self bsdDeviceName] UTF8String]);
    if(disk_ref != NULL)
    {
        DADiskUnmount(disk_ref, 0, REDADiskUnmountCallback, (__bridge void *)(self));
        CFRelease(disk_ref);
    }
}

- (void)mountFilesystem
{
    IfNotConnectedReturn();
    DLog();
    
    DADiskRef    disk_ref = DADiskCreateFromBSDName(kCFAllocatorDefault, daSession, [[self bsdDeviceName] UTF8String]);
    if(disk_ref != NULL)
    {
        DADiskMount(disk_ref, NULL, 0, REDADiskMountCallback, (__bridge void *)(self));
        CFRelease(disk_ref);
    }
}
#pragma mark I/O Level Helpers
- (NSDictionary*)diskDescription
{
    IfNotConnectedReturn(nil);
    
    NSDictionary *result  = nil;
    DADiskRef    disk_ref = DADiskCreateFromBSDName(kCFAllocatorDefault, daSession, [[self bsdDeviceName] UTF8String]);
    if(disk_ref != NULL)
    {
        result = (__bridge_transfer NSDictionary*)DADiskCopyDescription(disk_ref);
        CFRelease(disk_ref);
    }
    return result;
}
#pragma mark - C-Callbacks
void REDADiskUnmountCallback(DADiskRef disk, DADissenterRef dissenter, void *self)
{
    NSLog(@"REDADiskUnmountCallback");
    DLog(@"%d", dissenter == NULL);
}

void REDADiskMountCallback(DADiskRef disk, DADissenterRef dissenter, void *self)
{
    NSLog(@"REDDADiskMountCallback");
    DLog(@"%d", dissenter == NULL);
}
@end
