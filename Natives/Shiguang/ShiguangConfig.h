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
#define SHIGUANG_VERSION            @"1.0.0"

// 启动器管理的游戏目录（POJAV_GAME_DIR 的符号链接目标）
NSString *ShiguangGameDir(void);
