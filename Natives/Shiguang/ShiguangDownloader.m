#import "ShiguangDownloader.h"
#import "ShiguangConfig.h"

#include <sys/stat.h>

static NSString *const ShiguangDownloaderErrorDomain = @"ShiguangDownloaderError";

@interface ShiguangDownloader () <NSURLSessionDownloadDelegate>
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSMutableDictionary<NSNumber *, NSMutableDictionary *> *entries;
@end

@implementation ShiguangDownloader

+ (instancetype)shared {
    static ShiguangDownloader *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ShiguangDownloader alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 86400;
    // 模组同步默认 6 个文件并发，系统默认每主机 6 条连接会互相排队
    configuration.HTTPMaximumConnectionsPerHost = 16;
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
    queue.name = @"shiguang.downloader";
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
    self.entries = [NSMutableDictionary new];
    return self;
}

- (void)downloadURL:(NSString *)urlString
              toPath:(NSString *)path
            progress:(ShiguangDownloadProgress)progress
          completion:(ShiguangDownloadCompletion)completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil || path.length == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:ShiguangDownloaderErrorDomain
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"下载地址无效"}]);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:SHIGUANG_USER_AGENT forHTTPHeaderField:@"User-Agent"];

    ShiguangDownloadProgress progressBlock = progress ?: ^(int64_t received, int64_t expected, double speed) {};
    ShiguangDownloadCompletion completionBlock = completion ?: ^(BOOL success, NSError *error) {};

    NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:request];
    NSMutableDictionary *entry = [@{
        @"path": path,
        @"progress": progressBlock,
        @"completion": completionBlock,
        @"lastBytes": @0,
        @"lastTime": @0,
        @"speed": @0
    } mutableCopy];

    @synchronized (self) {
        self.entries[@(task.taskIdentifier)] = entry;
    }
    [task resume];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    NSMutableDictionary *entry;
    @synchronized (self) {
        entry = self.entries[@(downloadTask.taskIdentifier)];
    }
    if (entry == nil) {
        return;
    }

    double now = NSDate.date.timeIntervalSinceReferenceDate;
    double lastTime = [entry[@"lastTime"] doubleValue];
    int64_t lastBytes = [entry[@"lastBytes"] longLongValue];
    double speed = [entry[@"speed"] doubleValue];
    if (lastTime > 0 && now > lastTime) {
        speed = (double)(totalBytesWritten - lastBytes) / (now - lastTime);
    }
    if (lastTime == 0 || now - lastTime >= 0.3) {
        entry[@"lastTime"] = @(now);
        entry[@"lastBytes"] = @(totalBytesWritten);
        entry[@"speed"] = @(speed);
    }

    ShiguangDownloadProgress progress = (ShiguangDownloadProgress)entry[@"progress"];
    if (progress != nil) {
        progress(totalBytesWritten, totalBytesExpectedToWrite, speed);
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSMutableDictionary *entry;
    @synchronized (self) {
        entry = self.entries[@(downloadTask.taskIdentifier)];
    }
    if (entry == nil) {
        return;
    }

    NSHTTPURLResponse *response = (NSHTTPURLResponse *)downloadTask.response;
    if (response != nil && response.statusCode >= 400) {
        entry[@"error"] = [NSError errorWithDomain:ShiguangDownloaderErrorDomain
                                              code:response.statusCode
                                          userInfo:@{NSLocalizedDescriptionKey:
                                              [NSString stringWithFormat:@"下载失败（HTTP %ld）", (long)response.statusCode]}];
        return;
    }

    NSString *path = entry[@"path"];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *error = nil;
    NSString *directory = path.stringByDeletingLastPathComponent;
    [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
    [fileManager removeItemAtPath:path error:nil];
    if (![fileManager moveItemAtPath:location.path toPath:path error:&error]) {
        entry[@"error"] = error ?: [NSError errorWithDomain:ShiguangDownloaderErrorDomain
                                                        code:2
                                                    userInfo:@{NSLocalizedDescriptionKey: @"保存下载文件失败"}];
        return;
    }
    entry[@"moved"] = @YES;
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    NSMutableDictionary *entry;
    @synchronized (self) {
        entry = self.entries[@(task.taskIdentifier)];
        if (entry != nil) {
            [self.entries removeObjectForKey:@(task.taskIdentifier)];
        }
    }
    if (entry == nil) {
        return;
    }

    NSError *finalError = error ?: entry[@"error"];
    BOOL success = finalError == nil && [entry[@"moved"] boolValue];
    if (finalError == nil && !success) {
        finalError = [NSError errorWithDomain:ShiguangDownloaderErrorDomain
                                          code:3
                                      userInfo:@{NSLocalizedDescriptionKey: @"下载未完成"}];
    }

    ShiguangDownloadCompletion completion = (ShiguangDownloadCompletion)entry[@"completion"];
    if (completion != nil) {
        completion(success, finalError);
    }
}

@end
