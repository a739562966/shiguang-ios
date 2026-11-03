#import "ShiguangConfig.h"

#include <stdlib.h>

NSString *ShiguangGameDir(void) {
    const char *dir = getenv("POJAV_GAME_DIR");
    return dir ? @(dir) : nil;
}

NSString *ShiguangMirrorURL(NSString *url) {
    if (url.length == 0) {
        return url;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:url];
    if (components == nil) {
        return url;
    }

    NSString *host = components.host.lowercaseString;
    if (host.length == 0) {
        return url;
    }

    static NSDictionary<NSString *, NSString *> *hosts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hosts = @{
            @"piston-meta.mojang.com": @"",
            @"launchermeta.mojang.com": @"",
            @"launcher.mojang.com": @"",
            @"libraries.minecraft.net": @"/maven",
            @"resources.download.minecraft.net": @"/assets",
            @"meta.fabricmc.net": @"/fabric-meta"
        };
    });

    NSString *prefix = hosts[host];
    if (prefix == nil) {
        return url;
    }

    components.host = @"bmclapi2.bangbang93.com";
    if (prefix.length > 0) {
        components.path = [prefix stringByAppendingString:components.path ?: @""];
    }
    return components.URL.absoluteString ?: url;
}
