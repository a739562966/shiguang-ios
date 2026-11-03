#pragma once

#import <Foundation/Foundation.h>

typedef void (^ShiguangDownloadProgress)(int64_t received, int64_t expected, double bytesPerSecond);
typedef void (^ShiguangDownloadCompletion)(BOOL success, NSError *error);

@interface ShiguangDownloader : NSObject

+ (instancetype)shared;

- (void)downloadURL:(NSString *)urlString
              toPath:(NSString *)path
            progress:(ShiguangDownloadProgress)progress
          completion:(ShiguangDownloadCompletion)completion;

@end
