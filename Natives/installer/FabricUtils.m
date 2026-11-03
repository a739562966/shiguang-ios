#import "FabricUtils.h"

@implementation FabricUtils

+ (NSDictionary *)endpoints {
    return @{
        @"Fabric": @{
            @"game": @"https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/game",
            @"loader": @"https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader",
            @"icon": @"https://avatars.githubusercontent.com/u/21025855?s=64",
            @"json": @"https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/%@/%@/profile/json"
        },
        @"Quilt": @{
            @"game": @"https://meta.quiltmc.org/v3/versions/game",
            @"loader": @"https://meta.quiltmc.org/v3/versions/loader",
            @"icon": @"https://raw.githubusercontent.com/QuiltMC/art/master/brand/64png/quilt_logo_transparent.png",
            @"json": @"https://meta.quiltmc.org/v3/versions/loader/%@/%@/profile/json"
        }
    };
}

@end
