#import "ShiguangBootstrap.h"
#import "ShiguangConfig.h"
#import "ShiguangModSync.h"

#import "../MinecraftResourceDownloadTask.h"
#import "../PLProfiles.h"
#import "../LauncherNavigationController.h"
#import "../utils.h"

NSString *const ShiguangBootstrapDidUpdateNotification = @"ShiguangBootstrapDidUpdateNotification";

static void *ShiguangBootstrapProgressContext = &ShiguangBootstrapProgressContext;

static NSString *const ShiguangProfileName = @"拾光宝可梦小镇";

#pragma mark - 网络

static NSData *ShiguangBootstrapHttpGet(NSString *urlString, NSError **outError) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"ShiguangBootstrapError"
                                              code:1
                                          userInfo:@{NSLocalizedDescriptionKey: @"下载地址无效"}];
        }
        return nil;
    }

    __block NSData *result = nil;
    __block NSError *resultError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 25;
    [request setValue:SHIGUANG_USER_AGENT forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            result = data;
            resultError = error;
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            if (resultError == nil && status >= 400) {
                resultError = [NSError errorWithDomain:@"ShiguangBootstrapError"
                                                    code:status
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"HTTP %ld", (long)status]}];
            }
            dispatch_semaphore_signal(semaphore);
        }];
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (outError) *outError = resultError;
    return resultError == nil ? result : nil;
}

static id ShiguangBootstrapGetJSON(NSString *urlString, NSError **outError) {
    NSData *data = ShiguangBootstrapHttpGet(urlString, outError);
    if (data == nil || data.length == 0) {
        return nil;
    }
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
}

#pragma mark - 实现

@interface ShiguangBootstrap ()

@property(nonatomic, readwrite) BOOL running;
@property(nonatomic, readwrite) BOOL ready;
@property(nonatomic, readwrite) double progress;
@property(nonatomic, readwrite) int64_t speed;
@property(nonatomic, readwrite, copy) NSString *message;
@property(nonatomic, readwrite, copy) NSString *errorMessage;
@property(nonatomic, readwrite, copy) NSString *versionId;
@property(nonatomic, readwrite) NSDictionary *metadata;

@property(nonatomic) MinecraftResourceDownloadTask *task;
@property(nonatomic) dispatch_semaphore_t downloadSemaphore;
@property(nonatomic) BOOL downloadFailed;
@property(nonatomic) BOOL observingDownload;
@property(nonatomic) NSTimeInterval lastProgressTime;
@property(nonatomic) int64_t lastProgressBytes;

- (void)run;
- (void)postUpdateNotification;
- (void)updateMessage:(NSString *)message progress:(double)progress speed:(int64_t)speed;
- (void)finishWithError:(NSString *)error;
- (void)finishReadyWithMessage:(NSString *)message;
- (NSString *)localFabricVersionIdInGameDir:(NSString *)gameDir;
- (NSString *)ensureFabricProfileInGameDir:(NSString *)gameDir error:(NSString **)outError;
- (void)applyLauncherProfile:(NSString *)versionId;
- (BOOL)downloadGameWithVersionId:(NSString *)versionId error:(NSString **)outError;

@end

@implementation ShiguangBootstrap

+ (ShiguangBootstrap *)shared {
    static ShiguangBootstrap *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ShiguangBootstrap alloc] init];
    });
    return shared;
}

+ (void)startForce:(BOOL)force {
    ShiguangBootstrap *bootstrap = self.shared;
    @synchronized (bootstrap) {
        if (bootstrap.running) {
            return;
        }
        if (bootstrap.ready && !force) {
            return;
        }
        bootstrap.running = YES;
        bootstrap.ready = NO;
        bootstrap.errorMessage = nil;
        bootstrap.progress = -1;
        bootstrap.speed = 0;
        bootstrap.message = @"正在检查运行环境…";
    }

    [bootstrap postUpdateNotification];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [bootstrap run];
    });
}

+ (void)start {
    [self startForce:NO];
}

+ (void)retry {
    [self startForce:YES];
}

- (void)postUpdateNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:ShiguangBootstrapDidUpdateNotification
                                                          object:self];
    });
}

- (void)updateMessage:(NSString *)message progress:(double)progress speed:(int64_t)speed {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.message = message;
        self.progress = progress;
        self.speed = speed;
        [NSNotificationCenter.defaultCenter postNotificationName:ShiguangBootstrapDidUpdateNotification
                                                          object:self];
    });
}

- (void)finishWithError:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.running = NO;
        self.ready = NO;
        self.errorMessage = error;
        self.message = error;
        self.progress = -1;
        self.speed = 0;
        [NSNotificationCenter.defaultCenter postNotificationName:ShiguangBootstrapDidUpdateNotification
                                                          object:self];
    });
}

- (void)finishReadyWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.running = NO;
        self.ready = YES;
        self.errorMessage = nil;
        self.message = message;
        self.progress = 1;
        self.speed = 0;
        [NSNotificationCenter.defaultCenter postNotificationName:ShiguangBootstrapDidUpdateNotification
                                                          object:self];
    });
}

#pragma mark - Fabric

- (NSString *)localFabricVersionIdInGameDir:(NSString *)gameDir {
    NSString *versionsDir = [gameDir stringByAppendingPathComponent:@"versions"];
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:versionsDir error:nil];
    for (NSString *name in names) {
        if (![name hasPrefix:@"fabric-loader-"] || ![name hasSuffix:[@"-" stringByAppendingString:SHIGUANG_MC_VERSION]]) {
            continue;
        }
        NSString *jsonPath = [[[versionsDir stringByAppendingPathComponent:name]
            stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"json"];
        NSData *data = [NSData dataWithContentsOfFile:jsonPath];
        if (data == nil) {
            continue;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class] && [json[@"id"] isEqualToString:name]) {
            return name;
        }
    }
    return nil;
}

- (NSString *)ensureFabricProfileInGameDir:(NSString *)gameDir error:(NSString **)outError {
    NSString *local = [self localFabricVersionIdInGameDir:gameDir];
    if (local != nil) {
        return local;
    }

    NSError *error = nil;
    id loaders = ShiguangBootstrapGetJSON([NSString stringWithFormat:
        @"https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/%@", SHIGUANG_MC_VERSION], &error);
    if (![loaders isKindOfClass:NSArray.class] || [loaders count] == 0) {
        if (outError) *outError = @"无法获取 Fabric 加载器列表，请检查网络";
        return nil;
    }

    NSArray *loaderList = (NSArray *)loaders;
    NSDictionary *selected = loaderList.firstObject;
    for (NSDictionary *entry in loaderList) {
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"loader"][@"stable"] boolValue]) {
            selected = entry;
            break;
        }
    }
    NSString *loaderVersion = selected[@"loader"][@"version"];
    if (![loaderVersion isKindOfClass:NSString.class] || loaderVersion.length == 0) {
        if (outError) *outError = @"Fabric 加载器版本解析失败";
        return nil;
    }

    NSString *profileURL = [NSString stringWithFormat:
        @"https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/%@/%@/profile/json",
        SHIGUANG_MC_VERSION, loaderVersion];
    NSDictionary *profile = ShiguangBootstrapGetJSON(profileURL, &error);
    if (![profile isKindOfClass:NSDictionary.class]) {
        // 网络失败时再尝试一次本地缓存
        local = [self localFabricVersionIdInGameDir:gameDir];
        if (local != nil) {
            return local;
        }
        if (outError) *outError = @"无法获取 Fabric 加载器信息，请检查网络";
        return nil;
    }

    NSString *versionId = profile[@"id"];
    if (![versionId isKindOfClass:NSString.class] || versionId.length == 0) {
        versionId = [NSString stringWithFormat:@"fabric-loader-%@-%@", loaderVersion, SHIGUANG_MC_VERSION];
    }

    NSString *directory = [gameDir stringByAppendingPathComponent:[NSString stringWithFormat:@"versions/%@", versionId]];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [[directory stringByAppendingPathComponent:versionId] stringByAppendingPathExtension:@"json"];
    NSError *writeError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:profile options:NSJSONWritingPrettyPrinted error:&writeError];
    if (data == nil || ![data writeToFile:path atomically:YES]) {
        if (outError) *outError = @"保存 Fabric 配置失败";
        return nil;
    }
    return versionId;
}

- (void)applyLauncherProfile:(NSString *)versionId {
    dispatch_sync(dispatch_get_main_queue(), ^{
        PLProfiles *profiles = PLProfiles.current;
        NSMutableDictionary *all = profiles.profileDict[@"profiles"];
        if (![all isKindOfClass:NSMutableDictionary.class]) {
            all = [NSMutableDictionary dictionary];
            profiles.profileDict[@"profiles"] = all;
        }
        all[ShiguangProfileName] = [@{
            @"name": ShiguangProfileName,
            @"lastVersionId": versionId,
            @"gameDir": @"."
        } mutableCopy];
        profiles.profileDict[@"selectedProfile"] = (id)ShiguangProfileName;
        [profiles save];
    });
}

#pragma mark - 游戏文件

- (BOOL)downloadGameWithVersionId:(NSString *)versionId error:(NSString **)outError {
    self.task = [MinecraftResourceDownloadTask new];
    self.downloadFailed = NO;
    self.downloadSemaphore = dispatch_semaphore_create(0);
    self.lastProgressTime = 0;
    self.lastProgressBytes = 0;

    __weak ShiguangBootstrap *weakSelf = self;
    self.task.handleError = ^{
        ShiguangBootstrap *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.downloadFailed = YES;
        if (strongSelf.downloadSemaphore != nil) {
            dispatch_semaphore_signal(strongSelf.downloadSemaphore);
        }
    };

    [self.task downloadVersion:@{@"id": versionId}];
    [self.task.progress addObserver:self
                          forKeyPath:@"fractionCompleted"
                             options:NSKeyValueObservingOptionInitial
                             context:ShiguangBootstrapProgressContext];
    self.observingDownload = YES;

    dispatch_semaphore_wait(self.downloadSemaphore, DISPATCH_TIME_FOREVER);

    if (self.observingDownload) {
        [self.task.progress removeObserver:self forKeyPath:@"fractionCompleted" context:ShiguangBootstrapProgressContext];
        self.observingDownload = NO;
    }

    BOOL failed = self.downloadFailed || self.task.metadata == nil;
    if (failed) {
        if (outError) *outError = @"游戏文件下载失败，请检查网络后重试";
        self.task = nil;
        return NO;
    }
    self.metadata = self.task.metadata;
    self.task = nil;
    return YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context != ShiguangBootstrapProgressContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    MinecraftResourceDownloadTask *task = self.task;
    if (task == nil) {
        return;
    }
    NSProgress *progress = task.progress;
    if (progress == nil || progress.totalUnitCount <= 0) {
        return;
    }

    double fraction = progress.fractionCompleted;
    int64_t completed = (int64_t)(progress.totalUnitCount * fraction);
    NSTimeInterval now = NSDate.date.timeIntervalSinceReferenceDate;
    int64_t speed = 0;
    if (self.lastProgressTime > 0 && now > self.lastProgressTime) {
        int64_t delta = completed - self.lastProgressBytes;
        if (delta > 0) {
            speed = (int64_t)((double)delta / (now - self.lastProgressTime));
        }
    }

    if (self.lastProgressTime == 0 || now - self.lastProgressTime >= 0.5 || fraction >= 0.999) {
        self.lastProgressTime = now;
        self.lastProgressBytes = completed;
        [self updateMessage:[NSString stringWithFormat:@"正在下载游戏 %d%%", (int)(fraction * 100)]
                   progress:fraction
                      speed:speed];
    }

    // 与上游逻辑一致：用 textProgress 的 finished 判断整个下载队列是否结束
    NSProgress *textProgress = task.textProgress;
    if (textProgress != nil) {
        textProgress.completedUnitCount = completed;
        if (textProgress.finished && task.metadata != nil && self.downloadSemaphore != nil) {
            dispatch_semaphore_signal(self.downloadSemaphore);
        }
    }
}

#pragma mark - 主流程

- (void)run {
    NSString *gameDir = ShiguangGameDir();
    if (gameDir.length == 0) {
        [self finishWithError:@"游戏目录不可用"];
        return;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:gameDir withIntermediateDirectories:YES attributes:nil error:nil];

    [self updateMessage:@"正在获取游戏版本信息…" progress:-1 speed:0];

    NSError *manifestError = nil;
    id manifestObject = ShiguangBootstrapGetJSON(@"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json", &manifestError);
    if (![manifestObject isKindOfClass:NSDictionary.class]) {
        [self finishWithError:@"无法获取 Minecraft 版本清单，请检查网络"];
        return;
    }
    NSDictionary *manifest = manifestObject;
    NSArray *versions = manifest[@"versions"];
    if (![versions isKindOfClass:NSArray.class] || versions.count == 0) {
        [self finishWithError:@"无法获取 Minecraft 版本清单，请检查网络"];
        return;
    }
    remoteVersionList = [versions mutableCopy];

    NSDictionary *baseVersion = nil;
    for (NSDictionary *version in versions) {
        if ([version isKindOfClass:NSDictionary.class] && [version[@"id"] isEqualToString:SHIGUANG_MC_VERSION]) {
            baseVersion = version;
            break;
        }
    }
    if (baseVersion == nil) {
        [self finishWithError:[NSString stringWithFormat:@"版本清单中找不到 Minecraft %@", SHIGUANG_MC_VERSION]];
        return;
    }

    [self updateMessage:@"正在获取 Fabric 加载器…" progress:-1 speed:0];
    NSString *fabricError = nil;
    NSString *fabricVersionId = [self ensureFabricProfileInGameDir:gameDir error:&fabricError];
    if (fabricVersionId == nil) {
        [self finishWithError:fabricError ?: @"Fabric 加载器准备失败"];
        return;
    }
    self.versionId = fabricVersionId;
    [self applyLauncherProfile:fabricVersionId];

    NSString *authlibPath = [NSBundle.mainBundle pathForResource:@"authlib-injector" ofType:@"jar" inDirectory:@"libs"];
    if (authlibPath == nil) {
        [self finishWithError:@"缺少 authlib-injector.jar，无法连接拾光认证服务器"];
        return;
    }

    [self updateMessage:@"正在检查游戏文件…" progress:0 speed:0];
    NSString *downloadError = nil;
    if (![self downloadGameWithVersionId:fabricVersionId error:&downloadError]) {
        [self finishWithError:downloadError ?: @"游戏文件下载失败"];
        return;
    }

    __block NSString *syncSummary = nil;
    __block BOOL syncOK = NO;
    __weak ShiguangBootstrap *weakSelf = self;
    [ShiguangModSync syncGameDir:gameDir progress:^(NSString *message, double fraction, int64_t speed) {
        ShiguangBootstrap *strongSelf = weakSelf;
        [strongSelf updateMessage:message progress:fraction speed:speed];
    } completion:^(NSString *summary, BOOL success) {
        syncSummary = summary;
        syncOK = success;
    }];

    if (syncSummary.length == 0) {
        syncSummary = syncOK ? @"准备完成" : @"模组同步失败，仍可启动游戏";
    }
    [self finishReadyWithMessage:syncSummary];
}

@end
