#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "DBNumberedSlider.h"
#import "HostManagerBridge.h"
#import "LauncherNavigationController.h"
#import "LauncherMenuViewController.h"
#import "LauncherPreferences.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherSplitViewController.h"
#import "LauncherPrefContCfgViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "UIKit+hook.h"

#import "config.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface LauncherPreferencesViewController()<UIDocumentPickerDelegate>
@property(nonatomic) NSArray<NSString*> *rendererKeys, *rendererList;
@property(nonatomic) BOOL pickingThemeVideo;
@property(nonatomic) BOOL pickingThemeVideoLandscape;
@property(nonatomic) BOOL pickingThemeImageLandscape;
@end

@implementation LauncherPreferencesViewController

- (void)applyThemeChangesAndReload {
    AmethystApplyThemeAppearance();
    AmethystApplyThemeToWindow(UIWindow.mainWindow);
    AmethystApplyThemeToWindow(UIWindow.externalWindow);
    [self.tableView reloadData];
}

- (id)init {
    self = [super init];
    self.title = localize(@"Settings", nil);
    return self;
}

- (NSString *)imageName {
    return @"MenuSettings";
}

- (NSString *)themeBackgroundDirectory {
    return [NSString stringWithFormat:@"%s/theme", getenv("POJAV_HOME")];
}

- (void)viewDidLoad
{
    self.getPreference = ^id(NSString *section, NSString *key){
        NSString *keyFull = [NSString stringWithFormat:@"%@.%@", section, key];
        return getPrefObject(keyFull);
    };
    self.setPreference = ^(NSString *section, NSString *key, id value){
        NSString *keyFull = [NSString stringWithFormat:@"%@.%@", section, key];
        setPrefObject(keyFull, value);
    };
    
    self.hasDetail = YES;
    self.prefDetailVisible = self.navigationController == nil;
    
    self.prefSections = @[@"general", @"theme", @"video", @"control", @"java", @"debug"];

    self.rendererKeys = getRendererKeys(NO);
    self.rendererList = getRendererNames(NO);

    __weak __typeof(self) weakSelf = self;
    BOOL(^whenNotInGame)() = ^BOOL(){
        return self.navigationController != nil;
    };
    void(^applyThemeChanges)(void) = ^void() {
        [weakSelf applyThemeChangesAndReload];
        if (sidebarViewController) {
            [sidebarViewController applyMenuPreferences];
        }
    };
    void(^applyMenuChanges)(void) = ^void() {
        if (sidebarViewController) {
            [sidebarViewController applyMenuPreferences];
        }
        if ([weakSelf.splitViewController isKindOfClass:LauncherSplitViewController.class]) {
            [(LauncherSplitViewController *)weakSelf.splitViewController applySidebarPreferences];
        }
    };
    BOOL(^hasThemeImagePortrait)(void) = ^BOOL() {
        NSString *path = getPrefObject(@"general.theme_background_image");
        return [path isKindOfClass:NSString.class] && path.length > 0;
    };
    BOOL(^hasThemeImageLandscape)(void) = ^BOOL() {
        NSString *path = getPrefObject(@"general.theme_background_image_landscape");
        return [path isKindOfClass:NSString.class] && path.length > 0;
    };
    BOOL(^hasThemeImage)(void) = ^BOOL() {
        return hasThemeImagePortrait() || hasThemeImageLandscape();
    };
    BOOL(^hasThemeVideo)(void) = ^BOOL() {
        NSString *videoPath = getPrefObject(@"general.theme_background_video");
        if ([videoPath isKindOfClass:NSString.class] && videoPath.length > 0) {
            return YES;
        }
        NSString *landscapePath = getPrefObject(@"general.theme_background_video_landscape");
        return [landscapePath isKindOfClass:NSString.class] && landscapePath.length > 0;
    };
    BOOL(^hasThemeMedia)(void) = ^BOOL() {
        return hasThemeImage() || hasThemeVideo();
    };
    self.prefContents = @[
        @[
            // General settings
            @{@"icon": @"cube"},
            @{@"key": @"check_sha",
              @"hasDetail": @YES,
              @"icon": @"lock.shield",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"cosmetica",
              @"hasDetail": @YES,
              @"icon": @"eyeglasses",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"debug_logging",
              @"hasDetail": @YES,
              @"icon": @"doc.badge.gearshape",
              @"type": self.typeSwitch,
              @"action": ^(BOOL enabled){
                  debugLogEnabled = enabled;
                  NSLog(@"[Debugging] Debug log enabled: %@", enabled ? @"YES" : @"NO");
              }
            },
            @{@"key": @"appicon",
              @"hasDetail": @YES,
              @"icon": @"paintbrush",
              @"type": self.typePickField,
              @"enableCondition": ^BOOL(){
                  return UIApplication.sharedApplication.supportsAlternateIcons;
              },
              @"action": ^void(NSString *iconName) {
                  if ([iconName isEqualToString:@"AppIcon-Light"]) {
                      iconName = nil;
                  }
                  [UIApplication.sharedApplication setAlternateIconName:iconName completionHandler:^(NSError * _Nullable error) {
                      if (error == nil) return;
                      NSLog(@"Error in appicon: %@", error);
                      showDialog(localize(@"Error", nil), error.localizedDescription);
                  }];
              },
              @"pickKeys": @[
                  @"AppIcon-Light",
              ],
              @"pickList": @[
                  localize(@"preference.title.appicon-default", nil)
              ]
            },
            @{@"key": @"hidden_sidebar",
              @"hasDetail": @YES,
              @"icon": @"sidebar.leading",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_compact",
              @"hasDetail": @YES,
              @"icon": @"list.bullet.rectangle",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_show_icons",
              @"hasDetail": @YES,
              @"icon": @"square.grid.2x2",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_show_account",
              @"hasDetail": @YES,
              @"icon": @"person.crop.circle",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_show_news",
              @"hasDetail": @YES,
              @"icon": @"newspaper",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_show_profiles",
              @"hasDetail": @YES,
              @"icon": @"person.2",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_show_settings",
              @"hasDetail": @YES,
              @"icon": @"gearshape",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_show_custom_controls",
              @"hasDetail": @YES,
              @"icon": @"hand.tap",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_show_mod_installer",
              @"hasDetail": @YES,
              @"icon": @"shippingbox",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"menu_show_send_logs",
              @"hasDetail": @YES,
              @"icon": @"square.and.arrow.up",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  applyMenuChanges();
              }
            },
            @{@"key": @"reduce_motion",
              @"hasDetail": @YES,
              @"icon": @"figure.walk",
              @"type": self.typeSwitch
            },
            @{@"key": @"settings_compact_rows",
              @"hasDetail": @YES,
              @"icon": @"line.3.horizontal",
              @"type": self.typeSwitch,
              @"requestReload": @YES
            },
            @{@"key": @"settings_show_icons",
              @"hasDetail": @YES,
              @"icon": @"square.grid.2x2",
              @"type": self.typeSwitch,
              @"requestReload": @YES
            },
            @{@"key": @"reset_warnings",
              @"icon": @"exclamationmark.triangle",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  resetWarnings();
              }
            },
            @{@"key": @"reset_settings",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"requestReload": @YES,
              @"showConfirmPrompt": @YES,
              @"destructive": @YES,
              @"action": ^void(){
                  loadPreferences(YES);
                  [self.tableView reloadData];
              }
            },
            @{@"key": @"erase_demo_data",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"enableCondition": ^BOOL(){
                  NSString *demoPath = [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")];
                  int count = [NSFileManager.defaultManager contentsOfDirectoryAtPath:demoPath error:nil].count;
                  return whenNotInGame() && count > 0;
              },
              @"showConfirmPrompt": @YES,
              @"destructive": @YES,
              @"action": ^void(){
                  NSString *demoPath = [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")];
                  NSError *error;
                  if([NSFileManager.defaultManager removeItemAtPath:demoPath error:&error]) {
                      [NSFileManager.defaultManager createDirectoryAtPath:demoPath
                                              withIntermediateDirectories:YES attributes:nil error:nil];
                      [NSFileManager.defaultManager changeCurrentDirectoryPath:demoPath];
                      if (getenv("DEMO_LOCK")) {
                          [(LauncherNavigationController *)self.navigationController fetchLocalVersionList];
                      }
                  } else {
                      NSLog(@"Error in erase_demo_data: %@", error);
                      showDialog(localize(@"Error", nil), error.localizedDescription);
                  }
              }
            }
        ], @[
            // Theme settings
            @{@"icon": @"paintpalette"},
            @{@"key": @"theme_palette",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"paintbrush.pointed",
              @"type": self.typePickField,
              @"pickKeys": @[
                  @"amethyst",
                  @"midnight",
                  @"warm",
                  @"ocean",
                  @"forest",
                  @"sakura",
                  @"oled"
              ],
              @"pickList": @[
                  localize(@"preference.pick.theme_palette.amethyst", nil),
                  localize(@"preference.pick.theme_palette.midnight", nil),
                  localize(@"preference.pick.theme_palette.warm", nil),
                  localize(@"preference.pick.theme_palette.ocean", nil),
                  localize(@"preference.pick.theme_palette.forest", nil),
                  localize(@"preference.pick.theme_palette.sakura", nil),
                  localize(@"preference.pick.theme_palette.oled", nil)
              ],
              @"action": ^(NSString *value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_accent",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"paintpalette",
              @"type": self.typePickField,
              @"pickKeys": @[
                  @"teal",
                  @"blue",
                  @"indigo",
                  @"cyan",
                  @"purple",
                  @"pink",
                  @"rose",
                  @"orange",
                  @"yellow",
                  @"red",
                  @"green",
                  @"lime",
                  @"mono"
              ],
              @"pickList": @[
                  localize(@"preference.pick.theme_accent.teal", nil),
                  localize(@"preference.pick.theme_accent.blue", nil),
                  localize(@"preference.pick.theme_accent.indigo", nil),
                  localize(@"preference.pick.theme_accent.cyan", nil),
                  localize(@"preference.pick.theme_accent.purple", nil),
                  localize(@"preference.pick.theme_accent.pink", nil),
                  localize(@"preference.pick.theme_accent.rose", nil),
                  localize(@"preference.pick.theme_accent.orange", nil),
                  localize(@"preference.pick.theme_accent.yellow", nil),
                  localize(@"preference.pick.theme_accent.red", nil),
                  localize(@"preference.pick.theme_accent.green", nil),
                  localize(@"preference.pick.theme_accent.lime", nil),
                  localize(@"preference.pick.theme_accent.mono", nil)
              ],
              @"action": ^(NSString *value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_mode",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"circle.lefthalf.filled",
              @"type": self.typePickField,
              @"pickKeys": @[
                  @"system",
                  @"light",
                  @"dark"
              ],
              @"pickList": @[
                  localize(@"preference.pick.theme_mode.system", nil),
                  localize(@"preference.pick.theme_mode.light", nil),
                  localize(@"preference.pick.theme_mode.dark", nil)
              ],
              @"action": ^(NSString *value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_text_color",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"textformat",
              @"type": self.typePickField,
              @"pickKeys": @[
                  @"default",
                  @"light",
                  @"dark",
                  @"accent"
              ],
              @"pickList": @[
                  localize(@"preference.pick.theme_text_color.default", nil),
                  localize(@"preference.pick.theme_text_color.light", nil),
                  localize(@"preference.pick.theme_text_color.dark", nil),
                  localize(@"preference.pick.theme_text_color.accent", nil)
              ],
              @"action": ^(NSString *value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_text_opacity",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"textformat.size",
              @"type": self.typeSlider,
              @"continuous": @NO,
              @"min": @(0),
              @"max": @(100),
              @"action": ^(int value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_button_opacity",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"square.opacity",
              @"type": self.typeSlider,
              @"continuous": @NO,
              @"min": @(0),
              @"max": @(100),
              @"action": ^(int value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_button_outline",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"square.dashed",
              @"type": self.typeSwitch,
              @"action": ^(BOOL enabled){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_button_corner_radius",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"square",
              @"type": self.typeSlider,
              @"continuous": @NO,
              @"min": @(0),
              @"max": @(30),
              @"action": ^(int value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_button_border_width",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"line.3.horizontal.decrease",
              @"type": self.typeSlider,
              @"continuous": @NO,
              @"min": @(0),
              @"max": @(6),
              @"action": ^(int value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_background_image",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"photo.on.rectangle",
              @"type": self.typeButton,
              @"skipActionAlert": @YES,
              @"action": ^void(){
                  [weakSelf actionPickThemeBackgroundImage];
              }
            },
            @{@"key": @"theme_background_image_landscape",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"rectangle.landscape",
              @"type": self.typeButton,
              @"skipActionAlert": @YES,
              @"action": ^void(){
                  [weakSelf actionPickThemeBackgroundImageLandscape];
              }
            },
            @{@"key": @"theme_background_video",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"video",
              @"type": self.typeButton,
              @"skipActionAlert": @YES,
              @"action": ^void(){
                  [weakSelf actionPickThemeBackgroundVideo];
              }
            },
            @{@"key": @"theme_background_video_landscape",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"rectangle.landscape",
              @"type": self.typeButton,
              @"skipActionAlert": @YES,
              @"action": ^void(){
                  [weakSelf actionPickThemeBackgroundVideoLandscape];
              }
            },
            @{@"key": @"theme_background_video_mute",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"speaker.slash",
              @"type": self.typeSwitch,
              @"enableCondition": hasThemeVideo,
              @"action": ^(BOOL enabled){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_background_video_loop",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"repeat",
              @"type": self.typeSwitch,
              @"enableCondition": hasThemeVideo,
              @"action": ^(BOOL enabled){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_background_clear",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"destructive": @YES,
              @"skipActionAlert": @YES,
              @"enableCondition": hasThemeImagePortrait,
              @"action": ^void(){
                  [weakSelf actionClearThemeBackgroundImage];
              }
            },
            @{@"key": @"theme_background_clear_landscape",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"destructive": @YES,
              @"skipActionAlert": @YES,
              @"enableCondition": hasThemeImageLandscape,
              @"action": ^void(){
                  [weakSelf actionClearThemeBackgroundImageLandscape];
              }
            },
            @{@"key": @"theme_background_clear_video",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"destructive": @YES,
              @"skipActionAlert": @YES,
              @"enableCondition": hasThemeVideo,
              @"action": ^void(){
                  [weakSelf actionClearThemeBackgroundVideo];
              }
            },
            @{@"key": @"theme_background_clear_video_landscape",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"destructive": @YES,
              @"skipActionAlert": @YES,
              @"enableCondition": hasThemeVideo,
              @"action": ^void(){
                  [weakSelf actionClearThemeBackgroundVideoLandscape];
              }
            },
            @{@"key": @"theme_background_opacity",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"slider.horizontal.3",
              @"type": self.typeSlider,
              @"enableCondition": hasThemeMedia,
              @"continuous": @NO,
              @"min": @(0),
              @"max": @(100),
              @"action": ^(int value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_background_blur",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"drop",
              @"type": self.typeSlider,
              @"enableCondition": hasThemeMedia,
              @"continuous": @NO,
              @"min": @(0),
              @"max": @(100),
              @"action": ^(int value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_background_dim",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"moon.fill",
              @"type": self.typeSlider,
              @"enableCondition": hasThemeMedia,
              @"continuous": @NO,
              @"min": @(0),
              @"max": @(100),
              @"action": ^(int value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_background_scale",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"arrow.up.left.and.arrow.down.right",
              @"type": self.typePickField,
              @"enableCondition": hasThemeMedia,
              @"pickKeys": @[
                  @"fill",
                  @"fit",
                  @"center"
              ],
              @"pickList": @[
                  localize(@"preference.pick.theme_background_scale.fill", nil),
                  localize(@"preference.pick.theme_background_scale.fit", nil),
                  localize(@"preference.pick.theme_background_scale.center", nil)
              ],
              @"action": ^(NSString *value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_background_rotation_portrait",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"rotate.right",
              @"type": self.typePickField,
              @"enableCondition": hasThemeImage,
              @"pickKeys": @[
                  @"portrait",
                  @"landscape",
                  @"landscape_left",
                  @"landscape_right"
              ],
              @"pickList": @[
                  localize(@"preference.pick.theme_background_rotation.portrait", nil),
                  localize(@"preference.pick.theme_background_rotation.landscape", nil),
                  localize(@"preference.pick.theme_background_rotation.left", nil),
                  localize(@"preference.pick.theme_background_rotation.right", nil)
              ],
              @"action": ^(NSString *value){
                  applyThemeChanges();
              }
            },
            @{@"key": @"theme_background_rotation_landscape",
              @"section": @"general",
              @"hasDetail": @YES,
              @"icon": @"rotate.right",
              @"type": self.typePickField,
              @"enableCondition": hasThemeImage,
              @"pickKeys": @[
                  @"portrait",
                  @"landscape",
                  @"landscape_left",
                  @"landscape_right"
              ],
              @"pickList": @[
                  localize(@"preference.pick.theme_background_rotation.portrait", nil),
                  localize(@"preference.pick.theme_background_rotation.landscape", nil),
                  localize(@"preference.pick.theme_background_rotation.left", nil),
                  localize(@"preference.pick.theme_background_rotation.right", nil)
              ],
              @"action": ^(NSString *value){
                  applyThemeChanges();
              }
            }
        ], @[
            // Video and renderer settings
            @{@"icon": @"video"},
            @{@"key": @"renderer",
              @"hasDetail": @YES,
              @"icon": @"cpu",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": self.rendererKeys,
              @"pickList": self.rendererList
            },
            @{@"key": @"resolution",
              @"hasDetail": @YES,
              @"icon": @"viewfinder",
              @"type": self.typeSlider,
              @"min": @(25),
              @"max": @(150)
            },
            @{@"key": @"max_framerate",
              @"hasDetail": @YES,
              @"icon": @"timelapse",
              @"type": self.typeSwitch,
              @"enableCondition": ^BOOL(){
                  return whenNotInGame() && (UIScreen.mainScreen.maximumFramesPerSecond > 60);
              }
            },
            @{@"key": @"performance_hud",
              @"hasDetail": @YES,
              @"icon": @"waveform.path.ecg",
              @"type": self.typeSwitch,
              @"enableCondition": ^BOOL(){
                  return [CAMetalLayer instancesRespondToSelector:@selector(developerHUDProperties)];
              }
            },
            @{@"key": @"fullscreen_airplay",
              @"hasDetail": @YES,
              @"icon": @"airplayvideo",
              @"type": self.typeSwitch,
              @"action": ^(BOOL enabled){
                  if (self.navigationController != nil) return;
                  if (UIApplication.sharedApplication.connectedScenes.count < 2) return;
                  if (enabled) {
                      [self.presentingViewController performSelector:@selector(switchToExternalDisplay)];
                  } else {
                      [self.presentingViewController performSelector:@selector(switchToInternalDisplay)];
                  }
              }
            },
            @{@"key": @"silence_other_audio",
              @"hasDetail": @YES,
              @"icon": @"speaker.slash",
              @"type": self.typeSwitch
            },
            @{@"key": @"silence_with_switch",
              @"hasDetail": @YES,
              @"icon": @"speaker.zzz",
              @"type": self.typeSwitch
            },
            @{@"key": @"allow_microphone",
              @"hasDetail": @YES,
              @"icon": @"mic",
              @"type": self.typeSwitch
            },
        ], @[
            // Control settings
            @{@"icon": @"gamecontroller"},
            @{@"key": @"default_gamepad_ctrl",
                @"icon": @"hammer",
                @"type": self.typeChildPane,
                @"enableCondition": whenNotInGame,
                @"canDismissWithSwipe": @NO,
                @"class": LauncherPrefContCfgViewController.class
            },
            @{@"key": @"hardware_hide",
                @"icon": @"eye.slash",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"recording_hide",
                @"icon": @"eye.slash",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"gesture_mouse_tap_hold",
                @"icon": @"hand.tap",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"gesture_mouse_scroll",
                @"icon": @"arrow.up.and.down",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"gesture_hotbar",
                @"icon": @"hand.tap",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"disable_haptics",
                @"icon": @"wave.3.left",
                @"hasDetail": @NO,
                @"type": self.typeSwitch,
            },
            @{@"key": @"slideable_hotbar",
                @"hasDetail": @YES,
                @"icon": @"slider.horizontal.below.rectangle",
                @"type": self.typeSwitch
            },
            @{@"key": @"press_duration",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.click.badge.clock",
                @"type": self.typeSlider,
                @"min": @(100),
                @"max": @(1000),
            },
            @{@"key": @"button_scale",
                @"hasDetail": @YES,
                @"icon": @"aspectratio",
                @"type": self.typeSlider,
                @"min": @(50), // 80?
                @"max": @(500)
            },
            @{@"key": @"mouse_scale",
                @"hasDetail": @YES,
                @"icon": @"arrow.up.left.and.arrow.down.right.circle",
                @"type": self.typeSlider,
                @"min": @(25),
                @"max": @(300)
            },
            @{@"key": @"mouse_speed",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.motionlines",
                @"type": self.typeSlider,
                @"min": @(25),
                @"max": @(300)
            },
            @{@"key": @"virtmouse_enable",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.rays",
                @"type": self.typeSwitch
            },
            @{@"key": @"gyroscope_enable",
                @"hasDetail": @YES,
                @"icon": @"gyroscope",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            },
            @{@"key": @"gyroscope_invert_x_axis",
                @"hasDetail": @YES,
                @"icon": @"arrow.left.and.right",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            },
            @{@"key": @"gyroscope_sensitivity",
                @"hasDetail": @YES,
                @"icon": @"move.3d",
                @"type": self.typeSlider,
                @"min": @(50),
                @"max": @(300),
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            }
        ], @[
        // Java tweaks
            @{@"icon": @"sparkles"},
            @{@"key": @"manage_runtime",
                @"hasDetail": @YES,
                @"icon": @"cube",
                @"type": self.typeChildPane,
                @"canDismissWithSwipe": @YES,
                @"class": LauncherPrefManageJREViewController.class,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"java_args",
                @"hasDetail": @YES,
                @"icon": @"slider.vertical.3",
                @"type": self.typeTextField,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"env_variables",
                @"hasDetail": @YES,
                @"icon": @"terminal",
                @"type": self.typeTextField,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"auto_ram",
                @"hasDetail": @YES,
                @"icon": @"slider.horizontal.3",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame,
                @"warnCondition": ^BOOL(){
                    return !isJailbroken;
                },
                @"warnKey": @"auto_ram_warn",
                @"requestReload": @YES
            },
            @{@"key": @"allocated_memory",
                @"hasDetail": @YES,
                @"icon": @"memorychip",
                @"type": self.typeSlider,
                @"min": @(250),
                @"max": @((NSProcessInfo.processInfo.physicalMemory / 1048576) * 0.85),
                @"enableCondition": ^BOOL(){
                    return !getPrefBool(@"java.auto_ram") && whenNotInGame();
                },
                @"warnCondition": ^BOOL(DBNumberedSlider *view){
                    return view.value >= NSProcessInfo.processInfo.physicalMemory / 1048576 * 0.37;
                },
                @"warnKey": @"mem_warn"
            }
        ], @[
            // Debug settings - only recommended for developer use
            @{@"icon": @"ladybug"},
            @{@"key": @"debug_always_attached_jit",
                @"hasDetail": @YES,
                @"icon": @"app.connected.to.app.below.fill",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return DeviceRequiresTXMWorkaround() && whenNotInGame();
                },
            },
            @{@"key": @"debug_skip_wait_jit",
                @"hasDetail": @YES,
                @"icon": @"forward",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"debug_hide_home_indicator",
                @"hasDetail": @YES,
                @"icon": @"iphone.and.arrow.forward",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return
                        self.splitViewController.view.safeAreaInsets.bottom > 0 ||
                        self.view.safeAreaInsets.bottom > 0;
                }
            },
            @{@"key": @"debug_ipad_ui",
                @"hasDetail": @YES,
                @"icon": @"ipad",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"debug_auto_correction",
                @"hasDetail": @YES,
                @"icon": @"textformat.abc.dottedunderline",
                @"type": self.typeSwitch
            }
        ]
    ];

    [super viewDidLoad];
    if (self.navigationController == nil) {
        self.tableView.alpha = 0.9;
    }
    if (NSProcessInfo.processInfo.isMacCatalystApp) {
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeClose];
        closeButton.frame = CGRectOffset(closeButton.frame, 10, 10);
        [closeButton addTarget:self action:@selector(actionClose) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:closeButton];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.navigationController == nil) {
        [self.presentingViewController performSelector:@selector(updatePreferenceChanges)];
    }
}

- (void)actionClose {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark UITableView

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) { // Add to general section
        return [NSString stringWithFormat:@"Angel Aura Amethyst %@-%s (%s/%s)\n%@ on %@ (%s)\nPID: %d",
            NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
            CONFIG_TYPE, CONFIG_BRANCH, CONFIG_COMMIT,
            UIDevice.currentDevice.completeOSVersion, [HostManager GetModelName], getenv("POJAV_DETECTEDINST"), getpid()];
    }

    NSString *footer = NSLocalizedStringWithDefaultValue(([NSString stringWithFormat:@"preference.section.footer.%@", self.prefSections[section]]), @"Localizable", NSBundle.mainBundle, @" ", nil);
    if ([footer isEqualToString:@" "]) {
        return nil;
    }
    return footer;
}

- (void)actionPickThemeBackgroundImage {
    self.pickingThemeVideo = NO;
    self.pickingThemeVideoLandscape = NO;
    self.pickingThemeImageLandscape = NO;
    UTType *imageType = [UTType typeWithIdentifier:@"public.image"];
    if (!imageType) {
        showDialog(localize(@"Error", nil), @"Image picker is unavailable.");
        return;
    }
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[imageType] asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)actionPickThemeBackgroundImageLandscape {
    self.pickingThemeVideo = NO;
    self.pickingThemeVideoLandscape = NO;
    self.pickingThemeImageLandscape = YES;
    UTType *imageType = [UTType typeWithIdentifier:@"public.image"];
    if (!imageType) {
        showDialog(localize(@"Error", nil), @"Image picker is unavailable.");
        return;
    }
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[imageType] asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)actionPickThemeBackgroundVideo {
    self.pickingThemeVideo = YES;
    self.pickingThemeVideoLandscape = NO;
    self.pickingThemeImageLandscape = NO;
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *movieType = [UTType typeWithIdentifier:@"public.movie"];
    if (movieType) {
        [types addObject:movieType];
    }
    UTType *videoType = [UTType typeWithIdentifier:@"public.video"];
    if (videoType && ![types containsObject:videoType]) {
        [types addObject:videoType];
    }
    if (types.count == 0) {
        self.pickingThemeVideo = NO;
        self.pickingThemeVideoLandscape = NO;
        showDialog(localize(@"Error", nil), @"Video picker is unavailable.");
        return;
    }
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:types asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)actionPickThemeBackgroundVideoLandscape {
    self.pickingThemeVideo = YES;
    self.pickingThemeVideoLandscape = YES;
    self.pickingThemeImageLandscape = NO;
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *movieType = [UTType typeWithIdentifier:@"public.movie"];
    if (movieType) {
        [types addObject:movieType];
    }
    UTType *videoType = [UTType typeWithIdentifier:@"public.video"];
    if (videoType && ![types containsObject:videoType]) {
        [types addObject:videoType];
    }
    if (types.count == 0) {
        self.pickingThemeVideo = NO;
        self.pickingThemeVideoLandscape = NO;
        showDialog(localize(@"Error", nil), @"Video picker is unavailable.");
        return;
    }
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:types asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)actionClearThemeBackgroundImage {
    NSString *currentPath = getPrefObject(@"general.theme_background_image");
    if ([currentPath isKindOfClass:NSString.class] && currentPath.length > 0) {
        [NSFileManager.defaultManager removeItemAtPath:currentPath error:nil];
    }
    setPrefObject(@"general.theme_background_image", @"");
    [self applyThemeChangesAndReload];
}

- (void)actionClearThemeBackgroundImageLandscape {
    NSString *currentPath = getPrefObject(@"general.theme_background_image_landscape");
    if ([currentPath isKindOfClass:NSString.class] && currentPath.length > 0) {
        [NSFileManager.defaultManager removeItemAtPath:currentPath error:nil];
    }
    setPrefObject(@"general.theme_background_image_landscape", @"");
    [self applyThemeChangesAndReload];
}

- (void)actionClearThemeBackgroundVideo {
    NSString *currentPath = getPrefObject(@"general.theme_background_video");
    if ([currentPath isKindOfClass:NSString.class] && currentPath.length > 0) {
        [NSFileManager.defaultManager removeItemAtPath:currentPath error:nil];
    }
    setPrefObject(@"general.theme_background_video", @"");
    [self applyThemeChangesAndReload];
}

- (void)actionClearThemeBackgroundVideoLandscape {
    NSString *currentPath = getPrefObject(@"general.theme_background_video_landscape");
    if ([currentPath isKindOfClass:NSString.class] && currentPath.length > 0) {
        [NSFileManager.defaultManager removeItemAtPath:currentPath error:nil];
    }
    setPrefObject(@"general.theme_background_video_landscape", @"");
    [self applyThemeChangesAndReload];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.pickingThemeVideo = NO;
    self.pickingThemeVideoLandscape = NO;
    self.pickingThemeImageLandscape = NO;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [url startAccessingSecurityScopedResource];
    BOOL pickingVideo = self.pickingThemeVideo;
    BOOL pickingVideoLandscape = self.pickingThemeVideoLandscape;
    BOOL pickingImageLandscape = self.pickingThemeImageLandscape;
    self.pickingThemeVideo = NO;
    self.pickingThemeVideoLandscape = NO;
    self.pickingThemeImageLandscape = NO;

    NSString *themeDir = [self themeBackgroundDirectory];
    [NSFileManager.defaultManager createDirectoryAtPath:themeDir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];

    NSString *extension = url.pathExtension.length > 0 ? url.pathExtension : (pickingVideo ? @"mp4" : @"png");
    NSString *baseName = @"background";
    if (pickingVideo) {
        baseName = pickingVideoLandscape ? @"background-video-landscape" : @"background-video";
    } else if (pickingImageLandscape) {
        baseName = @"background-landscape";
    }
    NSString *destPath = [themeDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseName, extension]];

    NSString *prefKey = @"general.theme_background_image";
    if (pickingVideo) {
        prefKey = pickingVideoLandscape ? @"general.theme_background_video_landscape" : @"general.theme_background_video";
    } else if (pickingImageLandscape) {
        prefKey = @"general.theme_background_image_landscape";
    }
    NSString *previousPath = getPrefObject(prefKey);
    if ([previousPath isKindOfClass:NSString.class] && previousPath.length > 0 && ![previousPath isEqualToString:destPath]) {
        [NSFileManager.defaultManager removeItemAtPath:previousPath error:nil];
    }

    [NSFileManager.defaultManager removeItemAtPath:destPath error:nil];
    NSError *copyError = nil;
    if (![NSFileManager.defaultManager copyItemAtPath:url.path toPath:destPath error:&copyError]) {
        [url stopAccessingSecurityScopedResource];
        showDialog(localize(@"Error", nil), copyError.localizedDescription);
        return;
    }

    [url stopAccessingSecurityScopedResource];

    setPrefObject(prefKey, destPath);
    [self applyThemeChangesAndReload];
}

@end
