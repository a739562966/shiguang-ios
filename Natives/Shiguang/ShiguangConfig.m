#import "ShiguangConfig.h"

#include <stdlib.h>

NSString *ShiguangGameDir(void) {
    const char *dir = getenv("POJAV_GAME_DIR");
    return dir ? @(dir) : nil;
}
