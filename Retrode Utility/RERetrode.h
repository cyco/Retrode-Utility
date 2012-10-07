//
//  RERetrode.h
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kREDiskNotMounted;  // Device is currently not mounted
extern NSString * const kRENoBSDDevice;     // Device is not known to DA, meaning it can't be mounted without hw reset

extern const int64_t kREDisconnectDelay;
extern const int32_t kREVendorIDVersion2;
extern const int32_t kREProductIDVersion2;
extern const int32_t kREVendorIDVersion2DFU;
extern const int32_t kREProductIDVersion2DFU;

@class REFirmware, RERetrode;
@protocol REREtrodeDelegate <NSObject>
@optional
- (void)retrodeDidDisconnect:(RERetrode*)retrode;
- (void)retrodeHardwareDidBecomeAvailable:(RERetrode*)retrode;
- (void)retrodeHardwareDidBecomeUnavailable:(RERetrode*)retrode;
- (void)retrodeDidMount:(RERetrode*)retrode; // TODO: actually call this
- (void)retrodeDidUnmount:(RERetrode*)retrode; // TODO: actually call this

- (void)retrodeDidEnterDFUMode:(RERetrode*)retrode;
- (void)retrodeDidLeaveDFUMode:(RERetrode*)retrode;
@end

@interface RERetrode : NSObject
- (NSString*)mountPath;
- (void)mountFilesystem;
- (void)unmountFilesystem;

@property (readonly, strong) NSString *identifier;
@property BOOL isMounted;
@property (nonatomic) id <REREtrodeDelegate> delegate;
@end

