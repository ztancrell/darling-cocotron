/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSDisplay.h>
#import <AppKit/NSErrors.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSColorList.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontTypeface.h>
#import <Onyx2D/O2Font_freetype.h>
#import <fontconfig/fontconfig.h>
#include <stdlib.h>

@implementation NSDisplay

+ (void) initialize {
    if (self == [NSDisplay class]) {
        NSDictionary *map = @{
            @"LeftControl" : @"Command",
            @"LeftAlt" : @"Alt",
            @"RightControl" : @"Control",
            @"RightAlt" : @"Alt"
        };
        NSDictionary *modifierMapping = @{@"NSModifierFlagMapping" : map};

        [[NSUserDefaults standardUserDefaults]
                registerDefaults: modifierMapping];
    }
}

+ (NSDisplay *) currentDisplay {
    return NSThreadSharedInstance(@"NSDisplay");
}

- (instancetype) init {
    if ([self class] != [NSDisplay class]) {
        // Initializing a concrete subclass.
        _eventQueue = [NSMutableArray new];
        return self;
    }

    // NSDisplay is a (singleton) class cluster; we load
    // the installed backends and initialize on of them.
    [self release];

    // Discover the installed backends.
    NSBundle *appKitBundle = [NSBundle bundleForClass: [NSDisplay class]];
    NSMutableArray *backends = [NSMutableArray new];
    for (NSString *path in
         [appKitBundle pathsForResourcesOfType: @"backend"
                                   inDirectory: @"Backends"]) {
        NSBundle *backendBundle = [NSBundle bundleWithPath: path];
        NSError *error = nil;
        if ([backendBundle loadAndReturnError: &error]) {
            [backends addObject: backendBundle];
        } else {
            NSLog(@"AppKit: Failed to load backend at %@: %@", path, error);
        }
    }

    // Sort them according to the NSPriority key in their Info.plist files.
    [backends sortUsingComparator: ^(NSBundle *b1, NSBundle *b2) {
      NSNumber *p1 = [b1 objectForInfoDictionaryKey: @"NSPriority"];
      NSNumber *p2 = [b2 objectForInfoDictionaryKey: @"NSPriority"];
      return [p2 compare: p1];
    }];

    // Try to instantiate them in that order.
    for (NSBundle *backendBundle in backends) {
        NSDisplay *display = [[[backendBundle principalClass] alloc] init];
        if (display != nil) {
            // The first one to initialize successfully becomes the
            // one that we're going to use.
            [backends release];
            return display;
        }
    }

    // None of the backends can be used.
    [NSException raise: NSWindowServerCommunicationException
                format: @"Failed to connect to a window server. Available "
                        @"backends are: %@",
                        backends];

    [backends release];
    return nil;
}

- (NSArray<NSScreen *> *) screens {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSDraggingManager *) draggingManager {
    NSInvalidAbstractInvocation();
    return nil;
}

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSColor *) colorWithName: (NSString *) colorName {
    NSInvalidAbstractInvocation();
    return nil;
}

- (void) _addSystemColor: (NSColor *) result forName: (NSString *) colorName {
    NSInvalidAbstractInvocation();
}

- (NSTimeInterval) textCaretBlinkInterval {
    NSInvalidAbstractInvocation();
    return 1;
}

- (void) hideCursor {
    NSInvalidAbstractInvocation();
}

- (void) unhideCursor {
    NSInvalidAbstractInvocation();
}

// Arrow, IBeam, HorizontalResize, VerticalResize
- (id) cursorWithName: (NSString *) name {
    NSInvalidAbstractInvocation();
    return nil;
}

- (void) setCursor: (id) cursor {
    NSInvalidAbstractInvocation();
}

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSString *) mode
                            dequeue: (BOOL) dequeue
{
    NSEvent *result = nil;

    if ([_eventQueue count])
        untilDate = [NSDate date];

    [[NSRunLoop currentRunLoop] runMode: mode beforeDate: untilDate];

    // Scan for the first event of a wanted type. Events that do not match stay
    // queued: AppKit's contract is that nextEventMatchingMask: returns only
    // what was asked for and leaves the rest for the main loop, but removing
    // them here destroyed every other pending event whenever a caller asked
    // for a narrow mask - a tracking loop asking for NSLeftMouseUpMask would
    // silently discard queued key events.
    while (result == nil && [_eventQueue count] > 0) {
        NSUInteger i, count = [_eventQueue count];

        for (i = 0; i < count; i++) {
            NSEvent *event = _eventQueue[i];

            if (NSEventMaskFromType([event type]) & mask) {
                result = [[event retain] autorelease];

                if (dequeue)
                    [_eventQueue removeObjectAtIndex: i];
                break;
            }
        }
    }

    if (result == nil) {
        result = [[[NSEvent alloc] initWithType: NSAppKitSystem
                                       location: NSZeroPoint
                                  modifierFlags: 0
                                         window: nil] autorelease];
    }

    return result;
}

- (void) discardEventsMatchingMask: (NSEventMask) mask
                       beforeEvent: (NSEvent *) event
{
    NSInteger count = [_eventQueue count];

    while (--count >= 0) {
        if (_eventQueue[count] == event) {
            break;
        }
    }

    // The mask selects which events to drop, so it has to be tested against
    // each candidate. Testing it against the stop marker makes the test
    // constant for the whole scan, so a coalescing call drops every earlier
    // event whatever its type - and the periodic-event coalescer wipes queued
    // key and mouse events on every tick.
    while (--count >= 0) {
        if (NSEventMaskFromType([_eventQueue[count] type]) & mask) {
            [_eventQueue removeObjectAtIndex: count];
        }
    }
}

- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart {
    if (atStart) {
        [_eventQueue insertObject: event atIndex: 0];
    } else {
        [_eventQueue addObject: event];
    }
}

- (BOOL) containsAndRemovePeriodicEvents {
    BOOL result = NO;
    NSUInteger count = [_eventQueue count];

    while (--count >= 0) {
        NSEvent *event = _eventQueue[count];
        if ([event type] == NSPeriodic) {
            result = YES;
            [_eventQueue removeObjectAtIndex: count];
        }
    }

    return result;
}

- (NSEventModifierFlags) modifierForDefault: (NSString *) key
                                   standard: (NSEventModifierFlags) standard
{
    NSDictionary *modmap = [[NSUserDefaults standardUserDefaults]
            dictionaryForKey: @"NSModifierFlagMapping"];
    NSString *remap = modmap[key];

    if ([remap isEqualToString: @"Command"])
        return NSCommandKeyMask;
    if ([remap isEqualToString: @"Alt"])
        return NSAlternateKeyMask;
    if ([remap isEqualToString: @"Control"])
        return NSControlKeyMask;

    return standard;
}

- (void) beep {
    NSInvalidAbstractInvocation();
}

// Font listing comes from fontconfig and needs no window server, so these are class methods: a
// process that may not connect to one (a sandboxed helper) can still ask which fonts exist.
+ (NSSet *) allFontFamilyNames {
    FcPattern *pat = FcPatternCreate();
    // Avoid the variadic FcObjectSetBuild(): fontconfig is a native (Linux) library, and on
    // arm64 Darwin and Linux pass variadic arguments differently (stack vs. registers).
    FcObjectSet *props = FcObjectSetCreate();
    FcObjectSetAdd(props, FC_FAMILY);

    FcFontSet *set = FcFontList(O2FontSharedFontConfig(), pat, props);
    NSMutableSet *ret = [NSMutableSet set];

    for (int i = 0; i < set->nfont; i++) {
        FcChar8 *family;
        if (FcPatternGetString(set->fonts[i], FC_FAMILY, 0, &family) ==
            FcResultMatch && family != NULL) {
            NSString *familyStr = [NSString stringWithCString: (const char *) family
                                                     encoding: NSUTF8StringEncoding];
            if (familyStr == nil)
                familyStr = [NSString stringWithCString: (const char *) family
                                               encoding: NSISOLatin1StringEncoding];
            if (familyStr != nil)
                [ret addObject: familyStr];
        }
    }

    FcPatternDestroy(pat);
    FcObjectSetDestroy(props);
    FcFontSetDestroy(set);
    return ret;
}

static NSString *matchedFamily(FcConfig *config, NSString *family) {
    FcPattern *pat = FcPatternCreate();
    if (family != nil) {
        FcPatternAddString(pat, FC_FAMILY,
                           (const FcChar8 *) [family UTF8String]);
    }
    FcConfigSubstitute(config, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);

    FcResult result;
    FcPattern *match = FcFontMatch(config, pat, &result);
    FcPatternDestroy(pat);
    if (match == NULL)
        return nil;

    FcChar8 *matched = NULL;
    NSString *res = nil;
    if (FcPatternGetString(match, FC_FAMILY, 0, &matched) == FcResultMatch)
        res = [NSString stringWithUTF8String: (const char *) matched];
    FcPatternDestroy(match);
    return res;
}

+ (NSString *) substituteFamilyName: (NSString *) familyName {
    return matchedFamily(O2FontSharedFontConfig(), familyName);
}

// A generic family with no installed member matches the same default font as
// a pattern without any family.
+ (NSString *) fontFamilyNameForGenericFamily: (NSString *) generic {
    FcConfig *config = O2FontSharedFontConfig();
    NSString *family = matchedFamily(config, generic);
    if (family == nil || [family isEqualToString: matchedFamily(config, nil)])
        return nil;
    return family;
}

// NSUnboldFontMask and NSUnitalicFontMask are conversion requests, not face
// traits.
static NSFontTraitMask fontTraitsOfPattern(FcPattern *p) {
    int slant = FC_SLANT_ROMAN, width = FC_WIDTH_NORMAL,
        weight = FC_WEIGHT_REGULAR;
    FcPatternGetInteger(p, FC_SLANT, 0, &slant);
    FcPatternGetInteger(p, FC_WIDTH, 0, &width);
    FcPatternGetInteger(p, FC_WEIGHT, 0, &weight);

    NSFontTraitMask traits = 0;
    if (slant == FC_SLANT_OBLIQUE || slant == FC_SLANT_ITALIC)
        traits |= NSItalicFontMask;
    if (weight >= FC_WEIGHT_SEMIBOLD)
        traits |= NSBoldFontMask;
    if (width <= FC_WIDTH_SEMICONDENSED)
        traits |= NSNarrowFontMask;
    else if (width >= FC_WIDTH_SEMIEXPANDED)
        traits |= NSExpandedFontMask;
    return traits;
}

// -[NSFontFamily typefaceWithTraits:] takes the first face with a trait mask,
// so list the faces nearest to regular (or bold) weight and normal width first,
// then regular, italic, bold, bold italic.
static int fontPatternDistance(FcPattern *p) {
    int slant = FC_SLANT_ROMAN, width = FC_WIDTH_NORMAL,
        weight = FC_WEIGHT_REGULAR;
    FcPatternGetInteger(p, FC_SLANT, 0, &slant);
    FcPatternGetInteger(p, FC_WIDTH, 0, &width);
    FcPatternGetInteger(p, FC_WEIGHT, 0, &weight);
    BOOL bold = weight >= FC_WEIGHT_SEMIBOLD;
    int target = bold ? FC_WEIGHT_BOLD : FC_WEIGHT_REGULAR;
    return (abs(weight - target) * 1000 + abs(width - FC_WIDTH_NORMAL)) * 4 +
           bold * 2 + (slant != FC_SLANT_ROMAN);
}

static int compareFontPatterns(const void *a, const void *b) {
    return fontPatternDistance(*(FcPattern *const *) a) -
           fontPatternDistance(*(FcPattern *const *) b);
}

+ (NSArray<NSFontTypeface *> *) fontTypefacesForFamilyName:
        (NSString *) familyName
{
    familyName = [self substituteFamilyName: familyName];
    if (familyName == nil) {
        return @[];
    }
    FcPattern *pat = FcPatternCreate();
    FcPatternAddString(pat, FC_FAMILY,
                       (unsigned char *) [familyName UTF8String]);
    // Not FcObjectSetBuild(): see -allFontFamilyNames.
    FcObjectSet *props = FcObjectSetCreate();
    FcObjectSetAdd(props, FC_FAMILY);
    FcObjectSetAdd(props, FC_STYLE);
    FcObjectSetAdd(props, FC_SLANT);
    FcObjectSetAdd(props, FC_WIDTH);
    FcObjectSetAdd(props, FC_WEIGHT);

    FcFontSet *set = FcFontList(O2FontSharedFontConfig(), pat, props);
    NSMutableArray *ret = [NSMutableArray array];
    qsort(set->fonts, set->nfont, sizeof(FcPattern *), compareFontPatterns);

    for (int i = 0; i < set->nfont; i++) {
        FcChar8 *typeface;
        FcPattern *p = set->fonts[i];
        if (FcPatternGetString(p, FC_STYLE, 0, &typeface) == FcResultMatch && typeface != NULL) {
            NSString *traitName =
                    [NSString stringWithCString: (const char *) typeface
                                       encoding: NSUTF8StringEncoding];
            if (traitName == nil)
                traitName = [NSString stringWithCString: (const char *) typeface
                                               encoding: NSISOLatin1StringEncoding];
            if (traitName == nil)
                traitName = @"Regular";

            FcChar8 *pattern = FcNameUnparse(p);
            NSString *name = nil;
            if (pattern != NULL) {
                name = [NSString stringWithCString: (const char *) pattern
                                          encoding: NSUTF8StringEncoding];
                if (name == nil)
                    name = [NSString stringWithCString: (const char *) pattern
                                              encoding: NSISOLatin1StringEncoding];
                FcStrFree(pattern);
            }
            if (name == nil)
                name = traitName;

            NSFontTypeface *face = [[NSFontTypeface alloc]
                    initWithName: name
                       traitName: traitName
                          traits: fontTraitsOfPattern(p)];
            if (face != nil) {
                [ret addObject: face];
                [face release];
            }
        }
    }

    FcPatternDestroy(pat);
    FcObjectSetDestroy(props);
    FcFontSetDestroy(set);
    return ret;
}

- (CGFloat) scrollerWidth {
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) runModalPageLayoutWithPrintInfo: (NSPrintInfo *) printInfo {
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) runModalPrintPanelWithPrintInfoDictionary:
        (NSMutableDictionary *) attributes
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (CGContextRef) graphicsPortForPrintOperationWithView: (NSView *) view
                                             printInfo:
                                                     (NSPrintInfo *) printInfo
                                             pageRange: (NSRange) pageRange
{
    NSInvalidAbstractInvocation();
    return nil;
}

- (BOOL) implementsCustomPanelForClass: (Class) panelClass {
    return NO;
}

- (int) savePanel: (NSSavePanel *) savePanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) openPanel: (NSOpenPanel *) openPanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
                       types: (NSArray *) types
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (NSPoint) mouseLocation {
    NSInvalidAbstractInvocation();
    return NSMakePoint(0, 0);
}

- (NSUInteger) currentModifierFlags {
    NSInvalidAbstractInvocation();
    return 0;
}

- (NSArray *) orderedWindowNumbers {
    NSInvalidAbstractInvocation();
    return nil;
}

- (CGRect) insetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    NSInvalidAbstractInvocation();
    return frame;
}

- (CGRect) outsetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    NSInvalidAbstractInvocation();
    return frame;
}

@end

void NSColorSetCatalogColor(NSString *catalogName, NSString *colorName,
                            NSColor *color)
{
    NSColorList *colors = [NSColorList colorListNamed: catalogName];

    [colors setColor: color forKey: colorName];
}

NSColor *NSColorGetCatalogColor(NSString *catalogName, NSString *colorName) {
    NSColorList *colors = [NSColorList colorListNamed: catalogName];

    if (colors != nil)
        return [colors colorWithKey: colorName];

    return nil;
}
