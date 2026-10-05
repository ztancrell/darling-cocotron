#import <CoreText/CTFontManager.h>
#import <CoreText/CTFontDescriptor.h>
#import <CoreGraphics/CGFont.h>
#import <CoreGraphics/CGDataProvider.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSData.h>
#import <Foundation/NSURL.h>

const CFStringRef kCTFontManagerRegisteredFontsChangedNotification = CFSTR("CTFontManagerFontChangedNotification");

// ponytail: reports success without registering anything, so the font is not findable by name and
// lookups for it get whatever fontconfig matches instead. Returning false here needs a real
// CFError in *error (callers read it uninitialized otherwise). Real fix: keep registered CGFonts
// where O2Font's name lookup can find them.
static bool pretendGraphicsFontRegistration(NSString *action, CGFontRef font, CFErrorRef *error)
{
    CFStringRef name = font ? CGFontCopyPostScriptName(font) : NULL;
    NSLog(@"CTFontManager: %@ is not implemented. Reporting success without doing it for font \"%@\" (%p); "
          @"lookups by that name will get a fontconfig fallback.",
          action, name ? (NSString *)name : @"(no name)", font);
    if (name) CFRelease(name);
    if (error) *error = NULL;
    return true;
}

bool CTFontManagerRegisterGraphicsFont(CGFontRef font, CFErrorRef* error)
{
    return pretendGraphicsFontRegistration(@"CTFontManagerRegisterGraphicsFont", font, error);
}

bool CTFontManagerUnregisterGraphicsFont(CGFontRef font, CFErrorRef *error)
{
    return pretendGraphicsFontRegistration(@"CTFontManagerUnregisterGraphicsFont", font, error);
}

CFArrayRef CTFontManagerCopyAvailableFontFamilyNames(void)
{
    NSArray *families = [NSArray arrayWithObjects:
        @"Helvetica",
        @"Times",
        @"Courier",
        @"Arial",
        @"Menlo",
        @"Monaco",
        @"Geneva",
        @"Symbol",
        @"Apple Color Emoji",
        nil];
    return (CFArrayRef)[families copy];
}

// A descriptor made from font data carries the font itself under this private key, because a font
// that exists only in memory cannot be found again by name (name lookup asks fontconfig, which
// knows files on disk). CTFontCreateWithFontDescriptor uses the carried font when it is there.
const CFStringRef kDarlingCTFontGraphicsFontAttribute = CFSTR("DarlingCTFontGraphicsFont");

// ponytail: one descriptor per data blob; a font collection (.ttc) yields only its first face.
CTFontDescriptorRef CTFontManagerCreateFontDescriptorFromData(CFDataRef data)
{
    if (!data) return NULL;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    if (!provider) return NULL;
    CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    if (!cgFont) return NULL;   // not a font FreeType can read
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithObject:(id)cgFont
                                                                       forKey:(id)kDarlingCTFontGraphicsFontAttribute];
    CFStringRef name = CGFontCopyPostScriptName(cgFont);
    if (name) {
        attributes[(id)kCTFontNameAttribute] = (id)name;
        CFRelease(name);
    }
    CGFontRelease(cgFont);
    return CTFontDescriptorCreateWithAttributes((CFDictionaryRef)attributes);
}

CFArrayRef CTFontManagerCreateFontDescriptorsFromData(CFDataRef data)
{
    CTFontDescriptorRef desc = CTFontManagerCreateFontDescriptorFromData(data);
    if (!desc) return (CFArrayRef)[[NSArray array] retain];
    NSArray *result = [[NSArray alloc] initWithObjects:(id)desc, nil];
    CFRelease(desc);
    return (CFArrayRef)result;
}

// Synchronously loads font data from fontURL (local file or network URL).
// Network URLs may block if invoked from the main thread.
CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef fontURL)
{
    if (!fontURL) return (CFArrayRef)[[NSArray array] retain];
    NSData *data = [NSData dataWithContentsOfURL:(NSURL *)fontURL];
    if (!data) return (CFArrayRef)[[NSArray array] retain];
    return CTFontManagerCreateFontDescriptorsFromData((CFDataRef)data);
}

bool CTFontManagerRegisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope, CFErrorRef * error)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return false;
}

/* ---- Darling: local discovery placeholders, NOT implementations ----
 * Each logs its own name when called and returns zero, so one run shows which of these an
 * application actually reaches. Replace each with a real implementation, or remove it. */
#include <stdio.h>
#ifndef DARLING_UNIMPLEMENTED
#define DARLING_UNIMPLEMENTED(sym) \
	__attribute__((visibility("default"))) long darling_unimplemented_##sym(void) __asm__("_" #sym); \
	long darling_unimplemented_##sym(void) { fprintf(stderr, "DARLING unimplemented function called: " #sym "\n"); return 0; }
#endif
DARLING_UNIMPLEMENTED(CTFontDescriptorCopyLocalizedAttribute)
DARLING_UNIMPLEMENTED(CTFontDescriptorIsSystemUIFont)
