#pragma once

#import "../authenticator/BaseAuthenticator.h"

@interface ShiguangAuthenticator : BaseAuthenticator

/// 登录（Yggdrasil /authserver/authenticate）
+ (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
                 callback:(Callback)callback;

/// 注册（Yggdrasil /authserver/register），成功后自动登录
+ (void)registerWithUsername:(NSString *)username
                     password:(NSString *)password
                     callback:(Callback)callback;

/// 启动前校验令牌，失效时自动刷新
+ (void)ensureValidWithCallback:(Callback)callback;

/// 当前账号是否来自拾光认证
+ (BOOL)isCurrentShiguang;

- (void)validateWithCallback:(Callback)callback;

@end
