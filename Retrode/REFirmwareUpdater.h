//
//  REFirmwareUpdater.h
//  Retrode
//
//  Created by Christoph Leimbrock on 29.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const REFirmwareUpdaterDidReloadVersions;
extern NSString * const REFirmwareUpdateErrorDomain;
extern const NSInteger kREFirmwareUpdateErrorOtherUpdateInProgress;
extern const NSInteger kREFirmwareUpdateErrorDeviceVersionMismatch;
extern const NSInteger kREFirmwareUpdateErrorVersionAlreadyInstalled;
extern const NSInteger kREFirmwareUpdateErrorRetrodeNotConnected;
extern const NSInteger kREFirmwareUpdateErrorRetrodeNotInDFU;

@class REFirmware, RERetrode;
@interface REFirmwareUpdater : NSObject <NSURLDownloadDelegate>
+ (REFirmwareUpdater*)sharedFirmwareUpdater;
- (BOOL)updateAvailableFirmwareVersionsWithError:(NSError**)outError;

- (void)installFirmware:(REFirmware*)firmware toRetrode:(RERetrode*)retrode withCallback:(void (^)(double, id))callback;

@property (strong, readonly) NSArray *availableFirmwareVersions;
@end

@interface REFirmware : NSObject
@property (strong, readonly) NSString *version;
@property (strong, readonly) NSString *deviceVersion;
@property (strong, readonly) NSURL    *url;
@property (strong, readonly) NSArray  *releaseNotes;
@property (strong, readonly) NSDate   *releaseDate;
@end