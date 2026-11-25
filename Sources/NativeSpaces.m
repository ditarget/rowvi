#import "NativeSpaces.h"
#import <dlfcn.h>
#import <objc/message.h>

static void *skyLight(void) {
    static void *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    });
    return library;
}

static int connection(void) {
    void *library = skyLight();
    int (*mainConnection)(void) = library ? dlsym(library, "SLSMainConnectionID") : NULL;
    return mainConnection ? mainConnection() : 0;
}

NSArray<NSDictionary *> *WLCopyDisplays(void) {
    int cid = connection();
    CFArrayRef (*copy)(int) = cid ? dlsym(skyLight(), "SLSCopyManagedDisplaySpaces") : NULL;
    return copy ? CFBridgingRelease(copy(cid)) : nil;
}

NSArray<NSNumber *> *WLCopyWindowSpaces(CGWindowID window) {
    int cid = connection();
    CFArrayRef (*copy)(int, int, CFArrayRef) = cid ? dlsym(skyLight(), "SLSCopySpacesForWindows") : NULL;
    return copy ? CFBridgingRelease(copy(cid, 7, (__bridge CFArrayRef)@[@(window)])) : nil;
}

CGWindowID WLWindowID(AXUIElementRef window) {
    AXError (*getWindow)(AXUIElementRef, CGWindowID *) = dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    CGWindowID id = 0;
    if (getWindow) getWindow(window, &id);
    return id;
}

@protocol WLBridgedOperation
- (instancetype)initWithWindows:(NSArray<NSNumber *> *)windows spaceID:(uint64_t)space;
- (instancetype)initWithSpaceID:(uint64_t)space displayIdentifier:(NSString *)display index:(uint64_t)index;
- (void)performWithWMBridgeDelegate;
@end

BOOL WLMoveWindow(CGWindowID window, uint64_t space) {
    if (!skyLight()) return NO;
    Class type = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
    if (![type instancesRespondToSelector:@selector(initWithWindows:spaceID:)] ||
        ![type instancesRespondToSelector:@selector(performWithWMBridgeDelegate)]) return NO;
    id<WLBridgedOperation> operation = [(id<WLBridgedOperation>)[type alloc] initWithWindows:@[@(window)] spaceID:space];
    if (!operation) return NO;
    [operation performWithWMBridgeDelegate];
    return YES;
}

BOOL WLMoveSpace(uint64_t space, NSString *display, uint64_t index) {
    if (!skyLight()) return NO;
    Class type = NSClassFromString(@"SLSBridgedMoveManagedSpaceToDisplayIndexOperation");
    if (![type instancesRespondToSelector:@selector(initWithSpaceID:displayIdentifier:index:)] ||
        ![type instancesRespondToSelector:@selector(performWithWMBridgeDelegate)]) return NO;
    id<WLBridgedOperation> operation = [(id<WLBridgedOperation>)[type alloc] initWithSpaceID:space displayIdentifier:display index:index];
    if (!operation) return NO;
    [operation performWithWMBridgeDelegate];
    return YES;
}

BOOL WLToggleMissionControl(void) {
    int (*notify)(CFStringRef, void *) = dlsym(RTLD_DEFAULT, "CoreDockSendNotification");
    return notify && notify(CFSTR("com.apple.expose.awake"), NULL) == 0;
}
