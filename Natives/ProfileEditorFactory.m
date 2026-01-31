#import "ProfileEditorFactory.h"

UIViewController *CreateProfileEditorViewController(NSDictionary *profile) {
    Class cls = NSClassFromString(@"LauncherProfileEditorViewController");
    if (!cls) {
        return nil;
    }

    UIViewController *viewController = [cls new];
    if (profile && [viewController respondsToSelector:@selector(setProfile:)]) {
        [viewController setValue:profile.mutableCopy forKey:@"profile"];
    }
    return viewController;
}
