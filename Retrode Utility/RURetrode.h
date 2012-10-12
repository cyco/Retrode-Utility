//
//  RURetrode.h
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kRUDiskNotMounted;  // Device is currently not mounted
extern NSString * const kRUNoBSDDevice;     // Device is not known to DA, meaning it can't be mounted without hw reset

extern const int64_t kRUDisconnectDelay;
extern const int32_t kRUVendorID;
extern const int32_t kRUProductIDVersion1;
extern const int32_t kRUProductIDVersion2;
extern const int32_t kRUVendorIDVersion2DFU;
extern const int32_t kRUProductIDVersion2DFU;

@class RUFirmware, RURetrode;
@protocol RURetrodeDelegate <NSObject>
@optional
- (void)retrodeDidDisconnect:(RURetrode*)retrode;
- (void)retrodeHardwareDidBecomeAvailable:(RURetrode*)retrode;
- (void)retrodeHardwareDidBecomeUnavailable:(RURetrode*)retrode;
- (void)retrodeDidMount:(RURetrode*)retrode; // TODO: actually call this
- (void)retrodeDidUnmount:(RURetrode*)retrode; // TODO: actually call this

- (void)retrodeDidEnterDFUMode:(RURetrode*)retrode;
- (void)retrodeDidLeaveDFUMode:(RURetrode*)retrode;
@end

@interface RURetrode : NSObject
- (NSString*)mountPath;
- (void)mountFilesystem;
- (void)unmountFilesystem;

@property (readonly, strong) NSString *identifier;
@property BOOL isMounted;
@property (nonatomic) id <RURetrodeDelegate> delegate;
@end

