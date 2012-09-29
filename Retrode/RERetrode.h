//
//  RERetrode.h
//  Retrode
//
//  Created by Christoph Leimbrock on 28.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kREDiskNotMounted;  // Device is currently not mounted
extern NSString * const kRENoBSDDevice;     // Device is not known to DA, meaning it can't be mounted without hw reset

@interface RERetrode : NSObject
- (NSString*)mountPath;
- (void)mountFilesystem;
- (void)unmountFilesystem;
@property (readonly, strong) NSString *identifier;
@end

@protocol REREtrodeDelegate <NSObject>
- (void)retrodeDidConnect:(RERetrode*)retrode;
- (void)retrodeDidDisconnect:(RERetrode*)retrode;
@end