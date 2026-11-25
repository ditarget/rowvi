#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

NS_ASSUME_NONNULL_BEGIN
NSArray<NSDictionary *> * _Nullable WLCopyDisplays(void);
NSArray<NSNumber *> * _Nullable WLCopyWindowSpaces(CGWindowID window);
CGWindowID WLWindowID(AXUIElementRef window);
BOOL WLMoveWindow(CGWindowID window, uint64_t space);
BOOL WLMoveSpace(uint64_t space, NSString *display, uint64_t index);
BOOL WLToggleMissionControl(void);
NS_ASSUME_NONNULL_END
