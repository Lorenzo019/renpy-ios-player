/*
 * Dichiarazioni minime di UIKit / CoreFoundation / dispatch, copiate dalle
 * firme Apple, usate SOLO per un controllo di sintassi su Linux
 * (tests/objc_syntax_check.sh). Non fanno parte dell'app.
 */

#import <Foundation/Foundation.h>

#define NS_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#define NS_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")
#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

/* ---- CoreGraphics / CoreFoundation ------------------------------------- */
typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { CGRect r = { { x, y }, { w, h } }; return r; }
static inline CGSize CGSizeMake(CGFloat w, CGFloat h) { CGSize s = { w, h }; return s; }

typedef const struct __CFString *CFStringRef;
typedef unsigned char Boolean;
typedef double CFTimeInterval;
typedef double CFAbsoluteTime;
extern const CFStringRef kCFRunLoopDefaultMode;
extern int32_t CFRunLoopRunInMode(CFStringRef mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled);
extern CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);

/* ---- dispatch ----------------------------------------------------------- */
@protocol OS_dispatch_queue <NSObject>
@end
typedef NSObject<OS_dispatch_queue> *dispatch_queue_t;
typedef NSObject *dispatch_queue_attr_t;
typedef uint64_t dispatch_time_t;
typedef long dispatch_once_t;
typedef void (^dispatch_block_t)(void);
#define DISPATCH_TIME_NOW (0ull)
#define NSEC_PER_SEC 1000000000ull
#define DISPATCH_QUEUE_SERIAL NULL
extern dispatch_queue_t dispatch_get_main_queue(void);
extern dispatch_queue_t dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);
extern void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);
extern void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
extern dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);
extern void dispatch_once(dispatch_once_t *predicate, dispatch_block_t block);

/* ---- Foundation (API Apple mancanti in GNUstep) ------------------------ */
extern NSString *const NSURLVolumeAvailableCapacityForImportantUsageKey;

@interface NSFileManager (AppleOnly)
@property (readonly, copy) NSURL *temporaryDirectory;
- (NSArray<NSURL *> *)URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domainMask;
@end

@interface NSURL (AppleOnly)
@property (readonly) const char *fileSystemRepresentation;
- (BOOL)startAccessingSecurityScopedResource;
- (void)stopAccessingSecurityScopedResource;
- (nullable NSDictionary<NSString *, id> *)resourceValuesForKeys:(NSArray<NSString *> *)keys error:(NSError **)error;
@end

@interface NSString (AppleOnly)
- (NSComparisonResult)localizedStandardCompare:(NSString *)string;
@end

@protocol NSFilePresenter;
@interface NSFileCoordinator (AppleOnly)
- (instancetype)initWithFilePresenter:(nullable id<NSFilePresenter>)filePresenterOrNil;
@end

/* ---- UIKit -------------------------------------------------------------- */
typedef struct { CGFloat top, left, bottom, right; } UIEdgeInsets;
static inline UIEdgeInsets UIEdgeInsetsMake(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { UIEdgeInsets e = { t, l, b, r }; return e; }

typedef NSString *UIApplicationOpenURLOptionsKey;
extern UIApplicationOpenURLOptionsKey const UIApplicationOpenURLOptionsOpenInPlaceKey;
extern NSString *const UITrackingRunLoopMode;

typedef NSString *UIFontTextStyle;
extern UIFontTextStyle const UIFontTextStyleHeadline;
extern UIFontTextStyle const UIFontTextStyleBody;
extern UIFontTextStyle const UIFontTextStyleFootnote;
typedef CGFloat UIFontWeight;
extern const UIFontWeight UIFontWeightRegular;

typedef NS_ENUM(NSInteger, NSTextAlignment) { NSTextAlignmentLeft = 0, NSTextAlignmentCenter = 1, NSTextAlignmentRight = 2 };
typedef NS_ENUM(NSInteger, UILayoutConstraintAxis) { UILayoutConstraintAxisHorizontal = 0, UILayoutConstraintAxisVertical = 1 };
typedef NS_OPTIONS(NSUInteger, UIViewAutoresizing) { UIViewAutoresizingNone = 0, UIViewAutoresizingFlexibleWidth = 1 << 1, UIViewAutoresizingFlexibleHeight = 1 << 4 };
typedef NS_OPTIONS(NSUInteger, UIControlEvents) { UIControlEventTouchUpInside = 1 << 6, UIControlEventValueChanged = 1 << 12 };
typedef NS_OPTIONS(NSUInteger, UIControlState) { UIControlStateNormal = 0 };
typedef NS_ENUM(NSInteger, UIButtonType) { UIButtonTypeCustom = 0, UIButtonTypeSystem = 1 };
typedef NS_ENUM(NSInteger, UIModalPresentationStyle) { UIModalPresentationFullScreen = 0, UIModalPresentationOverFullScreen = 5 };
typedef NS_ENUM(NSInteger, UIModalTransitionStyle) { UIModalTransitionStyleCoverVertical = 0, UIModalTransitionStyleCrossDissolve = 2 };
typedef NS_ENUM(NSInteger, UIProgressViewStyle) { UIProgressViewStyleDefault = 0 };
typedef NS_ENUM(NSInteger, UITableViewStyle) { UITableViewStylePlain, UITableViewStyleGrouped, UITableViewStyleInsetGrouped };
typedef NS_ENUM(NSInteger, UITableViewCellStyle) { UITableViewCellStyleDefault, UITableViewCellStyleValue1, UITableViewCellStyleValue2, UITableViewCellStyleSubtitle };
typedef NS_ENUM(NSInteger, UITableViewCellSelectionStyle) { UITableViewCellSelectionStyleNone, UITableViewCellSelectionStyleBlue, UITableViewCellSelectionStyleGray, UITableViewCellSelectionStyleDefault };
typedef NS_ENUM(NSInteger, UITableViewCellAccessoryType) { UITableViewCellAccessoryNone, UITableViewCellAccessoryDisclosureIndicator };
typedef NS_ENUM(NSInteger, UITableViewRowAnimation) { UITableViewRowAnimationFade, UITableViewRowAnimationRight, UITableViewRowAnimationLeft, UITableViewRowAnimationTop, UITableViewRowAnimationBottom, UITableViewRowAnimationNone };
typedef NS_ENUM(NSInteger, UIAlertControllerStyle) { UIAlertControllerStyleActionSheet = 0, UIAlertControllerStyleAlert };
typedef NS_ENUM(NSInteger, UIAlertActionStyle) { UIAlertActionStyleDefault = 0, UIAlertActionStyleCancel, UIAlertActionStyleDestructive };
typedef NS_ENUM(NSInteger, UIBarButtonSystemItem) { UIBarButtonSystemItemDone, UIBarButtonSystemItemCancel, UIBarButtonSystemItemEdit, UIBarButtonSystemItemSave, UIBarButtonSystemItemAdd, UIBarButtonSystemItemFlexibleSpace, UIBarButtonSystemItemFixedSpace, UIBarButtonSystemItemCompose, UIBarButtonSystemItemReply, UIBarButtonSystemItemAction };
typedef NS_ENUM(NSInteger, UIBarButtonItemStyle) { UIBarButtonItemStylePlain, UIBarButtonItemStyleDone };
typedef NS_ENUM(NSInteger, UIContextualActionStyle) { UIContextualActionStyleNormal, UIContextualActionStyleDestructive };

@class UIView, UIViewController, UIWindow, UIImage, UIColor, UIFont, UITableView, UINavigationController, UIBarButtonItem;

@interface UIColor : NSObject
+ (UIColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
@property (class, nonatomic, readonly) UIColor *systemBackgroundColor;
@property (class, nonatomic, readonly) UIColor *secondarySystemBackgroundColor;
@property (class, nonatomic, readonly) UIColor *secondaryLabelColor;
@property (class, nonatomic, readonly) UIColor *systemRedColor;
@end

@interface UIFont : NSObject
+ (UIFont *)preferredFontForTextStyle:(UIFontTextStyle)style;
+ (UIFont *)monospacedSystemFontOfSize:(CGFloat)fontSize weight:(UIFontWeight)weight;
@end

@interface UIImage : NSObject
+ (nullable UIImage *)imageWithContentsOfFile:(NSString *)path;
+ (nullable UIImage *)systemImageNamed:(NSString *)name;
- (void)drawInRect:(CGRect)rect;
@end

@interface UIBezierPath : NSObject
+ (instancetype)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)cornerRadius;
- (void)addClip;
@end

@interface UIGraphicsImageRendererContext : NSObject
@end
typedef void (^UIGraphicsImageDrawingActions)(UIGraphicsImageRendererContext *rendererContext);
@interface UIGraphicsImageRenderer : NSObject
- (instancetype)initWithSize:(CGSize)size;
- (UIImage *)imageWithActions:(UIGraphicsImageDrawingActions)actions;
@end

@interface CALayer : NSObject
@property CGFloat cornerRadius;
@end

@interface NSLayoutConstraint : NSObject
+ (void)activateConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
@end

@interface NSLayoutAnchor : NSObject
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)anchor;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)anchor constant:(CGFloat)c;
@end
@interface NSLayoutDimension : NSLayoutAnchor
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c;
@end

@interface UIResponder : NSObject
@end

@interface UIView : UIResponder
- (instancetype)initWithFrame:(CGRect)frame;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nullable, nonatomic, copy) UIColor *backgroundColor;
@property (null_resettable, nonatomic, strong) UIColor *tintColor;
@property (nonatomic, readonly, strong) CALayer *layer;
@property (nonatomic) BOOL translatesAutoresizingMaskIntoConstraints;
@property (nonatomic) UIViewAutoresizing autoresizingMask;
@property (nonatomic, getter=isHidden) BOOL hidden;
- (void)addSubview:(UIView *)view;
@property (nonatomic, readonly, strong) NSLayoutAnchor *leadingAnchor;
@property (nonatomic, readonly, strong) NSLayoutAnchor *trailingAnchor;
@property (nonatomic, readonly, strong) NSLayoutAnchor *topAnchor;
@property (nonatomic, readonly, strong) NSLayoutAnchor *bottomAnchor;
@property (nonatomic, readonly, strong) NSLayoutAnchor *centerXAnchor;
@property (nonatomic, readonly, strong) NSLayoutAnchor *centerYAnchor;
@property (nonatomic, readonly, strong) NSLayoutDimension *widthAnchor;
@end

@interface UIControl : UIView
@property (nonatomic, getter=isEnabled) BOOL enabled;
- (void)addTarget:(nullable id)target action:(SEL)action forControlEvents:(UIControlEvents)controlEvents;
@end

@interface UILabel : UIView
@property (nullable, nonatomic, copy) NSString *text;
@property (null_resettable, nonatomic, strong) UIFont *font;
@property (null_resettable, nonatomic, strong) UIColor *textColor;
@property (nonatomic) NSTextAlignment textAlignment;
@property (nonatomic) NSInteger numberOfLines;
@end

@interface UIButton : UIControl
+ (instancetype)buttonWithType:(UIButtonType)buttonType;
- (void)setTitle:(nullable NSString *)title forState:(UIControlState)state;
@end

@interface UIProgressView : UIView
- (instancetype)initWithProgressViewStyle:(UIProgressViewStyle)style;
- (void)setProgress:(float)progress animated:(BOOL)animated;
@end

@interface UIStackView : UIView
- (instancetype)initWithArrangedSubviews:(NSArray<__kindof UIView *> *)views;
@property (nonatomic) UILayoutConstraintAxis axis;
@property (nonatomic) CGFloat spacing;
@end

@interface UISegmentedControl : UIControl
- (instancetype)initWithItems:(nullable NSArray *)items;
@property (nonatomic) NSInteger selectedSegmentIndex;
- (void)sizeToFit;
@end

@interface UIScrollView : UIView
@property (nonatomic) BOOL alwaysBounceVertical;
@end

@interface UITextView : UIScrollView
@property (null_resettable, nonatomic, copy) NSString *text;
@property (nullable, nonatomic, strong) UIFont *font;
@property (nonatomic, getter=isEditable) BOOL editable;
@property (nonatomic) UIEdgeInsets textContainerInset;
- (void)scrollRangeToVisible:(NSRange)range;
@end

@interface UIImageView : UIView
@property (nullable, nonatomic, strong) UIImage *image;
@end

@interface UITableViewCell : UIView
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier;
@property (nonatomic, readonly, strong, nullable) UILabel *textLabel;
@property (nonatomic, readonly, strong, nullable) UILabel *detailTextLabel;
@property (nonatomic, readonly, strong, nullable) UIImageView *imageView;
@property (nonatomic) UITableViewCellSelectionStyle selectionStyle;
@property (nonatomic) UITableViewCellAccessoryType accessoryType;
@property (nonatomic, strong, nullable) UIView *accessoryView;
@end

@interface UIRefreshControl : UIControl
- (void)endRefreshing;
@end

@interface UITableView : UIScrollView
@property (nonatomic) CGFloat rowHeight;
- (void)reloadData;
- (void)reloadSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation;
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated;
- (nullable __kindof UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier;
- (nullable __kindof UITableViewCell *)cellForRowAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface NSIndexPath (UIKit)
@property (nonatomic, readonly) NSInteger section;
@property (nonatomic, readonly) NSInteger row;
@end

@class UIPopoverPresentationController;

@interface UINavigationItem : NSObject
@property (nonatomic, strong, nullable) UIBarButtonItem *rightBarButtonItem;
@property (nonatomic, strong, nullable) UIBarButtonItem *leftBarButtonItem;
@property (nonatomic, strong, nullable) UIView *titleView;
@end

@interface UIViewController : UIResponder
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil;
@property (null_resettable, nonatomic, strong) UIView *view;
@property (nullable, nonatomic, copy) NSString *title;
@property (nonatomic, readonly, strong) UINavigationItem *navigationItem;
@property (nullable, nonatomic, readonly, strong) UINavigationController *navigationController;
@property (nullable, nonatomic, readonly) UIViewController *presentedViewController;
@property (nonatomic) UIModalPresentationStyle modalPresentationStyle;
@property (nonatomic) UIModalTransitionStyle modalTransitionStyle;
@property (nullable, nonatomic, readonly) UIPopoverPresentationController *popoverPresentationController;
- (void)viewDidLoad;
- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)loadViewIfNeeded;
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^ _Nullable)(void))completion;
- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^ _Nullable)(void))completion;
@end

@interface UIPopoverPresentationController : NSObject
@property (nullable, nonatomic, strong) UIView *sourceView;
@property (nonatomic, assign) CGRect sourceRect;
@property (nullable, nonatomic, strong) UIBarButtonItem *barButtonItem;
@end

@interface UITableViewController : UIViewController
- (instancetype)initWithStyle:(UITableViewStyle)style;
@property (null_resettable, nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) UIRefreshControl *refreshControl;
@end

@interface UINavigationBar : UIView
@property (nonatomic, readwrite, assign) BOOL prefersLargeTitles;
@end

@interface UINavigationController : UIViewController
- (instancetype)initWithRootViewController:(UIViewController *)rootViewController;
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (nullable UIViewController *)popViewControllerAnimated:(BOOL)animated;
@property (nonatomic, readonly) UINavigationBar *navigationBar;
@end

@interface UIBarButtonItem : NSObject
- (instancetype)initWithBarButtonSystemItem:(UIBarButtonSystemItem)systemItem target:(nullable id)target action:(nullable SEL)action;
- (instancetype)initWithImage:(nullable UIImage *)image style:(UIBarButtonItemStyle)style target:(nullable id)target action:(nullable SEL)action;
@end

@interface UIAlertAction : NSObject
+ (instancetype)actionWithTitle:(nullable NSString *)title style:(UIAlertActionStyle)style handler:(void (^ _Nullable)(UIAlertAction *action))handler;
@end

@interface UIAlertController : UIViewController
+ (instancetype)alertControllerWithTitle:(nullable NSString *)title message:(nullable NSString *)message preferredStyle:(UIAlertControllerStyle)preferredStyle;
- (void)addAction:(UIAlertAction *)action;
@end

@interface UIActivityViewController : UIViewController
- (instancetype)initWithActivityItems:(NSArray *)activityItems applicationActivities:(nullable NSArray *)applicationActivities;
@end

@interface UTType : NSObject
@end
extern UTType *UTTypeZIP;
extern UTType *UTTypeFolder;
extern UTType *UTTypeItem;

@class UIDocumentPickerViewController;
@protocol UIDocumentPickerDelegate <NSObject>
@optional
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls;
@end

@interface UIDocumentPickerViewController : UIViewController
- (instancetype)initForOpeningContentTypes:(NSArray<UTType *> *)contentTypes asCopy:(BOOL)asCopy;
@property (nullable, nonatomic, weak) id<UIDocumentPickerDelegate> delegate;
@property (nonatomic, assign) BOOL allowsMultipleSelection;
@end

@class UIContextualAction;
typedef void (^UIContextualActionHandler)(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL actionPerformed));
@interface UIContextualAction : NSObject
+ (instancetype)contextualActionWithStyle:(UIContextualActionStyle)style title:(nullable NSString *)title handler:(UIContextualActionHandler)handler;
@end

@interface UISwipeActionsConfiguration : NSObject
+ (instancetype)configurationWithActions:(NSArray<UIContextualAction *> *)actions;
@end

@interface UIScreen : NSObject
@property (class, nonatomic, readonly) UIScreen *mainScreen;
@property (nonatomic, readonly) CGRect bounds;
@end

@interface UIWindow : UIView
@property (nullable, nonatomic, strong) UIViewController *rootViewController;
- (void)makeKeyAndVisible;
@end

@interface UIApplication : UIResponder
@property (class, nonatomic, readonly) UIApplication *sharedApplication;
@property (nonatomic, getter=isIdleTimerDisabled) BOOL idleTimerDisabled;
- (void)openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options completionHandler:(void (^ _Nullable)(BOOL success))completion;
@end
