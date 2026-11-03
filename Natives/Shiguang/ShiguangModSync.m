#import "ShiguangModSync.h"
#import "ShiguangConfig.h"
#import "ShiguangDownloader.h"

/// 与桌面版一致的在线清单地址（失败时用 App 内置的 spec.json 兜底）
static NSString *const SGSpecURL = SHIGUANG_SPEC_URL;
/// CurseForge 公益镜像（官方 API 需要 key）
static NSString *const SGCurseForgeAPI = @"https://mod.mcimirror.top/curseforge/v1";
/// CurseForge 的 Fabric 加载器枚举值
static const NSInteger SGCurseForgeFabric = 4;
/// 服务器自制 mod 目录最多翻页数
static const NSInteger SGServerModsMaxPages = 6;

#pragma mark - 基础工具

static NSError *SGMakeError(NSString *message) {
    return [NSError errorWithDomain:@"ShiguangModSyncError"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *SGEncodePath(NSString *value) {
    NSMutableString *out = [NSMutableString string];
    const unsigned char *bytes = (const unsigned char *)value.UTF8String;
    if (bytes == NULL) {
        return @"";
    }
    for (NSUInteger i = 0; bytes[i] != '\0'; i++) {
        unsigned char c = bytes[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
            [out appendFormat:@"%c", c];
        } else {
            [out appendFormat:@"%%%02X", c];
        }
    }
    return out;
}

static NSString *SGDecodePercent(NSString *value) {
    NSString *decoded = [value stringByRemovingPercentEncoding];
    return decoded ?: value;
}

/// 同步 GET，网络请求失败/HTTP >= 400 时返回 nil 并给出错误
static NSData *SGHttpGetData(NSString *urlString, NSError **outError) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        if (outError) *outError = SGMakeError(@"下载地址无效");
        return nil;
    }

    __block NSData *result = nil;
    __block NSError *resultError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 15;
    [request setValue:SHIGUANG_USER_AGENT forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            result = data;
            resultError = error;
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            if (resultError == nil && status >= 400) {
                resultError = SGMakeError([NSString stringWithFormat:@"HTTP %ld", (long)status]);
            }
            dispatch_semaphore_signal(semaphore);
        }];
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (outError) *outError = resultError;
    return resultError == nil ? result : nil;
}

static id SGJSONObjectFromData(NSData *data) {
    if (data.length >= 3) {
        const unsigned char *bytes = data.bytes;
        if (bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
            data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
        }
    }
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
}

static id SGHttpGetJSON(NSString *urlString, NSError **outError) {
    NSData *data = SGHttpGetData(urlString, outError);
    if (data == nil || data.length == 0) {
        return nil;
    }
    return SGJSONObjectFromData(data);
}

/// 同步下载一个文件，并把当前文件进度换算到整体进度
static NSError *SGDownloadFile(NSString *url, NSString *path, NSString *message,
                               double fractionBase, double fractionSpan,
                               ShiguangSyncProgress progress) {
    __block NSError *resultError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[ShiguangDownloader shared] downloadURL:url toPath:path
        progress:^(int64_t received, int64_t expected, double speed) {
            double fraction = fractionBase;
            if (expected > 0) {
                fraction = fractionBase + (double)received / (double)expected * fractionSpan;
            }
            if (fraction < 0) fraction = 0;
            if (fraction > 1) fraction = 1;
            if (progress) {
                progress(message, fraction, (int64_t)speed);
            }
        }
        completion:^(BOOL success, NSError *error) {
            resultError = error;
            dispatch_semaphore_signal(semaphore);
        }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return resultError;
}

#pragma mark - 清单与本地文件

static NSArray<NSDictionary *> *SGLoadSpecs(void) {
    NSError *error = nil;
    id online = SGHttpGetJSON(SGSpecURL, &error);
    if ([online isKindOfClass:NSArray.class] && [online count] > 0) {
        return online;
    }

    NSString *path = [NSBundle.mainBundle pathForResource:@"spec" ofType:@"json"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    id fallback = data ? SGJSONObjectFromData(data) : nil;
    if ([fallback isKindOfClass:NSArray.class]) {
        return fallback;
    }
    return @[];
}

static BOOL SGSpecIsPack(NSDictionary *spec) {
    return [spec[@"kind"] isEqualToString:@"pack"];
}

/// 从文件名解析版本号：fabric-api-0.116.17+1.21.1.jar → 0.116.17
static NSString *SGVersionFromName(NSString *name, BOOL isPack) {
    NSString *stem = name;
    NSString *lower = name.lowercaseString;
    if ([lower hasSuffix:@".jar"] || [lower hasSuffix:@".zip"]) {
        stem = [name substringToIndex:name.length - 4];
    }
    NSString *base = stem;
    NSRange plus = [stem rangeOfString:@"+"];
    if (plus.location != NSNotFound) {
        base = [stem substringToIndex:plus.location];
    }

    if (isPack) {
        NSString *token = [[base componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lastObject] ?: @"";
        NSString *digits = token;
        if ([digits hasPrefix:@"v"] || [digits hasPrefix:@"V"]) {
            digits = [digits substringFromIndex:1];
        }
        if (digits.length == 0) {
            return @"";
        }
        unichar first = [digits characterAtIndex:0];
        if (!(first >= '0' && first <= '9')) {
            return @"";
        }
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
        if ([digits rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
            return @"";
        }
        return digits;
    }

    NSArray<NSString *> *tokens = [base componentsSeparatedByString:@"-"];
    for (NSString *token in [tokens reverseObjectEnumerator]) {
        if (token.length == 0) {
            continue;
        }
        unichar first = [token characterAtIndex:0];
        if (!(first >= '0' && first <= '9')) {
            continue;
        }
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
        if ([token rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
            continue;
        }
        if ([token isEqualToString:SHIGUANG_MC_VERSION] || [token isEqualToString:@"1.21"]) {
            continue;
        }
        return token;
    }
    return tokens.lastObject ?: @"";
}

/// 版本号转数字序列，便于比较 1.8.10 > 1.8.9
static NSArray<NSNumber *> *SGVersionKey(NSString *version) {
    NSMutableArray<NSNumber *> *keys = [NSMutableArray array];
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < version.length; i++) {
        unichar c = [version characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [digits appendFormat:@"%C", c];
        } else if (digits.length > 0) {
            [keys addObject:@(digits.longLongValue)];
            [digits setString:@""];
        }
    }
    if (digits.length > 0) {
        [keys addObject:@(digits.longLongValue)];
    }
    return keys;
}

static NSComparisonResult SGCompareVersion(NSString *lhs, NSString *rhs) {
    NSArray<NSNumber *> *a = SGVersionKey(lhs);
    NSArray<NSNumber *> *b = SGVersionKey(rhs);
    NSUInteger count = MAX(a.count, b.count);
    for (NSUInteger i = 0; i < count; i++) {
        long long left = i < a.count ? a[i].longLongValue : 0;
        long long right = i < b.count ? b[i].longLongValue : 0;
        if (left > right) {
            return NSOrderedDescending;
        }
        if (left < right) {
            return NSOrderedAscending;
        }
    }
    return NSOrderedSame;
}

/// 在目录中找已安装的文件（版本号最高的一份），返回 path 与 version
static NSDictionary *SGFindBestLocalFile(NSString *directory, NSDictionary *spec) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray<NSString *> *names = [fileManager contentsOfDirectoryAtPath:directory error:nil];
    if (names == nil) {
        return nil;
    }

    NSString *contains = [spec[@"contains"] ?: @"" lowercaseString];
    NSString *excludes = [spec[@"excludes"] ?: @"" lowercaseString];
    BOOL isPack = SGSpecIsPack(spec);

    NSDictionary *best = nil;
    for (NSString *name in names) {
        NSString *lower = name.lowercaseString;
        BOOL extensionOK = isPack ? [lower hasSuffix:@".zip"] : [lower hasSuffix:@".jar"];
        if (!extensionOK) {
            continue;
        }
        // 用文件名前缀匹配：contains 会把 "Chiselmon-...+cobblemon-1.8.0.jar" 误判成 Cobblemon 本体
        if (contains.length > 0 && ![lower hasPrefix:contains]) {
            continue;
        }
        if (excludes.length > 0 && [lower containsString:excludes]) {
            continue;
        }
        NSString *version = SGVersionFromName(name, isPack);
        if (best == nil ||
            SGCompareVersion(version, best[@"version"]) == NSOrderedDescending) {
            best = @{
                @"path": [directory stringByAppendingPathComponent:name],
                @"version": version,
                @"name": name
            };
        }
    }
    return best;
}

static NSString *SGFindLocalFile(NSString *directory, NSDictionary *spec) {
    return SGFindBestLocalFile(directory, spec)[@"path"];
}

#pragma mark - 版本解析

static NSDictionary *SGResolveFromModrinth(NSDictionary *spec) {
    NSString *project = spec[@"modrinth"];
    if (![project isKindOfClass:NSString.class] || project.length == 0) {
        return nil;
    }

    NSString *url = [NSString stringWithFormat:
        @"https://api.modrinth.com/v2/project/%@/version?game_versions=%%5B%%22%@%%22%%5D",
        SGEncodePath(project), SHIGUANG_MC_VERSION];
    if (!SGSpecIsPack(spec)) {
        url = [url stringByAppendingString:@"&loaders=%5B%22fabric%22%5D"];
    }

    id json = SGHttpGetJSON(url, nil);
    if (![json isKindOfClass:NSArray.class]) {
        return nil;
    }

    for (NSDictionary *version in json) {
        if (![version isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSArray *gameVersions = version[@"game_versions"];
        if ([gameVersions isKindOfClass:NSArray.class] &&
            ![gameVersions containsObject:SHIGUANG_MC_VERSION]) {
            continue;
        }
        NSArray *loaders = version[@"loaders"];
        if (!SGSpecIsPack(spec) && [loaders isKindOfClass:NSArray.class] &&
            ![loaders containsObject:@"fabric"]) {
            continue;
        }

        NSArray *files = version[@"files"];
        if (![files isKindOfClass:NSArray.class] || files.count == 0) {
            continue;
        }
        NSDictionary *file = files.firstObject;
        for (NSDictionary *candidate in files) {
            if ([candidate[@"primary"] boolValue]) {
                file = candidate;
                break;
            }
        }
        NSString *link = file[@"url"];
        NSString *name = file[@"filename"];
        if ([link isKindOfClass:NSString.class] && link.length > 0 &&
            [name isKindOfClass:NSString.class] && name.length > 0) {
            return @{@"url": link, @"filename": name.lastPathComponent};
        }
    }
    return nil;
}

static NSDictionary *SGResolveFromCurseForge(NSDictionary *spec) {
    NSNumber *project = spec[@"curseforge"];
    if (![project isKindOfClass:NSNumber.class] || project.integerValue <= 0) {
        return nil;
    }

    NSString *url = [NSString stringWithFormat:
        @"%@/mods/%ld/files?gameVersion=%@&pageSize=20",
        SGCurseForgeAPI, (long)project.integerValue, SHIGUANG_MC_VERSION];
    if (!SGSpecIsPack(spec)) {
        url = [url stringByAppendingFormat:@"&modLoaderType=%ld", (long)SGCurseForgeFabric];
    }

    id json = SGHttpGetJSON(url, nil);
    NSArray *files = json[@"data"];
    if (![files isKindOfClass:NSArray.class]) {
        return nil;
    }

    for (NSDictionary *file in files) {
        if (![file isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSArray *gameVersions = file[@"gameVersions"];
        if ([gameVersions isKindOfClass:NSArray.class] &&
            ![gameVersions containsObject:SHIGUANG_MC_VERSION]) {
            continue;
        }
        if (!SGSpecIsPack(spec) && [gameVersions isKindOfClass:NSArray.class]) {
            BOOL fabric = NO;
            for (NSString *value in gameVersions) {
                if ([value isKindOfClass:NSString.class] &&
                    [value caseInsensitiveCompare:@"fabric"] == NSOrderedSame) {
                    fabric = YES;
                    break;
                }
            }
            if (!fabric) {
                continue;
            }
        }

        NSString *name = file[@"fileName"];
        if (![name isKindOfClass:NSString.class] || name.length == 0) {
            continue;
        }
        NSString *link = file[@"downloadUrl"];
        if (![link isKindOfClass:NSString.class] || link.length == 0) {
            NSInteger fileID = [file[@"id"] integerValue];
            if (fileID <= 0) {
                continue;
            }
            link = [NSString stringWithFormat:@"https://mediafilez.forgecdn.net/files/%ld/%03ld/%@",
                (long)(fileID / 1000), (long)(fileID % 1000), SGEncodePath(name)];
        }
        return @{@"url": link, @"filename": name.lastPathComponent};
    }
    return nil;
}

static NSDictionary *SGResolveRelease(NSDictionary *spec) {
    NSDictionary *release = SGResolveFromModrinth(spec);
    if (release != nil) {
        return release;
    }
    return SGResolveFromCurseForge(spec);
}

#pragma mark - 配置写入

/// 首次启动写入中文语言并跳过多人游戏警告（与桌面版一致）
static void SGEnsureDefaultOptions(NSString *gameDir) {
    NSString *path = [gameDir stringByAppendingPathComponent:@"options.txt"];
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        return;
    }
    NSString *text = @"lang:zh_cn\nonboardAccessibility:false\nskipMultiplayerWarning:true\n";
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void SGDispatchProgress(ShiguangSyncProgress progress, NSString *message, double fraction, int64_t speed) {
    if (progress != nil) {
        progress(message, fraction, speed);
    }
}

/// 把材质包写进 options.txt（只追加缺失项，保留玩家已有顺序）
static void SGEnableResourcePacks(NSString *gameDir, NSArray<NSDictionary *> *specs) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *optionsPath = [gameDir stringByAppendingPathComponent:@"options.txt"];
    NSString *markerPath = [gameDir stringByAppendingPathComponent:@".resourcepacks-seeded"];
    if ([fileManager fileExistsAtPath:markerPath] && [fileManager fileExistsAtPath:optionsPath]) {
        return;
    }

    NSString *packsDir = [gameDir stringByAppendingPathComponent:@"resourcepacks"];
    NSMutableArray<NSString *> *target = [NSMutableArray array];
    for (NSDictionary *spec in specs) {
        if (!SGSpecIsPack(spec)) {
            continue;
        }
        NSString *local = SGFindLocalFile(packsDir, spec);
        if (local != nil) {
            [target addObject:[@"file/" stringByAppendingString:local.lastPathComponent]];
        }
    }
    if (target.count == 0) {
        return;
    }

    NSString *text = [NSString stringWithContentsOfFile:optionsPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSMutableArray<NSString *> *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
    if (lines.count == 1 && [lines.firstObject length] == 0) {
        [lines removeAllObjects];
    }

    NSMutableArray<NSString *> *packs = [NSMutableArray array];
    NSInteger lineIndex = -1;
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        if ([lines[i] hasPrefix:@"resourcePacks:"]) {
            lineIndex = i;
            NSString *line = lines[i];
            NSRange start = [line rangeOfString:@"["];
            NSRange end = [line rangeOfString:@"]" options:NSBackwardsSearch];
            if (start.location != NSNotFound && end.location != NSNotFound && end.location > start.location) {
                NSString *jsonText = [line substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
                NSArray *existing = [NSJSONSerialization JSONObjectWithData:[jsonText dataUsingEncoding:NSUTF8StringEncoding]
                                                                     options:0 error:nil];
                if ([existing isKindOfClass:NSArray.class]) {
                    [packs addObjectsFromArray:existing];
                }
            }
            break;
        }
    }
    if (packs.count == 0) {
        [packs addObject:@"vanilla"];
    }

    NSInteger added = 0;
    for (NSString *entry in target) {
        if (![packs containsObject:entry]) {
            [packs addObject:entry];
            added++;
        }
    }
    if (added == 0) {
        [@"" writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:packs options:0 error:nil];
    NSString *packJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] ?: @"[]";
    NSString *newLine = [@"resourcePacks:" stringByAppendingString:packJSON];
    if (lineIndex >= 0) {
        lines[lineIndex] = newLine;
    } else {
        [lines addObject:newLine];
    }

    NSString *output = [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    if ([output writeToFile:optionsPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        [@"" writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

/// Xaero 小地图：实体图标常显
static void SGApplyXaeroIcons(NSString *gameDir) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *path = [gameDir stringByAppendingPathComponent:@"config/xaero/minimap/default_radar_categories_client.json"];
    NSString *marker = [gameDir stringByAppendingPathComponent:@".xaero-icons-seeded"];
    if ([fileManager fileExistsAtPath:marker] || ![fileManager fileExistsAtPath:path]) {
        return;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    NSMutableDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    if (![json isKindOfClass:NSMutableDictionary.class]) {
        return;
    }
    NSMutableDictionary *overrides = json[@"settingOverrides"];
    if (![overrides isKindOfClass:NSMutableDictionary.class]) {
        return;
    }
    if ([overrides[@"icons"] integerValue] == 2) {
        [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    overrides[@"icons"] = @2;

    NSData *output = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
    if ([output writeToFile:path atomically:YES]) {
        [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

/// 小地图停靠右上角、锁定北向上（只做一次）
static void SGApplyXaeroLayout(NSString *gameDir) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *marker = [gameDir stringByAppendingPathComponent:@".xaero-layout-seeded"];
    if ([fileManager fileExistsAtPath:marker]) {
        return;
    }

    NSString *configDir = [gameDir stringByAppendingPathComponent:@"config"];
    NSString *hudPath = [configDir stringByAppendingPathComponent:@"xaerohud.txt"];
    NSString *module = @"module;id=xaerominimap:minimap;x=0;y=0;centered=false;fromRight=true;fromBottom=false;flippedVer=false;flippedHor=false;";

    NSString *hudText = [NSString stringWithContentsOfFile:hudPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSMutableArray<NSString *> *hudLines = [NSMutableArray array];
    for (NSString *line in [hudText componentsSeparatedByString:@"\n"]) {
        if (line.length > 0) {
            [hudLines addObject:line];
        }
    }
    BOOL hasModule = NO;
    for (NSInteger i = 0; i < (NSInteger)hudLines.count; i++) {
        NSString *line = hudLines[i];
        if ([line containsString:@"id=xaerominimap:minimap"]) {
            hasModule = YES;
            if ([line containsString:@"x=0;y=0;"] && [line containsString:@"fromRight=false"]) {
                hudLines[i] = module;
            }
        }
    }
    if (!hasModule) {
        [hudLines addObject:module];
    }
    [fileManager createDirectoryAtPath:configDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *hudOutput = [[hudLines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    BOOL hudOK = [hudOutput writeToFile:hudPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSString *profilePath = [configDir stringByAppendingPathComponent:@"xaero/minimap/profiles/default.cfg"];
    NSString *profileText = [NSString stringWithContentsOfFile:profilePath encoding:NSUTF8StringEncoding error:nil];
    if (profileText == nil) {
        // 游戏还没生成配置，下次启动再试
        return;
    }
    NSMutableArray<NSString *> *profileLines = [NSMutableArray array];
    for (NSString *line in [profileText componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"minimap_north_locked"]) {
            [profileLines addObject:@"minimap_north_locked = true"];
        } else if (line.length > 0 || profileLines.count > 0) {
            [profileLines addObject:line];
        }
    }
    NSString *profileOutput = [[profileLines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    BOOL profileOK = [profileOutput writeToFile:profilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (hudOK && profileOK) {
        [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - 服务器自制 mod

static NSArray<NSString *> *SGFetchServerModNames(NSString **errorMessage) {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"href=\"([^\"]+\\.jar)\""
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    for (NSInteger page = 0; page < SGServerModsMaxPages; page++) {
        NSString *url = page == 0 ? SHIGUANG_SERVER_MODS_URL
                                  : [SHIGUANG_SERVER_MODS_URL stringByAppendingFormat:@"?page=%ld", (long)page];
        NSError *error = nil;
        NSData *data = SGHttpGetData(url, &error);
        if (data == nil) {
            if (page == 0 && errorMessage != NULL) {
                *errorMessage = error.localizedDescription;
            }
            break;
        }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        NSUInteger before = names.count;
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html options:0 range:NSMakeRange(0, html.length)];
        for (NSTextCheckingResult *match in matches) {
            NSString *raw = [html substringWithRange:[match rangeAtIndex:1]];
            NSString *lower = raw.lowercaseString;
            if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] ||
                [lower hasPrefix:@"/"] || [lower hasPrefix:@"~"] || [lower hasPrefix:@"#"]) {
                continue;
            }
            NSString *name = SGDecodePercent(raw);
            if (name.length == 0 || [name containsString:@"/"] || [name containsString:@"\\"] ||
                [name containsString:@".."]) {
                continue;
            }
            [names addObject:name];
        }
        if (names.count == before) {
            break;
        }
    }
    return names.allObjects;
}

static void SGSyncServerMods(NSString *gameDir, ShiguangSyncProgress progress) {
    NSString *modsDir = [gameDir stringByAppendingPathComponent:@"mods"];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    [fileManager createDirectoryAtPath:modsDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *errorMessage = nil;
    NSArray<NSString *> *remote = SGFetchServerModNames(&errorMessage);
    if (remote.count == 0) {
        return;
    }

    NSString *statePath = [modsDir stringByAppendingPathComponent:@".server_mods.json"];
    NSData *stateData = [NSData dataWithContentsOfFile:statePath];
    id previousJSON = stateData ? [NSJSONSerialization JSONObjectWithData:stateData options:0 error:nil] : nil;
    NSMutableSet<NSString *> *previous = [NSMutableSet set];
    if ([previousJSON isKindOfClass:NSArray.class]) {
        for (NSString *name in previousJSON) {
            if ([name isKindOfClass:NSString.class]) {
                [previous addObject:name];
            }
        }
    }
    NSMutableSet<NSString *> *remoteSet = [NSMutableSet setWithArray:remote];

    NSInteger total = remote.count;
    for (NSInteger i = 0; i < total; i++) {
        NSString *name = remote[i];
        NSString *target = [modsDir stringByAppendingPathComponent:name];
        if ([fileManager fileExistsAtPath:target]) {
            continue;
        }
        NSString *url = [SHIGUANG_SERVER_MODS_URL stringByAppendingString:SGEncodePath(name)];
        NSString *message = [NSString stringWithFormat:@"正在下载服务器 mod %@（%ld/%ld）", name, (long)(i + 1), (long)total];
        SGDownloadFile(url, target, message, (double)i / (double)total, 1.0 / (double)total, progress);
    }

    for (NSString *old in previous) {
        if (![remoteSet containsObject:old]) {
            NSString *path = [modsDir stringByAppendingPathComponent:old];
            [fileManager removeItemAtPath:path error:nil];
        }
    }

    NSMutableArray<NSString *> *remaining = [NSMutableArray array];
    for (NSString *name in remote) {
        if ([fileManager fileExistsAtPath:[modsDir stringByAppendingPathComponent:name]]) {
            [remaining addObject:name];
        }
    }
    NSData *stateOutput = [NSJSONSerialization dataWithJSONObject:remaining options:0 error:nil];
    if (stateOutput != nil) {
        [stateOutput writeToFile:statePath atomically:YES];
    }
}

#pragma mark - 主流程

@implementation ShiguangModSync

+ (void)syncGameDir:(NSString *)gameDir
           progress:(ShiguangSyncProgress)progress
         completion:(ShiguangSyncCompletion)completion {
    if (gameDir.length == 0) {
        if (completion) completion(@"游戏目录不可用", NO);
        return;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *modsDir = [gameDir stringByAppendingPathComponent:@"mods"];
    NSString *packsDir = [gameDir stringByAppendingPathComponent:@"resourcepacks"];
    [fileManager createDirectoryAtPath:modsDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fileManager createDirectoryAtPath:packsDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSArray<NSDictionary *> *specs = SGLoadSpecs();
    if (specs.count == 0) {
        if (completion) completion(@"模组清单为空", NO);
        return;
    }

    SGDispatchProgress(progress, @"正在检查模组与材质包…", 0, 0);

    __block NSInteger downloaded = 0;
    __block NSInteger updated = 0;
    __block NSInteger skipped = 0;
    __block NSInteger failed = 0;
    NSLock *counterLock = [NSLock new];
    // 最多 6 个文件同时下载：原来逐个串行，单个 CDN 连接只有几十 KB/s，总时间被拉得很长
    dispatch_semaphore_t slots = dispatch_semaphore_create(6);
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("shiguang.mod-sync", DISPATCH_QUEUE_CONCURRENT);

    void (^processSpec)(NSInteger) = ^(NSInteger i) {
        NSDictionary *spec = specs[i];
        if (![spec isKindOfClass:NSDictionary.class]) {
            return;
        }
        NSString *directory = SGSpecIsPack(spec) ? packsDir : modsDir;
        NSString *name = spec[@"name"] ?: @"未命名";
        NSString *kindLabel = SGSpecIsPack(spec) ? @"材质包" : @"模组";
        NSDictionary *local = SGFindBestLocalFile(directory, spec);

        SGDispatchProgress(progress,
            [NSString stringWithFormat:@"正在检查%@ %@（%ld/%ld）", kindLabel, name, (long)(i + 1), (long)specs.count],
            (double)i / (double)specs.count, 0);

        NSDictionary *release = SGResolveRelease(spec);
        if (release == nil) {
            [counterLock lock];
            if (local != nil) {
                // 离线或接口异常时，本地已有就保持现状
                skipped++;
            } else {
                failed++;
            }
            [counterLock unlock];
            return;
        }

        BOOL needsDownload = (local == nil);
        if (local != nil) {
            NSString *localVersion = local[@"version"];
            NSString *remoteVersion = SGVersionFromName(release[@"filename"] ?: @"", SGSpecIsPack(spec));
            if (localVersion.length > 0 && remoteVersion.length > 0) {
                needsDownload = SGCompareVersion(remoteVersion, localVersion) == NSOrderedDescending;
            } else {
                needsDownload = ![local[@"name"] isEqualToString:release[@"filename"]];
            }
        }
        if (!needsDownload) {
            [counterLock lock];
            skipped++;
            [counterLock unlock];
            SGDispatchProgress(progress,
                [NSString stringWithFormat:@"%@（已是最新）", name],
                (double)(i + 1) / (double)specs.count, 0);
            return;
        }

        NSString *target = [directory stringByAppendingPathComponent:release[@"filename"]];
        NSString *message = local != nil
            ? [NSString stringWithFormat:@"正在更新%@ %@（%ld/%ld）", kindLabel, name, (long)(i + 1), (long)specs.count]
            : [NSString stringWithFormat:@"正在下载%@ %@（%ld/%ld）", kindLabel, name, (long)(i + 1), (long)specs.count];
        NSError *error = SGDownloadFile(release[@"url"], target, message,
            (double)i / (double)specs.count, 1.0 / (double)specs.count, progress);
        [counterLock lock];
        if (error == nil) {
            if (local != nil && ![local[@"path"] isEqualToString:target]) {
                [fileManager removeItemAtPath:local[@"path"] error:nil];
                updated++;
            } else {
                downloaded++;
            }
        } else {
            failed++;
            [fileManager removeItemAtPath:target error:nil];
        }
        [counterLock unlock];
    };

    for (NSInteger i = 0; i < (NSInteger)specs.count; i++) {
        dispatch_group_enter(group);
        dispatch_async(queue, ^{
            dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
            processSpec(i);
            dispatch_semaphore_signal(slots);
            dispatch_group_leave(group);
        });
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    SGEnsureDefaultOptions(gameDir);
    SGEnableResourcePacks(gameDir, specs);
    SGApplyXaeroIcons(gameDir);
    SGApplyXaeroLayout(gameDir);

    SGDispatchProgress(progress, @"正在同步服务器 mod…", 0, 0);
    SGSyncServerMods(gameDir, progress);

    NSString *summary;
    if (downloaded == 0 && updated == 0 && failed == 0) {
        summary = [NSString stringWithFormat:@"模组与材质包已是最新（%ld 项）", (long)skipped];
    } else if (failed == 0) {
        summary = [NSString stringWithFormat:@"已同步 %ld 项，更新 %ld 项，跳过 %ld 项", (long)downloaded, (long)updated, (long)skipped];
    } else {
        summary = [NSString stringWithFormat:@"已同步 %ld 项，更新 %ld 项，失败 %ld 项", (long)downloaded, (long)updated, (long)failed];
    }
    if (completion) {
        completion(summary, failed == 0);
    }
}

@end
