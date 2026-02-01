#import <AVFoundation/AVFoundation.h>
#import <SafariServices/SafariServices.h>

#import "LauncherPreferences.h"

#include "jni.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <objc/runtime.h>

#include "utils.h"

CFTypeRef SecTaskCopyValueForEntitlement(void* task, NSString* entitlement, CFErrorRef  _Nullable *error);
void* SecTaskCreateFromSelf(CFAllocatorRef allocator);

static inline UIColor *AmethystColorFromHex(uint32_t hex, CGFloat alpha) {
    CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 8) & 0xFF) / 255.0;
    CGFloat b = (hex & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
}

static UIColor *AmethystDynamicColor(uint32_t lightHex, uint32_t darkHex, CGFloat alpha) {
    UIColor *light = AmethystColorFromHex(lightHex, alpha);
    UIColor *dark = AmethystColorFromHex(darkHex, alpha);
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
            return trait.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        }];
    }
    return light;
}

typedef struct {
    const char *key;
    uint32_t light;
    uint32_t dark;
    uint32_t lightSoft;
    uint32_t darkSoft;
} AmethystAccentPalette;

static const AmethystAccentPalette kAmethystAccentPalettes[] = {
    {"teal", 0x1F9E93, 0x39D3BB, 0xD6F3EE, 0x163333},
    {"blue", 0x2F6BFF, 0x6EA1FF, 0xD9E6FF, 0x1A2A4A},
    {"purple", 0x7A4DFF, 0xB18CFF, 0xE6DBFF, 0x2A2045},
    {"pink", 0xE85CAB, 0xFF8FD1, 0xFDE0F1, 0x3C2033},
    {"orange", 0xF28C28, 0xFFB068, 0xFFE9D1, 0x3B2A1A},
    {"red", 0xE23C3C, 0xFF7B7B, 0xFADADA, 0x3C1E1E},
    {"green", 0x2FA24A, 0x6EE087, 0xDDF6E3, 0x1D3A25},
    {"mono", 0x58606A, 0xC0CAD4, 0xE6EAEE, 0x2A323A}
};

static const AmethystAccentPalette *AmethystAccentPaletteForKey(NSString *key) {
    if (![key isKindOfClass:NSString.class] || key.length == 0) {
        return &kAmethystAccentPalettes[0];
    }
    for (size_t i = 0; i < sizeof(kAmethystAccentPalettes) / sizeof(kAmethystAccentPalettes[0]); i++) {
        if ([key isEqualToString:@(kAmethystAccentPalettes[i].key)]) {
            return &kAmethystAccentPalettes[i];
        }
    }
    return &kAmethystAccentPalettes[0];
}

static UIColor *AmethystThemeAccentColorForPreference(BOOL soft) {
    NSString *accentKey = getPrefObject(@"general.theme_accent");
    const AmethystAccentPalette *palette = AmethystAccentPaletteForKey(accentKey);
    if (soft) {
        return AmethystDynamicColor(palette->lightSoft, palette->darkSoft, 1.0);
    }
    return AmethystDynamicColor(palette->light, palette->dark, 1.0);
}

typedef struct {
    const char *key;
    uint32_t lightBackground;
    uint32_t darkBackground;
    uint32_t lightSurface;
    uint32_t darkSurface;
    uint32_t lightSurfaceElevated;
    uint32_t darkSurfaceElevated;
    uint32_t lightTextPrimary;
    uint32_t darkTextPrimary;
    uint32_t lightTextSecondary;
    uint32_t darkTextSecondary;
    uint32_t lightSeparator;
    uint32_t darkSeparator;
    uint32_t lightSelection;
    uint32_t darkSelection;
} AmethystThemePalette;

static const AmethystThemePalette kAmethystThemePalettes[] = {
    {"amethyst", 0xF4F7FB, 0x0F131A, 0xFFFFFF, 0x151B24, 0xE9EEF5, 0x1C2430, 0x1B1F24, 0xE6EDF3, 0x546374, 0x9AA8B6, 0xD5DEE8, 0x2A3340, 0xDCE9F7, 0x233040},
    {"midnight", 0xEFF3FB, 0x0B0F16, 0xF7FAFF, 0x121826, 0xE3E9F4, 0x1A2333, 0x101828, 0xE2E8F0, 0x475467, 0x98A2B3, 0xCDD5E1, 0x243042, 0xD7E3F7, 0x1C2536},
    {"warm", 0xFBF5EF, 0x1A120F, 0xFFFAF6, 0x221714, 0xF3E8DD, 0x2C1F1A, 0x2B1E1A, 0xF6EEE7, 0x6B5449, 0xC8B6AA, 0xE4D4C6, 0x3A2A23, 0xF1E1D2, 0x33241E},
    {"oled", 0xF5F5F5, 0x000000, 0xFFFFFF, 0x0B0B0B, 0xEDEDED, 0x141414, 0x1A1A1A, 0xF2F2F2, 0x5A5A5A, 0xB0B0B0, 0xD6D6D6, 0x1F1F1F, 0xE0E0E0, 0x161616}
};

static const AmethystThemePalette *AmethystThemePaletteForKey(NSString *key) {
    if (![key isKindOfClass:NSString.class] || key.length == 0) {
        return &kAmethystThemePalettes[0];
    }
    for (size_t i = 0; i < sizeof(kAmethystThemePalettes) / sizeof(kAmethystThemePalettes[0]); i++) {
        if ([key isEqualToString:@(kAmethystThemePalettes[i].key)]) {
            return &kAmethystThemePalettes[i];
        }
    }
    return &kAmethystThemePalettes[0];
}

static const AmethystThemePalette *AmethystCurrentThemePalette(void) {
    NSString *paletteKey = getPrefObject(@"general.theme_palette");
    return AmethystThemePaletteForKey(paletteKey);
}

static NSString *AmethystThemeBackgroundImagePath(void) {
    id value = getPrefObject(@"general.theme_background_image");
    if (![value isKindOfClass:NSString.class] || [value length] == 0) {
        return nil;
    }
    return value;
}

static NSString *AmethystThemeBackgroundVideoPath(void) {
    id value = getPrefObject(@"general.theme_background_video");
    if (![value isKindOfClass:NSString.class] || [value length] == 0) {
        return nil;
    }
    return value;
}

static CGFloat AmethystThemeBackgroundOpacity(void) {
    CGFloat alpha = 1.0;
    id value = getPrefObject(@"general.theme_background_opacity");
    if ([value respondsToSelector:@selector(doubleValue)]) {
        alpha = [value doubleValue] / 100.0;
    }
    alpha = clamp(alpha, 0.0, 1.0);
    if (!AmethystThemeBackgroundImagePath() && !AmethystThemeBackgroundVideoPath()) {
        return 1.0;
    }
    return alpha;
}

BOOL getEntitlementValue(NSString *key) {
    void *secTask = SecTaskCreateFromSelf(NULL);
    CFTypeRef value = SecTaskCopyValueForEntitlement(SecTaskCreateFromSelf(NULL), key, nil);
    if (value != nil) {
        CFRelease(value);
    }
    CFRelease(secTask);

    return value != nil && [(__bridge id)value boolValue];
}

BOOL isJITEnabled(BOOL checkCSFlags) {
    if (!checkCSFlags && (getEntitlementValue(@"dynamic-codesigning") || isJailbroken)) {
        return YES;
    }

    int flags;
    csops(getpid(), 0, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) != 0;
}

void openLink(UIViewController* sender, NSURL* link) {
    if (NSClassFromString(@"SFSafariViewController") == nil) {
        NSData *data = [link.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
        [filter setValue:data forKey:@"inputMessage"];
        UIImage *image = [UIImage imageWithCIImage:filter.outputImage scale:1.0 orientation:UIImageOrientationUp];
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(300, 300), NO, 0.0);
        CGRect frame = CGRectMake(0, 0, 300, 300);
        [image drawInRect:frame];
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:frame];
        imageView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil
            message:link.absoluteString
            preferredStyle:UIAlertControllerStyleAlert];

        UIViewController *vc = UIViewController.new;
        vc.view = imageView;
        [alert setValue:vc forKey:@"contentViewController"];

        UIAlertAction* doneAction = [UIAlertAction actionWithTitle:localize(@"Done", nil) style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:doneAction];
        [sender presentViewController:alert animated:YES completion:nil];
    } else {
        SFSafariViewController *vc = [[SFSafariViewController alloc] initWithURL:link];
        [sender presentViewController:vc animated:YES completion:nil];
    }
}

NSMutableDictionary* parseJSONFromFile(NSString *path) {
    NSError *error;

    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (content == nil) {
        NSLog(@"[ParseJSON] Error: could not read %@: %@", path, error.localizedDescription);
        return @{@"NSErrorObject": error}.mutableCopy;
    }

    NSData* data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error) {
        NSLog(@"[ParseJSON] Error: could not parse JSON: %@", error.localizedDescription);
        return @{@"NSErrorObject": error}.mutableCopy;
    }
    return dict;
}

NSError* saveJSONToFile(NSDictionary *dict, NSString *path) {
    // TODO: handle rename
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
    if (jsonData == nil) {
        return error;
    }
    BOOL success = [jsonData writeToFile:path options:NSDataWritingAtomic error:&error];
    if (!success) {
        return error;
    }
    return nil;
}

NSString* localize(NSString* key, NSString* comment) {
    NSString *value = NSLocalizedString(key, nil);
    if (![NSLocale.preferredLanguages[0] isEqualToString:@"en"] && [value isEqualToString:key]) {
        NSString* path = [NSBundle.mainBundle pathForResource:@"en" ofType:@"lproj"];
        NSBundle* languageBundle = [NSBundle bundleWithPath:path];
        value = [languageBundle localizedStringForKey:key value:nil table:nil];

        if ([value isEqualToString:key]) {
            value = [[NSBundle bundleWithIdentifier:@"com.apple.UIKit"] localizedStringForKey:key value:nil table:nil];
        }
    }

    return value;
}

UIColor* AmethystThemeBackgroundColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightBackground, palette->darkBackground, AmethystThemeBackgroundOpacity());
}

UIColor* AmethystThemeSurfaceColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightSurface, palette->darkSurface, AmethystThemeBackgroundOpacity());
}

UIColor* AmethystThemeSurfaceElevatedColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightSurfaceElevated, palette->darkSurfaceElevated, AmethystThemeBackgroundOpacity());
}

UIColor* AmethystThemeAccentColor(void) {
    return AmethystThemeAccentColorForPreference(NO);
}

UIColor* AmethystThemeAccentSoftColor(void) {
    return AmethystThemeAccentColorForPreference(YES);
}

UIColor* AmethystThemeTextPrimaryColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightTextPrimary, palette->darkTextPrimary, 1.0);
}

UIColor* AmethystThemeTextSecondaryColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightTextSecondary, palette->darkTextSecondary, 1.0);
}

UIColor* AmethystThemeSeparatorColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightSeparator, palette->darkSeparator, AmethystThemeBackgroundOpacity());
}

UIColor* AmethystThemeSelectionColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightSelection, palette->darkSelection, AmethystThemeBackgroundOpacity());
}

static UIUserInterfaceStyle AmethystPreferredInterfaceStyle(void) {
    NSString *mode = getPrefObject(@"general.theme_mode");
    if ([mode isKindOfClass:NSString.class]) {
        if ([mode isEqualToString:@"light"]) {
            return UIUserInterfaceStyleLight;
        }
        if ([mode isEqualToString:@"dark"]) {
            return UIUserInterfaceStyleDark;
        }
    }
    return UIUserInterfaceStyleUnspecified;
}

void AmethystApplyThemeAppearance(void) {
    UIColor *accent = AmethystThemeAccentColor();
    UIColor *surface = AmethystThemeSurfaceColor();
    UIColor *text = AmethystThemeTextPrimaryColor();
    UIColor *separator = AmethystThemeSeparatorColor();
    CGFloat backgroundAlpha = AmethystThemeBackgroundOpacity();

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *navAppearance = [[UINavigationBarAppearance alloc] init];
        if (backgroundAlpha < 1.0) {
            [navAppearance configureWithTransparentBackground];
        } else {
            [navAppearance configureWithOpaqueBackground];
        }
        navAppearance.backgroundColor = surface;
        navAppearance.titleTextAttributes = @{NSForegroundColorAttributeName: text};
        navAppearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: text};
        navAppearance.shadowColor = separator;

        UINavigationBar *navProxy = [UINavigationBar appearance];
        navProxy.standardAppearance = navAppearance;
        navProxy.compactAppearance = navAppearance;
        navProxy.scrollEdgeAppearance = navAppearance;
        navProxy.tintColor = accent;

        UIToolbarAppearance *toolbarAppearance = [[UIToolbarAppearance alloc] init];
        if (backgroundAlpha < 1.0) {
            [toolbarAppearance configureWithTransparentBackground];
        } else {
            [toolbarAppearance configureWithOpaqueBackground];
        }
        toolbarAppearance.backgroundColor = surface;
        toolbarAppearance.shadowColor = separator;

        UIToolbar *toolbarProxy = [UIToolbar appearance];
        toolbarProxy.standardAppearance = toolbarAppearance;
        toolbarProxy.compactAppearance = toolbarAppearance;
        toolbarProxy.scrollEdgeAppearance = toolbarAppearance;
        toolbarProxy.tintColor = accent;

        UITableView *tableProxy = [UITableView appearance];
        tableProxy.backgroundColor = AmethystThemeBackgroundColor();
        tableProxy.separatorColor = separator;

        UISwitch *switchProxy = [UISwitch appearance];
        switchProxy.onTintColor = accent;

        UIProgressView *progressProxy = [UIProgressView appearance];
        progressProxy.tintColor = accent;

        UITextField *textFieldProxy = [UITextField appearance];
        textFieldProxy.tintColor = accent;
    } else {
        UINavigationBar *navProxy = [UINavigationBar appearance];
        navProxy.barTintColor = surface;
        navProxy.titleTextAttributes = @{NSForegroundColorAttributeName: text};
        navProxy.tintColor = accent;

        UIToolbar *toolbarProxy = [UIToolbar appearance];
        toolbarProxy.barTintColor = surface;
        toolbarProxy.tintColor = accent;

        UISwitch *switchProxy = [UISwitch appearance];
        switchProxy.onTintColor = accent;
    }
}

@interface AmethystBackgroundVideoView : UIView
@end

@implementation AmethystBackgroundVideoView
+ (Class)layerClass {
    return [AVPlayerLayer class];
}
@end

static char kAmethystThemeBackgroundVideoViewKey;
static char kAmethystThemeBackgroundVideoPlayerKey;
static char kAmethystThemeBackgroundVideoLooperKey;
static char kAmethystThemeBackgroundVideoPathKey;
static char kAmethystThemeBackgroundImageViewKey;

static AmethystBackgroundVideoView *AmethystThemeBackgroundVideoView(UIWindow *window) {
    AmethystBackgroundVideoView *view = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoViewKey);
    if (!view) {
        view = [[AmethystBackgroundVideoView alloc] initWithFrame:window.bounds];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.contentMode = UIViewContentModeScaleAspectFill;
        view.userInteractionEnabled = NO;
        view.clipsToBounds = YES;
        view.hidden = YES;
        AVPlayerLayer *layer = (AVPlayerLayer *)view.layer;
        layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [window insertSubview:view atIndex:0];
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
}

static UIImageView *AmethystThemeBackgroundImageView(UIWindow *window) {
    UIImageView *view = objc_getAssociatedObject(window, &kAmethystThemeBackgroundImageViewKey);
    if (!view) {
        view = [[UIImageView alloc] initWithFrame:window.bounds];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.contentMode = UIViewContentModeScaleAspectFill;
        view.userInteractionEnabled = NO;
        view.clipsToBounds = YES;
        UIView *videoView = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoViewKey);
        if (videoView) {
            [window insertSubview:view aboveSubview:videoView];
        } else {
            [window insertSubview:view atIndex:0];
        }
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundImageViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
}

void AmethystApplyThemeToWindow(UIWindow *window) {
    if (!window) return;
    if (@available(iOS 13.0, *)) {
        window.overrideUserInterfaceStyle = AmethystPreferredInterfaceStyle();
    }
    NSString *videoPath = AmethystThemeBackgroundVideoPath();
    AmethystBackgroundVideoView *videoView = AmethystThemeBackgroundVideoView(window);
    UIImageView *backgroundView = AmethystThemeBackgroundImageView(window);
    BOOL hasVideo = NO;
    if (videoPath && [NSFileManager.defaultManager fileExistsAtPath:videoPath]) {
        hasVideo = YES;
        AVPlayerLayer *layer = (AVPlayerLayer *)videoView.layer;
        NSString *currentPath = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoPathKey);
        AVQueuePlayer *player = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoPlayerKey);
        if (!currentPath || ![currentPath isEqualToString:videoPath] || !player) {
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:videoPath]];
            AVQueuePlayer *newPlayer = [AVQueuePlayer queuePlayerWithItems:@[item]];
            newPlayer.muted = YES;
            newPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;

            AVPlayerLooper *looper = [AVPlayerLooper playerLooperWithPlayer:newPlayer templateItem:item];
            objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoPlayerKey, newPlayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoLooperKey, looper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoPathKey, videoPath, OBJC_ASSOCIATION_COPY_NONATOMIC);
            layer.player = newPlayer;
            [newPlayer play];
        } else {
            if (layer.player != player) {
                layer.player = player;
            }
            [player play];
        }
        videoView.hidden = NO;
        [window sendSubviewToBack:videoView];
    } else {
        AVPlayerLayer *layer = (AVPlayerLayer *)videoView.layer;
        AVQueuePlayer *player = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoPlayerKey);
        if (player) {
            [player pause];
        }
        layer.player = nil;
        videoView.hidden = YES;
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoPlayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoLooperKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoPathKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }

    NSString *imagePath = hasVideo ? nil : AmethystThemeBackgroundImagePath();
    if (imagePath) {
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        if (image) {
            backgroundView.image = image;
            backgroundView.hidden = NO;
            [window sendSubviewToBack:backgroundView];
        } else {
            backgroundView.hidden = YES;
        }
    } else {
        backgroundView.hidden = YES;
    }
    window.tintColor = AmethystThemeAccentColor();
    window.backgroundColor = AmethystThemeBackgroundColor();
}

void customNSLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...)
{
    va_list ap; 
    va_start (ap, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:ap];
    printf("%s", [body UTF8String]);
    if (![format hasSuffix:@"\n"]) {
        printf("\n");
    }
    va_end (ap);
}

CGFloat MathUtils_dist(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    const CGFloat x = (x2 - x1);
    const CGFloat y = (y2 - y1);
    return (CGFloat) hypot(x, y);
}

//Ported from https://www.arduino.cc/reference/en/language/functions/math/map/
CGFloat MathUtils_map(CGFloat x, CGFloat in_min, CGFloat in_max, CGFloat out_min, CGFloat out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

CGFloat dpToPx(CGFloat dp) {
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    return dp * screenScale;
}

CGFloat pxToDp(CGFloat px) {
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    return px / screenScale;
}

void setButtonPointerInteraction(UIButton *button) {
    button.pointerInteractionEnabled = YES;
    button.pointerStyleProvider = ^ UIPointerStyle* (UIButton* button, UIPointerEffect* proposedEffect, UIPointerShape* proposedShape) {
        UITargetedPreview *preview = [[UITargetedPreview alloc] initWithView:button];
        return [NSClassFromString(@"UIPointerStyle") styleWithEffect:[NSClassFromString(@"UIPointerHighlightEffect") effectWithPreview:preview] shape:proposedShape];
    };
}

__attribute__((noinline,optnone,naked))
void* JIT26CreateRegionLegacy(size_t len) {
    asm("brk #0x69 \n"
        "ret");
}
__attribute__((noinline,optnone,naked))
void* JIT26PrepareRegion(void *addr, size_t len) {
    asm("mov x16, #1 \n"
        "brk #0xf00d \n"
        "ret");
}
__attribute__((noinline,optnone,naked))
void BreakSendJITScript(char* script, size_t len) {
   asm("mov x16, #2 \n"
       "brk #0xf00d \n"
       "ret");
}
__attribute__((noinline,optnone,naked))
void JIT26SetDetachAfterFirstBr(BOOL value) {
   asm("mov x16, #3 \n"
       "brk #0xf00d \n"
       "ret");
}
__attribute__((noinline,optnone,naked))
void JIT26PrepareRegionForPatching(void *addr, size_t size) {
   asm("mov x16, #4 \n"
       "brk #0xf00d \n"
       "ret");
}
void JIT26SendJITScript(NSString* script) {
    NSCAssert(script, @"Script must not be nil");
    BreakSendJITScript((char*)script.UTF8String, script.length);
}
BOOL DeviceRequiresTXMWorkaround(void) {
    if (@available(iOS 26.0, *)) {
        DIR *d = opendir("/private/preboot");
        if(!d) return NO;
        struct dirent *dir;
        char txmPath[PATH_MAX];
        while ((dir = readdir(d)) != NULL) {
            if(strlen(dir->d_name) == 96) {
                snprintf(txmPath, sizeof(txmPath), "/private/preboot/%s/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", dir->d_name);
                break;
            }
        }
        closedir(d);
        return access(txmPath, F_OK) == 0;
    }
    return NO;
}
