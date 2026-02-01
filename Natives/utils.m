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
    {"indigo", 0x5B5BF7, 0x8F8CFF, 0xE2E3FF, 0x26264D},
    {"cyan", 0x12B3D6, 0x5FE1FF, 0xD9F6FF, 0x123040},
    {"purple", 0x7A4DFF, 0xB18CFF, 0xE6DBFF, 0x2A2045},
    {"pink", 0xE85CAB, 0xFF8FD1, 0xFDE0F1, 0x3C2033},
    {"rose", 0xFF4D6D, 0xFF8FA3, 0xFFE0E7, 0x3B1C24},
    {"orange", 0xF28C28, 0xFFB068, 0xFFE9D1, 0x3B2A1A},
    {"yellow", 0xF2C94C, 0xFFD166, 0xFFF4CC, 0x3B3212},
    {"red", 0xE23C3C, 0xFF7B7B, 0xFADADA, 0x3C1E1E},
    {"green", 0x2FA24A, 0x6EE087, 0xDDF6E3, 0x1D3A25},
    {"lime", 0x7BCB1E, 0xB6FF5C, 0xE8FAD1, 0x233313},
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
    {"ocean", 0xF2F8FB, 0x0E1A23, 0xFFFFFF, 0x142434, 0xE6F0F7, 0x1C3042, 0x14202B, 0xE6F3FF, 0x4A5C6B, 0x97A9B7, 0xD6E2EC, 0x2B3D4E, 0xD7E9F7, 0x243647},
    {"forest", 0xF4F8F3, 0x101A14, 0xFFFFFF, 0x162019, 0xE6EFE4, 0x1E2A22, 0x1C241F, 0xE6F2EA, 0x556157, 0xA0B0A4, 0xD7E2D8, 0x2A372E, 0xDDE9DF, 0x243126},
    {"sakura", 0xFFF5F7, 0x1E1216, 0xFFFFFF, 0x26171D, 0xFFE9EF, 0x2F1C24, 0x24181D, 0xF7E9EE, 0x6B4B55, 0xC9AAB4, 0xF0D9E1, 0x3A2630, 0xFCE0E8, 0x35202A},
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

static NSString *AmethystThemeTextColorKey(void) {
    id value = getPrefObject(@"general.theme_text_color");
    if (![value isKindOfClass:NSString.class] || [value length] == 0) {
        return @"default";
    }
    return value;
}

static CGFloat AmethystThemeTextOpacity(void) {
    CGFloat alpha = 1.0;
    id value = getPrefObject(@"general.theme_text_opacity");
    if ([value respondsToSelector:@selector(doubleValue)]) {
        alpha = [value doubleValue] / 100.0;
    }
    return clamp(alpha, 0.0, 1.0);
}

static CGFloat AmethystThemeButtonOpacity(void) {
    CGFloat alpha = 1.0;
    id value = getPrefObject(@"general.theme_button_opacity");
    if ([value respondsToSelector:@selector(doubleValue)]) {
        alpha = [value doubleValue] / 100.0;
    }
    return clamp(alpha, 0.0, 1.0);
}

BOOL AmethystThemeButtonOutlineEnabled(void) {
    return getPrefBool(@"general.theme_button_outline");
}

CGFloat AmethystThemeButtonCornerRadius(void) {
    CGFloat radius = 12.0;
    id value = getPrefObject(@"general.theme_button_corner_radius");
    if ([value respondsToSelector:@selector(doubleValue)]) {
        radius = [value doubleValue];
    }
    return clamp(radius, 0.0, 40.0);
}

CGFloat AmethystThemeButtonBorderWidth(void) {
    CGFloat width = 1.0;
    id value = getPrefObject(@"general.theme_button_border_width");
    if ([value respondsToSelector:@selector(doubleValue)]) {
        width = [value doubleValue];
    }
    width = clamp(width, 0.0, 10.0);
    return width / UIScreen.mainScreen.scale;
}

static BOOL AmethystThemeHasBackgroundImage(void) {
    id portrait = getPrefObject(@"general.theme_background_image");
    id landscape = getPrefObject(@"general.theme_background_image_landscape");
    BOOL hasPortrait = [portrait isKindOfClass:NSString.class] && [portrait length] > 0;
    BOOL hasLandscape = [landscape isKindOfClass:NSString.class] && [landscape length] > 0;
    return hasPortrait || hasLandscape;
}

static NSString *AmethystThemeBackgroundImagePathForWindow(UIWindow *window) {
    NSString *portrait = getPrefObject(@"general.theme_background_image");
    NSString *landscape = getPrefObject(@"general.theme_background_image_landscape");
    BOOL hasPortrait = [portrait isKindOfClass:NSString.class] && portrait.length > 0;
    BOOL hasLandscape = [landscape isKindOfClass:NSString.class] && landscape.length > 0;
    if (!hasPortrait && !hasLandscape) {
        return nil;
    }
    BOOL isLandscape = window.bounds.size.width > window.bounds.size.height;
    if (isLandscape) {
        return hasLandscape ? landscape : (hasPortrait ? portrait : nil);
    }
    return hasPortrait ? portrait : (hasLandscape ? landscape : nil);
}

static BOOL AmethystThemeHasBackgroundVideo(void) {
    id portrait = getPrefObject(@"general.theme_background_video");
    if ([portrait isKindOfClass:NSString.class] && [portrait length] > 0) {
        return YES;
    }
    id landscape = getPrefObject(@"general.theme_background_video_landscape");
    return [landscape isKindOfClass:NSString.class] && [landscape length] > 0;
}

static NSString *AmethystThemeBackgroundVideoPathForWindow(UIWindow *window) {
    NSString *portrait = getPrefObject(@"general.theme_background_video");
    NSString *landscape = getPrefObject(@"general.theme_background_video_landscape");
    BOOL hasPortrait = [portrait isKindOfClass:NSString.class] && portrait.length > 0;
    BOOL hasLandscape = [landscape isKindOfClass:NSString.class] && landscape.length > 0;
    if (!hasPortrait && !hasLandscape) {
        return nil;
    }
    BOOL isLandscape = window.bounds.size.width > window.bounds.size.height;
    if (isLandscape) {
        return hasLandscape ? landscape : (hasPortrait ? portrait : nil);
    }
    return hasPortrait ? portrait : (hasLandscape ? landscape : nil);
}

static NSString *AmethystThemeBackgroundRotationKeyForWindow(UIWindow *window) {
    BOOL isLandscape = window.bounds.size.width > window.bounds.size.height;
    NSString *prefKey = isLandscape ? @"general.theme_background_rotation_landscape"
                                    : @"general.theme_background_rotation_portrait";
    id value = getPrefObject(prefKey);
    if ([value isKindOfClass:NSString.class] && [value length] > 0) {
        return value;
    }
    id legacy = getPrefObject(@"general.theme_background_rotation");
    if ([legacy isKindOfClass:NSString.class] && [legacy length] > 0) {
        return legacy;
    }
    return isLandscape ? @"landscape" : @"portrait";
}

static UIInterfaceOrientation AmethystThemeInterfaceOrientation(UIWindow *window) {
    if (@available(iOS 13.0, *)) {
        UIInterfaceOrientation orientation = window.windowScene.interfaceOrientation;
        if (orientation != UIInterfaceOrientationUnknown) {
            return orientation;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
}

static UIImageOrientation AmethystThemeBackgroundImageOrientationForWindow(UIWindow *window) {
    NSString *key = AmethystThemeBackgroundRotationKeyForWindow(window);
    if ([key isEqualToString:@"portrait"]) {
        return UIImageOrientationUp;
    }
    if ([key isEqualToString:@"landscape_left"]) {
        return UIImageOrientationLeft;
    }
    if ([key isEqualToString:@"landscape_right"]) {
        return UIImageOrientationRight;
    }
    if ([key isEqualToString:@"landscape"]) {
        UIInterfaceOrientation orientation = AmethystThemeInterfaceOrientation(window);
        if (orientation == UIInterfaceOrientationLandscapeLeft) {
            return UIImageOrientationRight;
        }
        if (orientation == UIInterfaceOrientationLandscapeRight) {
            return UIImageOrientationLeft;
        }
        if (window.bounds.size.width > window.bounds.size.height) {
            return UIImageOrientationRight;
        }
        return UIImageOrientationUp;
    }
    return UIImageOrientationUp;
}

static UIImage *AmethystThemeImageWithOrientation(UIImage *image, UIImageOrientation orientation) {
    if (!image || orientation == UIImageOrientationUp) {
        return image;
    }
    return [UIImage imageWithCGImage:image.CGImage scale:image.scale orientation:orientation];
}

static BOOL AmethystThemeShouldUsePortraitOverlay(UIWindow *window, NSString *imagePath, UIImage *image) {
    if (!window || !imagePath || !image) {
        return NO;
    }
    if (window.bounds.size.width <= window.bounds.size.height) {
        return NO;
    }
    if (![AmethystThemeBackgroundRotationKeyForWindow(window) isEqualToString:@"portrait"]) {
        return NO;
    }
    NSString *portrait = getPrefObject(@"general.theme_background_image");
    NSString *landscape = getPrefObject(@"general.theme_background_image_landscape");
    BOOL hasLandscape = [landscape isKindOfClass:NSString.class] && landscape.length > 0;
    if (hasLandscape) {
        return NO;
    }
    if (![portrait isKindOfClass:NSString.class] || portrait.length == 0) {
        return NO;
    }
    if (![imagePath isEqualToString:portrait]) {
        return NO;
    }
    return image.size.height >= image.size.width;
}

static CGFloat AmethystThemeBackgroundOpacity(void) {
    CGFloat alpha = 1.0;
    id value = getPrefObject(@"general.theme_background_opacity");
    if ([value respondsToSelector:@selector(doubleValue)]) {
        alpha = [value doubleValue] / 100.0;
    }
    alpha = clamp(alpha, 0.0, 1.0);
    if (!AmethystThemeHasBackgroundImage() && !AmethystThemeHasBackgroundVideo()) {
        return 1.0;
    }
    return alpha;
}

static CGFloat AmethystThemeBackgroundBlurOpacity(void) {
    CGFloat alpha = 0.0;
    id value = getPrefObject(@"general.theme_background_blur");
    if ([value respondsToSelector:@selector(doubleValue)]) {
        alpha = [value doubleValue] / 100.0;
    }
    alpha = clamp(alpha, 0.0, 1.0);
    if (!AmethystThemeHasBackgroundImage() && !AmethystThemeHasBackgroundVideo()) {
        return 0.0;
    }
    return alpha;
}

static CGFloat AmethystThemeBackgroundDimOpacity(void) {
    CGFloat alpha = 0.0;
    id value = getPrefObject(@"general.theme_background_dim");
    if ([value respondsToSelector:@selector(doubleValue)]) {
        alpha = [value doubleValue] / 100.0;
    }
    alpha = clamp(alpha, 0.0, 1.0);
    if (!AmethystThemeHasBackgroundImage() && !AmethystThemeHasBackgroundVideo()) {
        return 0.0;
    }
    return alpha;
}

static NSString *AmethystThemeBackgroundScaleKey(void) {
    id value = getPrefObject(@"general.theme_background_scale");
    if (![value isKindOfClass:NSString.class] || [value length] == 0) {
        return @"fit";
    }
    return value;
}

static UIViewContentMode AmethystThemeBackgroundImageContentMode(void) {
    NSString *key = AmethystThemeBackgroundScaleKey();
    if ([key isEqualToString:@"fill"]) {
        return UIViewContentModeScaleAspectFill;
    }
    if ([key isEqualToString:@"center"]) {
        return UIViewContentModeCenter;
    }
    return UIViewContentModeScaleAspectFit;
}

static NSString *AmethystThemeBackgroundVideoGravity(void) {
    NSString *key = AmethystThemeBackgroundScaleKey();
    if ([key isEqualToString:@"fill"]) {
        return AVLayerVideoGravityResizeAspectFill;
    }
    return AVLayerVideoGravityResizeAspect;
}

static BOOL AmethystThemeBackgroundVideoMuted(void) {
    id value = getPrefObject(@"general.theme_background_video_mute");
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return YES;
}

static BOOL AmethystThemeBackgroundVideoLoopEnabled(void) {
    id value = getPrefObject(@"general.theme_background_video_loop");
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return YES;
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
    NSString *overrideKey = AmethystThemeTextColorKey();
    UIColor *base = nil;
    if ([overrideKey isEqualToString:@"accent"]) {
        base = AmethystThemeAccentColor();
    } else if ([overrideKey isEqualToString:@"light"]) {
        base = AmethystDynamicColor(0xF8FAFC, 0xF8FAFC, 1.0);
    } else if ([overrideKey isEqualToString:@"dark"]) {
        base = AmethystDynamicColor(0x111827, 0x111827, 1.0);
    }
    if (!base) {
        const AmethystThemePalette *palette = AmethystCurrentThemePalette();
        base = AmethystDynamicColor(palette->lightTextPrimary, palette->darkTextPrimary, 1.0);
    }
    return [base colorWithAlphaComponent:AmethystThemeTextOpacity()];
}

UIColor* AmethystThemeTextSecondaryColor(void) {
    NSString *overrideKey = AmethystThemeTextColorKey();
    UIColor *base = nil;
    if ([overrideKey isEqualToString:@"accent"]) {
        base = AmethystThemeAccentColor();
    } else if ([overrideKey isEqualToString:@"light"]) {
        base = AmethystDynamicColor(0xF8FAFC, 0xF8FAFC, 1.0);
    } else if ([overrideKey isEqualToString:@"dark"]) {
        base = AmethystDynamicColor(0x111827, 0x111827, 1.0);
    }
    CGFloat alpha = AmethystThemeTextOpacity();
    if (base) {
        return [base colorWithAlphaComponent:alpha * 0.7];
    }
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    base = AmethystDynamicColor(palette->lightTextSecondary, palette->darkTextSecondary, 1.0);
    return [base colorWithAlphaComponent:alpha];
}

UIColor* AmethystThemeSeparatorColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightSeparator, palette->darkSeparator, AmethystThemeBackgroundOpacity());
}

UIColor* AmethystThemeSelectionColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    return AmethystDynamicColor(palette->lightSelection, palette->darkSelection, AmethystThemeBackgroundOpacity());
}

UIColor* AmethystThemeButtonBackgroundColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    CGFloat alpha = AmethystThemeButtonOpacity();
    return AmethystDynamicColor(palette->lightSurface, palette->darkSurface, alpha);
}

UIColor* AmethystThemeButtonSelectionColor(void) {
    const AmethystThemePalette *palette = AmethystCurrentThemePalette();
    CGFloat alpha = AmethystThemeButtonOpacity();
    return AmethystDynamicColor(palette->lightSelection, palette->darkSelection, alpha);
}

UIColor* AmethystThemeButtonBorderColor(void) {
    return [AmethystThemeAccentColor() colorWithAlphaComponent:0.6];
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

        UIBarButtonItem *barButtonProxy = [UIBarButtonItem appearance];
        [barButtonProxy setTitleTextAttributes:@{NSForegroundColorAttributeName: text}
                                      forState:UIControlStateNormal];
        [barButtonProxy setTitleTextAttributes:@{NSForegroundColorAttributeName: text}
                                      forState:UIControlStateHighlighted];

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

        UITableViewHeaderFooterView *headerProxy = [UITableViewHeaderFooterView appearance];
        headerProxy.textLabel.textColor = AmethystThemeTextSecondaryColor();
        if ([headerProxy respondsToSelector:@selector(detailTextLabel)]) {
            headerProxy.detailTextLabel.textColor = AmethystThemeTextSecondaryColor();
        }

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

        UIBarButtonItem *barButtonProxy = [UIBarButtonItem appearance];
        [barButtonProxy setTitleTextAttributes:@{NSForegroundColorAttributeName: text}
                                      forState:UIControlStateNormal];
        [barButtonProxy setTitleTextAttributes:@{NSForegroundColorAttributeName: text}
                                      forState:UIControlStateHighlighted];

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
static char kAmethystThemeBackgroundVideoMutedKey;
static char kAmethystThemeBackgroundVideoLoopKey;
static char kAmethystThemeBackgroundImageViewKey;
static char kAmethystThemeBackgroundPortraitViewKey;
static char kAmethystThemeBackgroundBlurViewKey;
static char kAmethystThemeBackgroundDimViewKey;

static AmethystBackgroundVideoView *AmethystThemeBackgroundVideoView(UIWindow *window) {
    AmethystBackgroundVideoView *view = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoViewKey);
    if (!view) {
        view = [[AmethystBackgroundVideoView alloc] initWithFrame:window.bounds];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.contentMode = AmethystThemeBackgroundImageContentMode();
        view.userInteractionEnabled = NO;
        view.clipsToBounds = YES;
        view.hidden = YES;
        AVPlayerLayer *layer = (AVPlayerLayer *)view.layer;
        layer.videoGravity = AmethystThemeBackgroundVideoGravity();
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
        view.contentMode = AmethystThemeBackgroundImageContentMode();
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

static UIImageView *AmethystThemeBackgroundPortraitView(UIWindow *window) {
    UIImageView *view = objc_getAssociatedObject(window, &kAmethystThemeBackgroundPortraitViewKey);
    if (!view) {
        view = [[UIImageView alloc] initWithFrame:window.bounds];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.contentMode = UIViewContentModeScaleAspectFit;
        view.userInteractionEnabled = NO;
        view.clipsToBounds = YES;
        view.hidden = YES;
        UIView *backgroundView = objc_getAssociatedObject(window, &kAmethystThemeBackgroundImageViewKey);
        if (backgroundView) {
            [window insertSubview:view aboveSubview:backgroundView];
        } else {
            [window insertSubview:view atIndex:0];
        }
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundPortraitViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
}

static UIVisualEffectView *AmethystThemeBackgroundBlurView(UIWindow *window) {
    UIVisualEffectView *view = objc_getAssociatedObject(window, &kAmethystThemeBackgroundBlurViewKey);
    if (!view) {
        UIBlurEffect *effect = nil;
        if (@available(iOS 13.0, *)) {
            effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        } else {
            effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
        }
        view = [[UIVisualEffectView alloc] initWithEffect:effect];
        view.frame = window.bounds;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.userInteractionEnabled = NO;
        view.hidden = YES;
        [window insertSubview:view atIndex:0];
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundBlurViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
}

static UIView *AmethystThemeBackgroundDimView(UIWindow *window) {
    UIView *view = objc_getAssociatedObject(window, &kAmethystThemeBackgroundDimViewKey);
    if (!view) {
        view = [[UIView alloc] initWithFrame:window.bounds];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.userInteractionEnabled = NO;
        view.hidden = YES;
        view.backgroundColor = UIColor.clearColor;
        [window insertSubview:view atIndex:0];
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundDimViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
}

void AmethystApplyThemeToWindow(UIWindow *window) {
    if (!window) return;
    if (@available(iOS 13.0, *)) {
        window.overrideUserInterfaceStyle = AmethystPreferredInterfaceStyle();
    }
    NSString *videoPath = AmethystThemeBackgroundVideoPathForWindow(window);
    AmethystBackgroundVideoView *videoView = AmethystThemeBackgroundVideoView(window);
    UIImageView *backgroundView = AmethystThemeBackgroundImageView(window);
    UIImageView *portraitView = AmethystThemeBackgroundPortraitView(window);
    videoView.contentMode = AmethystThemeBackgroundImageContentMode();
    ((AVPlayerLayer *)videoView.layer).videoGravity = AmethystThemeBackgroundVideoGravity();
    backgroundView.contentMode = AmethystThemeBackgroundImageContentMode();
    portraitView.contentMode = UIViewContentModeScaleAspectFit;
    BOOL hasVideo = NO;
    if (videoPath && [NSFileManager.defaultManager fileExistsAtPath:videoPath]) {
        hasVideo = YES;
        AVPlayerLayer *layer = (AVPlayerLayer *)videoView.layer;
        NSString *currentPath = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoPathKey);
        AVQueuePlayer *player = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoPlayerKey);
        BOOL muted = AmethystThemeBackgroundVideoMuted();
        BOOL loop = AmethystThemeBackgroundVideoLoopEnabled();
        NSNumber *prevMuted = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoMutedKey);
        NSNumber *prevLoop = objc_getAssociatedObject(window, &kAmethystThemeBackgroundVideoLoopKey);
        BOOL needsReload = !currentPath || ![currentPath isEqualToString:videoPath] || !player ||
            (prevMuted && prevMuted.boolValue != muted) ||
            (prevLoop && prevLoop.boolValue != loop);
        if (needsReload) {
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:videoPath]];
            AVQueuePlayer *newPlayer = [AVQueuePlayer queuePlayerWithItems:@[item]];
            newPlayer.muted = muted;
            newPlayer.actionAtItemEnd = loop ? AVPlayerActionAtItemEndNone : AVPlayerActionAtItemEndPause;

            AVPlayerLooper *looper = nil;
            if (loop) {
                looper = [AVPlayerLooper playerLooperWithPlayer:newPlayer templateItem:item];
            }
            objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoPlayerKey, newPlayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoLooperKey, looper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoPathKey, videoPath, OBJC_ASSOCIATION_COPY_NONATOMIC);
            objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoMutedKey, @(muted), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoLoopKey, @(loop), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            layer.player = newPlayer;
            [newPlayer play];
        } else {
            if (layer.player != player) {
                layer.player = player;
            }
            player.muted = muted;
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
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoMutedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window, &kAmethystThemeBackgroundVideoLoopKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSString *imagePath = hasVideo ? nil : AmethystThemeBackgroundImagePathForWindow(window);
    if (imagePath) {
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        if (image) {
            BOOL usePortraitOverlay = AmethystThemeShouldUsePortraitOverlay(window, imagePath, image);
            if (usePortraitOverlay) {
                backgroundView.image = image;
                backgroundView.contentMode = UIViewContentModeScaleAspectFill;
                backgroundView.hidden = NO;

                portraitView.image = image;
                portraitView.contentMode = UIViewContentModeScaleAspectFit;
                portraitView.hidden = NO;
            } else {
                UIImageOrientation rotation = AmethystThemeBackgroundImageOrientationForWindow(window);
                UIImage *displayImage = AmethystThemeImageWithOrientation(image, rotation);
                portraitView.hidden = YES;
                backgroundView.image = displayImage;
                backgroundView.contentMode = AmethystThemeBackgroundImageContentMode();
                backgroundView.hidden = NO;
            }
            [window sendSubviewToBack:backgroundView];
        } else {
            backgroundView.hidden = YES;
            portraitView.hidden = YES;
        }
    } else {
        backgroundView.hidden = YES;
        portraitView.hidden = YES;
    }
    BOOL hasMedia = hasVideo || !backgroundView.hidden || !portraitView.hidden;
    UIVisualEffectView *blurView = AmethystThemeBackgroundBlurView(window);
    CGFloat blurOpacity = hasMedia ? AmethystThemeBackgroundBlurOpacity() : 0.0;
    if (blurOpacity > 0.001) {
        blurView.hidden = NO;
        blurView.alpha = blurOpacity;
        UIView *anchorView = !backgroundView.hidden ? backgroundView : videoView;
        if (anchorView && blurView.superview == window) {
            [window insertSubview:blurView aboveSubview:anchorView];
        }
    } else {
        blurView.hidden = YES;
    }
    if (!portraitView.hidden) {
        UIView *anchorView = !blurView.hidden ? blurView : (!backgroundView.hidden ? backgroundView : videoView);
        if (anchorView && portraitView.superview == window) {
            [window insertSubview:portraitView aboveSubview:anchorView];
        }
    }
    UIView *dimView = AmethystThemeBackgroundDimView(window);
    CGFloat dimOpacity = hasMedia ? AmethystThemeBackgroundDimOpacity() : 0.0;
    if (dimOpacity > 0.001) {
        dimView.hidden = NO;
        dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:dimOpacity];
        UIView *anchorView = !portraitView.hidden ? portraitView : (!blurView.hidden ? blurView : (!backgroundView.hidden ? backgroundView : videoView));
        if (anchorView && dimView.superview == window) {
            [window insertSubview:dimView aboveSubview:anchorView];
        }
    } else {
        dimView.hidden = YES;
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
