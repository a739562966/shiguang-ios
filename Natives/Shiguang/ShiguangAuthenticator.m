#import "ShiguangAuthenticator.h"
#import "ShiguangConfig.h"

#import <UIKit/UIKit.h>
#include <stdlib.h>

#pragma mark - 工具

/// 把服务端返回的 \uXXXX 字面量还原成中文（有些错误信息被双重转义）
static NSString *ShiguangDecodeUnicodeEscapes(NSString *text) {
    if (![text containsString:@"\\u"]) {
        return text;
    }
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\\\u([0-9a-fA-F]{4})"
                                                                           options:0
                                                                             error:nil];
    NSMutableString *result = [text mutableCopy];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text
                                                             options:0
                                                               range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *hex = [text substringWithRange:[match rangeAtIndex:1]];
        unichar value = (unichar)strtoul(hex.UTF8String, NULL, 16);
        [result replaceCharactersInRange:match.range withString:[NSString stringWithFormat:@"%C", value]];
    }
    return result;
}

/// 极简 Yggdrasil 请求：成功回调解析后的 JSON，失败回调可直接展示的中文信息
static void ShiguangRequest(NSString *path, NSDictionary *body,
                            void (^success)(id json),
                            void (^failure)(NSString *message)) {
    NSURL *url = [NSURL URLWithString:[SHIGUANG_AUTH_SERVER stringByAppendingString:path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 20;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:SHIGUANG_USER_AGENT forHTTPHeaderField:@"User-Agent"];

    if (body != nil) {
        request.HTTPMethod = @"POST";
        NSError *jsonError = nil;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        if (jsonError != nil) {
            failure(@"请求数据编码失败");
            return;
        }
    } else {
        request.HTTPMethod = @"GET";
    }

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error != nil) {
                failure([NSString stringWithFormat:@"无法连接认证服务：%@", error.localizedDescription]);
                return;
            }
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            id json = nil;
            if (data.length > 0) {
                json = [NSJSONSerialization JSONObjectWithData:data
                                                       options:NSJSONReadingMutableContainers
                                                         error:nil];
            }
            if (status >= 200 && status < 300) {
                success(json ?: @{});
                return;
            }

            NSString *message = nil;
            if ([json isKindOfClass:NSDictionary.class]) {
                message = json[@"errorMessage"] ?: json[@"message"] ?: json[@"error"];
            }
            if (![message isKindOfClass:NSString.class] || message.length == 0) {
                message = [NSString stringWithFormat:@"认证服务返回 HTTP %ld", (long)status];
            }
            failure(ShiguangDecodeUnicodeEscapes(message));
        }];
    [task resume];
}

/// 从 authenticate / refresh 的响应中取出账号字段
static NSMutableDictionary *ShiguangAccountFromResponse(NSDictionary *json) {
    if (![json isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *accessToken = json[@"accessToken"];
    NSString *clientToken = json[@"clientToken"] ?: @"";
    NSDictionary *profile = json[@"selectedProfile"];

    if (![profile isKindOfClass:NSDictionary.class]) {
        NSArray *available = json[@"availableProfiles"];
        if ([available isKindOfClass:NSArray.class] && available.count > 0) {
            profile = available.firstObject;
        }
    }
    if (![accessToken isKindOfClass:NSString.class] || accessToken.length == 0) {
        return nil;
    }
    if (![profile isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSString *uuid = profile[@"id"];
    NSString *name = profile[@"name"];
    if (![uuid isKindOfClass:NSString.class] || uuid.length == 0) {
        return nil;
    }
    if (![name isKindOfClass:NSString.class] || name.length == 0) {
        return nil;
    }

    return [@{
        @"authType": SHIGUANG_ACCOUNT_TYPE,
        @"accessToken": accessToken,
        @"clientToken": clientToken,
        @"profileId": uuid,
        @"username": name,
        @"xuid": @"0"
    } mutableCopy];
}

#pragma mark - ShiguangAuthenticator

@implementation ShiguangAuthenticator

+ (BOOL)isCurrentShiguang {
    BaseAuthenticator *current = BaseAuthenticator.current;
    return [current.authData[@"authType"] isEqualToString:SHIGUANG_ACCOUNT_TYPE];
}

+ (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
                 callback:(Callback)callback {
    NSMutableDictionary *body = [@{
        @"agent": @{@"name": @"Minecraft", @"version": @1},
        @"username": username,
        @"password": password,
        @"requestUser": @YES,
        @"clientToken": [[[NSUUID UUID] UUIDString] lowercaseString]
    } mutableCopy];

    ShiguangRequest(@"/authserver/authenticate", body, ^(id json) {
        NSMutableDictionary *account = ShiguangAccountFromResponse(json);
        if (account == nil) {
            callback(@"登录成功但没有可用角色", NO);
            return;
        }
        ShiguangAuthenticator *authenticator = [[ShiguangAuthenticator alloc] initWithData:account];
        if (![authenticator saveChanges]) {
            callback(@"保存账号失败", NO);
            return;
        }
        BaseAuthenticator.current = authenticator;
        callback(nil, YES);
    }, ^(NSString *message) {
        callback(message, NO);
    });
}

+ (void)registerWithUsername:(NSString *)username
                     password:(NSString *)password
                     callback:(Callback)callback {
    ShiguangRequest(@"/authserver/register", @{@"username": username, @"password": password}, ^(id json) {
        // 注册成功后走一次标准登录，拿到正式令牌
        [ShiguangAuthenticator loginWithUsername:username password:password callback:callback];
    }, ^(NSString *message) {
        callback(message, NO);
    });
}

+ (void)ensureValidWithCallback:(Callback)callback {
    if (![ShiguangAuthenticator isCurrentShiguang]) {
        callback(@"请先登录", NO);
        return;
    }

    ShiguangAuthenticator *authenticator = (ShiguangAuthenticator *)BaseAuthenticator.current;
    [authenticator validateWithCallback:^(id status, BOOL valid) {
        if (valid) {
            callback(nil, YES);
            return;
        }
        [authenticator refreshTokenWithCallback:^(id refreshStatus, BOOL refreshed) {
            if (!refreshed) {
                callback(@"登录状态已失效，请重新登录", NO);
                return;
            }
            [authenticator saveChanges];
            callback(nil, YES);
        }];
    }];
}

- (void)loginWithCallback:(Callback)callback {
    NSString *username = self.authData[@"inputUsername"];
    NSString *password = self.authData[@"inputPassword"];
    if (![username isKindOfClass:NSString.class] || ![password isKindOfClass:NSString.class]) {
        callback(@"请输入用户名和密码", NO);
        return;
    }
    [ShiguangAuthenticator loginWithUsername:username password:password callback:callback];
}

- (void)validateWithCallback:(Callback)callback {
    NSString *accessToken = self.authData[@"accessToken"] ?: @"";
    NSString *clientToken = self.authData[@"clientToken"] ?: @"";
    ShiguangRequest(@"/authserver/validate", @{
        @"accessToken": accessToken,
        @"clientToken": clientToken
    }, ^(id json) {
        callback(nil, YES);
    }, ^(NSString *message) {
        callback(message, NO);
    });
}

- (void)refreshTokenWithCallback:(Callback)callback {
    NSString *accessToken = self.authData[@"accessToken"] ?: @"";
    NSString *clientToken = self.authData[@"clientToken"] ?: @"";
    ShiguangRequest(@"/authserver/refresh", @{
        @"accessToken": accessToken,
        @"clientToken": clientToken
    }, ^(id json) {
        NSMutableDictionary *account = ShiguangAccountFromResponse(json);
        if (account == nil) {
            callback(@"登录状态已失效，请重新登录", NO);
            return;
        }
        self.authData[@"oldusername"] = self.authData[@"username"];
        [self.authData addEntriesFromDictionary:account];
        callback(nil, YES);
    }, ^(NSString *message) {
        callback(message, NO);
    });
}

@end
