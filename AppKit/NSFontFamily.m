/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSFontFamily.h>
#import <AppKit/NSFontTypeface.h>
#import <AppKit/NSGraphicsContext.h>

@interface NSFontFamily ()
+ (NSMutableArray *) fontFamilies;
+ (void) buildFontFamilies;
@end

@implementation NSFontFamily

static NSMutableArray *sharedList = nil;
static NSMutableDictionary *sharedByName = nil;

+ (NSMutableArray *) fontFamilies {
    @synchronized([NSFontFamily class]) {
        if (sharedList == nil) {
            sharedList = [NSMutableArray new];
            sharedByName = [NSMutableDictionary new];
            [self buildFontFamilies];
        }

        return sharedList;
    }
}

+ (NSArray *) allFontFamilyNames {
    NSMutableArray *result = [NSMutableArray new];
    NSArray *families = [self fontFamilies];
    int i, count = [families count];

    for (i = 0; i < count; i++)
        [result addObject: [[families objectAtIndex: i] name]];

    [result sortUsingSelector: @selector(compare:)];

    return result;
}

+ (void) addFontFamily: (NSFontFamily *) family {
    if (family == nil)
        return;
    @synchronized([NSFontFamily class]) {
        [[self fontFamilies] addObject: family];
        NSString *name = [family name];
        if (name != nil)
            [sharedByName setObject: family forKey: name];
    }
}

+ (NSFontFamily *) addFontFamilyWithName: (NSString *) familyName {
    if (familyName == nil)
        return nil;
    NSFontFamily *family = [[self alloc] initWithName: familyName];
    [self addFontFamily: family];
    return [family autorelease];
}

+ (void) buildFontFamilies {
    NSSet *initialFamilyNames = [NSDisplay allFontFamilyNames];
    for (NSString *familyName in initialFamilyNames) {
        [self addFontFamilyWithName: familyName];
    }
}

+ (NSFontFamily *) fontFamilyWithName: (NSString *) name {
    if (name == nil)
        return nil;
    @synchronized([NSFontFamily class]) {
        [self fontFamilies]; // Ensure buildFontFamilies has run
        NSFontFamily *family = [sharedByName objectForKey: name];
        if (family != nil)
            return family;

        // Pretend to have this family.
        return [self addFontFamilyWithName: name];
    }
}

+ (NSFontFamily *) fontFamilyWithTypefaceName: (NSString *) name {
    if (name == nil)
        return nil;

    @synchronized([NSFontFamily class]) {
        [self fontFamilies];

        // Fast path: check if name itself matches a family name
        NSFontFamily *family = [sharedByName objectForKey: name];
        if (family != nil)
            return family;

        // Fast path: hyphen separator e.g. "Helvetica-Bold" -> "Helvetica"
        NSRange hyphen = [name rangeOfString: @"-" options: NSBackwardsSearch];
        if (hyphen.location != NSNotFound) {
            NSString *baseFamily = [name substringToIndex: hyphen.location];
            family = [sharedByName objectForKey: baseFamily];
            if (family != nil)
                return family;
        }

        // Fast path: space separator e.g. "Liberation Sans Bold" -> "Liberation Sans"
        NSRange space = [name rangeOfString: @" " options: NSBackwardsSearch];
        if (space.location != NSNotFound) {
            NSString *baseFamily = [name substringToIndex: space.location];
            family = [sharedByName objectForKey: baseFamily];
            if (family != nil)
                return family;
        }

        // Check only already-loaded families to avoid scanning all unloaded families
        for (NSFontFamily *check in sharedList) {
            if (check->_typefacesLoaded) {
                NSFontTypeface *typeface = [check typefaceWithName: name];
                if (typeface != nil)
                    return check;
            }
        }

        return nil;
    }
}

+ (NSFontTypeface *) fontTypefaceWithName: (NSString *) name {
    NSFontFamily *family = [self fontFamilyWithTypefaceName: name];
    return [family typefaceWithName: name];
}

- initWithName: (NSString *) name {
    _name = [name copy];
    _typefaces = [NSMutableArray new];
    _typefacesLoaded = NO;
    return self;
}

- (void) dealloc {
    [_name release];
    [_typefaces release];
    [super dealloc];
}

- (NSString *) name {
    return _name;
}

- (void) _ensureTypefacesLoaded {
    if (!_typefacesLoaded) {
        @synchronized(self) {
            if (!_typefacesLoaded) {
                NSArray *typefaces =
                        [NSDisplay fontTypefacesForFamilyName: _name];
                if (typefaces != nil)
                    [_typefaces addObjectsFromArray: typefaces];
                _typefacesLoaded = YES;
            }
        }
    }
}

- (NSFontTypeface *) typefaceWithName: (NSString *) name {
    [self _ensureTypefacesLoaded];
    int i, count = [_typefaces count];

    for (i = 0; i < count; i++) {
        NSFontTypeface *typeface = [_typefaces objectAtIndex: i];

        if ([[typeface name] isEqualToString: name])
            return typeface;
    }

    return nil;
}

- (NSFontTypeface *) typefaceWithTraits: (NSFontTraitMask) traits {
    [self _ensureTypefacesLoaded];
    int i, count = [_typefaces count];

    for (i = 0; i < count; i++) {
        NSFontTypeface *typeface = [_typefaces objectAtIndex: i];

        if ([typeface traits] == traits)
            return typeface;
    }

    return nil;
}

- (void) addTypeface: (NSFontTypeface *) typeface {
    if (typeface != nil) {
        _typefacesLoaded = YES;
        [_typefaces addObject: typeface];
    }
}

- (void) addTypefaces: (NSArray *) typefaces {
    if (typefaces != nil) {
        _typefacesLoaded = YES;
        [_typefaces addObjectsFromArray: typefaces];
    }
}

- (NSArray *) typefaces {
    [self _ensureTypefacesLoaded];
    return _typefaces;
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@ 0x%x %@ %@>", [self class], self,
                                       _name, _typefaces];
}
@end
