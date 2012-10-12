//
//  RUFirmwareUpdater.h
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 29.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const RUFirmwareUpdaterDidReloadVersions;
extern NSString * const RUFirmwareUpdateErrorDomain;
extern const NSInteger kRUFirmwareUpdateErrorOtherUpdateInProgress;
extern const NSInteger kRUFirmwareUpdateErrorDeviceVersionMismatch;
extern const NSInteger kRUFirmwareUpdateErrorVersionAlreadyInstalled;
extern const NSInteger kRUFirmwareUpdateErrorRetrodeNotConnected;
extern const NSInteger kRUFirmwareUpdateErrorRetrodeNotInDFU;

@class RUFirmware, RURetrode;
@interface RUFirmwareUpdater : NSObject <NSURLDownloadDelegate>
+ (RUFirmwareUpdater*)sharedFirmwareUpdater;
- (BOOL)updateAvailableFirmwareVersionsWithError:(NSError**)outError;
- (void)installFirmware:(RUFirmware*)firmware toRetrode:(RURetrode*)retrode withCallback:(void (^)(double, id))callback;

@property (strong, readonly) NSArray *availableFirmwareVersions;
@end

@interface RUFirmware : NSObject
@property (strong, readonly) NSString *version;
@property (strong, readonly) NSString *deviceVersion;
@property (strong, readonly) NSURL    *url;
@property (strong, readonly) NSArray  *releaseNotes;
@property (strong, readonly) NSDate   *releaseDate;
@end