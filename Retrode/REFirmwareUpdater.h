//
//  REFirmwareUpdater.h
//  Retrode
//
//  Created by Christoph Leimbrock on 29.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const REFirmwareUpdaterDidReloadVersions;

@interface REFirmwareUpdater : NSObject
+ (REFirmwareUpdater*)sharedFirmwareUpdater;
- (BOOL)updateAvailableFirmwareVersionsWithError:(NSError**)outError;
@property (strong, readonly) NSArray *availableFirmwareVersions;
@end

@interface REFirmware : NSObject
@property (strong, readonly) NSString *version;
@property (strong, readonly) NSString *deviceVersion;
@property (strong, readonly) NSURL    *url;
@property (strong, readonly) NSArray  *releaseNotes;
@property (strong, readonly) NSDate   *releaseDate;
@end