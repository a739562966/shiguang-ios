#pragma once

#import <Foundation/Foundation.h>

// 拾光宝可梦小镇 品牌与服务器常量（iOS 版）
#define SHIGUANG_APP_NAME           @"拾光宝可梦小镇"
#define SHIGUANG_AUTH_SERVER        @"https://auth.shiguangxz.online"
#define SHIGUANG_SERVER_ADDRESS     @"112.8.202.159"
#define SHIGUANG_MC_VERSION         @"1.21.1"
#define SHIGUANG_SPEC_URL           @"http://119.188.240.218:14325/shiguang/spec.json"
#define SHIGUANG_SERVER_MODS_URL    @"http://119.188.240.218:14325/mods/"
#define SHIGUANG_ACCOUNT_TYPE       @"shiguang"
#define SHIGUANG_USER_AGENT         @"Shiguang/iOS"
#define SHIGUANG_VERSION            @"1.0.1"

/// 与桌面版一致：公告 / 意见反馈 / QQ 群 / 版本更新
#define SHIGUANG_ANNOUNCEMENT_URL   @"http://www.shiguangxz.online:3000/api/announcements?page=1&pageSize=1"
#define SHIGUANG_FEEDBACK_URL       @"http://www.shiguangxz.online:3000/"
#define SHIGUANG_QQ_URL             @"https://qm.qq.com/q/txQDQ9H7lm"
#define SHIGUANG_RELEASES_URL       @"https://github.com/a739562966/shiguang-ios/releases"
#define SHIGUANG_LATEST_RELEASE_URL @"https://api.github.com/repos/a739562966/shiguang-ios/releases/latest"

// 启动器管理的游戏目录（POJAV_GAME_DIR 的符号链接目标）
NSString *ShiguangGameDir(void);

/// 把 Mojang / Fabric 官方地址换成国内镜像（BMCLAPI），不匹配的地址原样返回
NSString *ShiguangMirrorURL(NSString *url);
