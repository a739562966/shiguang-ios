#pragma once

#import <Foundation/Foundation.h>

typedef void (^ShiguangSyncProgress)(NSString *message, double fraction, int64_t bytesPerSecond);
typedef void (^ShiguangSyncCompletion)(NSString *summary, BOOL success);

@interface ShiguangModSync : NSObject

/// 同步模组、材质包、服务器自制 mod，并写入 Xaero / 材质包配置。
/// 该方法会阻塞调用线程，请放到后台队列执行。
+ (void)syncGameDir:(NSString *)gameDir
           progress:(ShiguangSyncProgress)progress
         completion:(ShiguangSyncCompletion)completion;

@end
