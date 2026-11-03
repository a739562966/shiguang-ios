#pragma once

#import <Foundation/Foundation.h>

extern NSString *const ShiguangBootstrapDidUpdateNotification;

@interface ShiguangBootstrap : NSObject

@property(class, readonly) ShiguangBootstrap *shared;

@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) BOOL ready;
/// 0..1，-1 表示当前阶段进度未知
@property(nonatomic, readonly) double progress;
@property(nonatomic, readonly) int64_t speed;
@property(nonatomic, readonly, copy) NSString *message;
@property(nonatomic, readonly, copy) NSString *errorMessage;
@property(nonatomic, readonly, copy) NSString *versionId;
@property(nonatomic, readonly) NSDictionary *metadata;

+ (void)start;
+ (void)retry;
+ (void)startForce:(BOOL)force;

@end
