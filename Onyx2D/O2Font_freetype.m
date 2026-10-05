#import <Onyx2D/O2Font_freetype.h>
#ifdef FREETYPE_PRESENT
#import <Onyx2D/O2Encoding.h>
#import <string.h>
#include FT_TRUETYPE_TABLES_H

@implementation O2Font_freetype

#ifdef DARLING

O2FontRef O2FontCreateWithFontName_platform(NSString *name) {
    return [[O2Font_freetype alloc] initWithFontName: name];
}

O2FontRef O2FontCreateWithDataProvider_platform(O2DataProviderRef provider) {
    return [[O2Font_freetype alloc] initWithDataProvider: provider];
}

#endif

FT_Library O2FontSharedFreeTypeLibrary() {
    static FT_Library library = NULL;

    if (library == NULL) {
        if (FT_Init_FreeType(&library) != 0) {
            NSLog(@"FT_Init_FreeType failed");
        }
    }

    return library;
}

static void addAppFont(FcConfig *config, NSString *path) {
    path = [[NSBundle mainBundle] pathForResource: path ofType: nil];
    if (path == nil) {
        NSLog(@"Cannot find font %@ in resources", path);
        return;
    }
    BOOL isDirectory;
    [[NSFileManager defaultManager] fileExistsAtPath: path
                                         isDirectory: &isDirectory];
    if (isDirectory) {
        FcConfigAppFontAddDir(config, (const FcChar8 *) [path UTF8String]);
    } else {
        FcConfigAppFontAddFile(config, (const FcChar8 *) [path UTF8String]);
    }
}

FcConfig *O2FontSharedFontConfig() {
    static FcConfig *fontConfig = NULL;

    if (fontConfig == NULL) {
        fontConfig = FcInitLoadConfigAndFonts();

        id appFontsPath = [[NSBundle mainBundle]
                objectForInfoDictionaryKey: @"ATSApplicationFontsPath"];
        if ([appFontsPath isKindOfClass: [NSString class]]) {
            addAppFont(fontConfig, appFontsPath);
        } else if ([appFontsPath isKindOfClass: [NSArray class]]) {
            for (NSString *path in appFontsPath) {
                addAppFont(fontConfig, path);
            }
        }
    }

    return fontConfig;
}

O2FontRef O2FontCreateWithCodePointCoverage(const uint32_t *codePoints,
                                           size_t count, FT_Face baseFace,
                                           const char *language) {
    if (codePoints == NULL || count == 0)
        return nil;

    FcPattern *pattern = FcPatternCreate();
    FcCharSet *characters = FcCharSetCreate();
    if (pattern == NULL || characters == NULL) {
        if (pattern != NULL)
            FcPatternDestroy(pattern);
        if (characters != NULL)
            FcCharSetDestroy(characters);
        return nil;
    }
    for (size_t index = 0; index < count; ++index) {
        if (codePoints[index] > 0x10FFFF ||
            (codePoints[index] >= 0xD800 && codePoints[index] <= 0xDFFF) ||
            !FcCharSetAddChar(characters, codePoints[index])) {
            FcCharSetDestroy(characters);
            FcPatternDestroy(pattern);
            return nil;
        }
    }
    FcBool added = FcPatternAddCharSet(pattern, FC_CHARSET, characters);
    FcCharSetDestroy(characters);
    if (!added) {
        FcPatternDestroy(pattern);
        return nil;
    }

    // Coverage is mandatory below; these properties rank suitable substitutes.
    // Do not add the base file/index: that would pin selection to the old face.
    if (baseFace != NULL) {
        if (baseFace->family_name != NULL)
            added = FcPatternAddString(pattern, FC_FAMILY,
                    (const FcChar8 *)baseFace->family_name);
        added = added && FcPatternAddInteger(pattern, FC_WEIGHT,
                baseFace->style_flags & FT_STYLE_FLAG_BOLD
                        ? FC_WEIGHT_BOLD : FC_WEIGHT_REGULAR);
        added = added && FcPatternAddInteger(pattern, FC_SLANT,
                baseFace->style_flags & FT_STYLE_FLAG_ITALIC
                        ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
        if (FT_IS_FIXED_WIDTH(baseFace))
            added = added && FcPatternAddInteger(pattern, FC_SPACING, FC_MONO);
    }
    if (language != NULL && language[0] != '\0')
        added = added && FcPatternAddString(pattern, FC_LANG,
                                            (const FcChar8 *)language);
    if (!added) {
        FcPatternDestroy(pattern);
        return nil;
    }

    FcConfig *config = O2FontSharedFontConfig();
    if (config == NULL || !FcConfigSubstitute(config, pattern, FcMatchPattern)) {
        FcPatternDestroy(pattern);
        return nil;
    }
    FcDefaultSubstitute(pattern);
    FcResult result;
    FcPattern *match = FcFontMatch(config, pattern, &result);
    FcPatternDestroy(pattern);
    if (match == NULL)
        return nil;

    FcChar8 *filename = NULL;
    int faceIndex = 0;
    FcResult indexResult = FcPatternGetInteger(match, FC_INDEX, 0, &faceIndex);
    if (FcPatternGetString(match, FC_FILE, 0, &filename) != FcResultMatch ||
        (indexResult != FcResultMatch && indexResult != FcResultNoMatch) ||
        faceIndex < 0) {
        FcPatternDestroy(match);
        return nil;
    }
    FT_Face face = NULL;
    FT_Error error = FT_New_Face(O2FontSharedFreeTypeLibrary(),
                                 (const char *)filename, faceIndex, &face);
    FcPatternDestroy(match);
    if (error != 0)
        return nil;
    if (FT_Select_Charmap(face, FT_ENCODING_UNICODE) != 0) {
        FT_Done_Face(face);
        return nil;
    }
    for (size_t index = 0; index < count; ++index) {
        if (FT_Get_Char_Index(face, codePoints[index]) == 0) {
            FT_Done_Face(face);
            return nil;
        }
    }
    return [[O2Font_freetype alloc] initWithFace: face];
}

+ (NSString *) filenameForPattern: (NSString *) pattern {
    FcConfig *config = O2FontSharedFontConfig();

    FcPattern *pat = FcNameParse((unsigned char *) [pattern UTF8String]);
    FcConfigSubstitute(config, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);

    FcResult fcResult;
    FcPattern *match = FcFontMatch(config, pat, &fcResult);
    FcPatternDestroy(pat);
    if (match == NULL) {
        return nil;
    }

    FcChar8 *filename = NULL;
    FcPatternGetString(match, FC_FILE, 0, &filename);

    NSString *res = nil;
    if (filename != NULL) {
        res = [NSString stringWithUTF8String: (char *) filename];
    }

    FcPatternDestroy(match);
    return res;
}

- (instancetype) initWithDataProvider: (O2DataProviderRef) provider {
    self = [super initWithDataProvider: provider];
    if (self == nil) {
        return nil;
    }

    const void *bytes = [provider bytes];
    size_t length = [provider length];

    FT_Face face;
    int error = FT_New_Memory_Face(O2FontSharedFreeTypeLibrary(), bytes, length,
                                   0, &face);

    if (error != 0) {
        NSLog(@"FT_New_Memory_Face() = %d", error);
        [self release];
        return nil;
    }

    return [self initWithFace: face];
}

- (instancetype) initWithFontName: (NSString *) name {
    self = [super initWithFontName: name];

    NSString *filename = [[self class] filenameForPattern: name];
    if (filename == nil) {
        filename = [[self class] filenameForPattern: @""];
    }
    if (filename == nil) {
        NSLog(@"No font found for name %@", name);
        [self release];
        return nil;
    }

    // fontconfig reports the host's font path (e.g. /usr/share/fonts/...), which does not
    // exist under the guest's own root, so -fileExistsAtPath: needs it prefixed with
    // /Volumes/SystemRoot. FreeType is reached through the native passthrough, which already
    // resolves those host paths itself: handing it the prefixed path instead makes every
    // FT_New_Face fail with error 1 (FT_Err_Cannot_Open_Resource). So use the prefixed
    // form only to decide *whether* the file is there, and always hand FreeType the raw
    // fontconfig path.
    NSString *freetypePath = filename;
    if (![[NSFileManager defaultManager] fileExistsAtPath: filename]) {
        NSString *rooted = [@"/Volumes/SystemRoot" stringByAppendingPathComponent: filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath: rooted]) {
            NSLog(@"Font file not found: %@", filename);
            [self release];
            return nil;
        }
    }

    FT_Face face;
    FT_Error error = FT_New_Face(O2FontSharedFreeTypeLibrary(),
                                 [freetypePath fileSystemRepresentation], 0, &face);

    if (error != 0) {
        NSLog(@"FT_New_Face() = %d", error);
        [self release];
        return nil;
    }

    return [self initWithFace: face];
}

- (instancetype) initWithFace: (FT_Face) face {
    _face = face;
    _platformType = O2FontPlatformTypeFreeType;
    _glyphCache = [NSMutableDictionary new];

    int i, numberOfCharMaps = face->num_charmaps;
    BOOL hasUnicode = FALSE;
    BOOL hasMacRoman = FALSE;

    for (i = 0; i < numberOfCharMaps; i++) {

        if (face->charmaps[i]->encoding == FT_ENCODING_UNICODE) {
            hasUnicode = TRUE;
        }
        if (face->charmaps[i]->encoding == FT_ENCODING_APPLE_ROMAN) {
            hasMacRoman = TRUE;
        }
    }
    if (hasUnicode) {
        _ftEncoding = FT_ENCODING_UNICODE;
    } else if (hasMacRoman) {
        _ftEncoding = FT_ENCODING_APPLE_ROMAN;
    } else {
        NSLog(@"encoding = %c %c %c %c", face->charmaps[0]->encoding >> 24,
              face->charmaps[0]->encoding >> 16,
              face->charmaps[0]->encoding >> 8, face->charmaps[0]->encoding);
        _ftEncoding = face->charmaps[0]->encoding;
    }

    if (FT_Select_Charmap(face, _ftEncoding) != 0) {
        NSLog(@"FT_Select_Charmap(%d) failed", _ftEncoding);
    }

    if (!(face->face_flags & FT_FACE_FLAG_SCALABLE)) {
        NSLog(@"FreeType font face is not scalable for family: %s", face->family_name ? face->family_name : "unknown");
    }

    _unitsPerEm = (O2Float) face->units_per_EM;
    _ascent = face->ascender;
    _descent = face->descender;
    _leading = 0;
    _capHeight = face->height;
    _xHeight = face->height;
    _italicAngle = 0;
    _stemV = 0;
    _bbox.origin.x = face->bbox.xMin;
    _bbox.origin.y = face->bbox.yMin;
    _bbox.size.width = face->bbox.xMax - face->bbox.xMin;
    _bbox.size.height = face->bbox.yMax - face->bbox.yMin;
    _numberOfGlyphs = face->num_glyphs;
    _advances = NULL;
    return self;
}

- (void) dealloc {
    FT_Done_Face(_face);
    [_glyphCache release];
    [_macRomanEncoding release];
    [_macExpertEncoding release];
    [_winAnsiEncoding release];
    [super dealloc];
}

- (FT_Face) face {
    return _face;
}

- (CFArrayRef) copyTableTags {
    if (_face == NULL)
        return NULL;
    @synchronized(self) {
        FT_ULong count = 0, tag, length;
        // With a NULL tag pointer FreeType reports the number of tables in the length argument.
        if (FT_Sfnt_Table_Info(_face, 0, NULL, &count) != 0)
            return NULL;
        CFMutableArrayRef tags = CFArrayCreateMutable(kCFAllocatorDefault, count, NULL);
        for (FT_ULong i = 0; i < count; i++) {
            if (FT_Sfnt_Table_Info(_face, i, &tag, &length) == 0)
                CFArrayAppendValue(tags, (const void *) (uintptr_t) tag);
        }
        return tags;
    }
}

// nil when the font has no such table (or is not an SFNT font at all), as on macOS.
- (NSData *) copyTableForTag: (uint32_t) tag {
    if (_face == NULL)
        return nil;
    @synchronized(self) {
        FT_ULong length = 0;
        if (FT_Load_Sfnt_Table(_face, tag, 0, NULL, &length) != 0 || length == 0)
            return nil;
        NSMutableData *table = [[NSMutableData alloc] initWithLength: length];
        if (FT_Load_Sfnt_Table(_face, tag, 0, [table mutableBytes], &length) != 0) {
            [table release];
            return nil;
        }
        return table;
    }
}

- (NSCharacterSet *) coveredCharacterSet {
    if (_coveredCharSet == nil && _face != NULL) {
        @synchronized(self) {
            if (_coveredCharSet == nil && _face != NULL) {
                CFMutableCharacterSetRef set = CFCharacterSetCreateMutable(kCFAllocatorDefault);
                FT_UInt gindex = 0;
                FT_ULong charcode = FT_Get_First_Char(_face, &gindex);
                FT_ULong rangeStart = 0;
                FT_ULong rangeLength = 0;

                while (gindex != 0) {
                    if (charcode <= 0x10FFFF) {
                        if (rangeLength > 0 && charcode == rangeStart + rangeLength) {
                            rangeLength++;
                        } else {
                            if (rangeLength > 0) {
                                CFCharacterSetAddCharactersInRange(set, CFRangeMake(rangeStart, rangeLength));
                            }
                            rangeStart = charcode;
                            rangeLength = 1;
                        }
                    }
                    charcode = FT_Get_Next_Char(_face, charcode, &gindex);
                }
                if (rangeLength > 0) {
                    CFCharacterSetAddCharactersInRange(set, CFRangeMake(rangeStart, rangeLength));
                }
                _coveredCharSet = (NSCharacterSet *) set;
            }
        }
    }
    return _coveredCharSet;
}

FT_Face O2FontFreeTypeFace(O2Font_freetype *self) {
    return self->_face;
}

- (void) fetchAdvances {
    FT_Set_Char_Size(_face, 0, _unitsPerEm * 64, 72, 72);

    _advances = NSZoneMalloc(NULL, sizeof(NSInteger) * _numberOfGlyphs);

    for (O2Glyph glyph = 0; glyph < _numberOfGlyphs; glyph++) {
        FT_Load_Glyph(_face, glyph, FT_LOAD_DEFAULT);

        _advances[glyph] = _face->glyph->advance.x / (O2Float)(2 << 5);
    }
}

- (O2Glyph) glyphWithGlyphName: (NSString *) name {
    return FT_Get_Name_Index(_face, (char *) [name cString]);
}

- (NSString *) copyGlyphNameForGlyph: (O2Glyph) glyph {
    unsigned char buffer[100];
    if (FT_Get_Glyph_Name(_face, glyph, buffer, sizeof(buffer)) != 0) {
        return nil;
    }
    return [[NSString alloc] initWithUTF8String: (const char *) buffer];
}

- (void) getGlyphs: (O2Glyph *) glyphs
        forCodePoints: (uint16_t *) codes
               length: (NSInteger) length
{
    for (int i = 0; i < length; i++) {
        glyphs[i] = FT_Get_Char_Index(_face, codes[i]);
    }
}

- (O2Encoding *) unicode_createEncodingForTextEncoding:
        (O2TextEncoding) encoding
{
    unichar unicode[256];
    O2Glyph glyphs[256];

    switch (encoding) {
    case kO2EncodingFontSpecific:
    case kO2EncodingMacRoman:
        if (_macRomanEncoding == nil) {
            O2EncodingGetMacRomanUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _macRomanEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                           unicode: unicode];
        }
        return [_macRomanEncoding retain];

    case kO2EncodingMacExpert:
        if (_macExpertEncoding == nil) {
            O2EncodingGetMacExpertUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _macExpertEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                            unicode: unicode];
        }
        return [_macExpertEncoding retain];

    case kO2EncodingWinAnsi:
        if (_winAnsiEncoding == nil) {
            O2EncodingGetWinAnsiUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _winAnsiEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                          unicode: unicode];
        }
        return [_winAnsiEncoding retain];

    default:
        return nil;
    }
    return nil;
}

- (O2Encoding *) MacRoman_createEncodingForTextEncoding:
        (O2TextEncoding) encoding
{

    uint16_t codes[256];
    O2Glyph glyphs[256];
    unichar unicode[256];

    if (_macRomanEncoding == nil) {

        if (encoding != kO2EncodingMacRoman &&
            encoding != kO2EncodingFontSpecific) {
            NSLog(@"font encoding is MacRoman, requesting encoding %d failed",
                  encoding);
        }

        for (int i = 0; i < 256; i++) {
            codes[i] = i;
        }

        [self getGlyphs: glyphs forCodePoints: codes length: 256];

        O2EncodingGetMacExpertUnicode(unicode);

        _macRomanEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                       unicode: unicode];
    }

    return [_macRomanEncoding retain];
}

- (O2Encoding *) createEncodingForTextEncoding: (O2TextEncoding) encoding {
    if (_ftEncoding == FT_ENCODING_APPLE_ROMAN) {
        return [self MacRoman_createEncodingForTextEncoding: encoding];
    }

    return [self unicode_createEncodingForTextEncoding: encoding];
}

- (O2FreeTypeCachedGlyph *) rasterizeGlyph: (O2Glyph) glyph
                                  pointSize: (O2Float) pointSize
{
    if (_face == NULL) {
        return nil;
    }

    @synchronized(self) {
        uint64_t keyValue = ((uint64_t)(uint32_t)((long)(pointSize * 64)) << 32) |
                            glyph;
        NSNumber *key = [NSNumber numberWithUnsignedLongLong: keyValue];

        O2FreeTypeCachedGlyph *cached = [_glyphCache objectForKey: key];
        if (cached != nil) {
            return [[cached retain] autorelease];
        }

        if (FT_Load_Glyph(_face, glyph, FT_LOAD_DEFAULT) != 0) {
            return nil;
        }

        if (FT_Render_Glyph(_face->glyph, FT_RENDER_MODE_NORMAL) != 0) {
            return nil;
        }

        FT_GlyphSlot slot = _face->glyph;
        cached = [[O2FreeTypeCachedGlyph alloc]
                initWithBitmap: &slot->bitmap
                          left: slot->bitmap_left
                           top: slot->bitmap_top
                       advance: slot->advance.x];

        if ([_glyphCache count] >= O2FONT_GLYPH_CACHE_LIMIT) {
            [_glyphCache removeAllObjects];
        }

        [_glyphCache setObject: cached forKey: key];
        return [cached autorelease];
    }
}

@end

@implementation O2FreeTypeCachedGlyph

- (instancetype) initWithBitmap: (const FT_Bitmap *) srcBitmap
                            left: (NSInteger) left
                             top: (NSInteger) top
                         advance: (FT_Pos) advance
{
    bitmap.rows = srcBitmap->rows;
    bitmap.width = srcBitmap->width;
    bitmap.pitch = srcBitmap->width;
    bitmap.num_grays = 256;
    bitmap.pixel_mode = FT_PIXEL_MODE_GRAY;
    bitmap.palette_mode = 0;
    bitmap.palette = NULL;
    bitmap.buffer = NULL;

    self->left = left;
    self->top = top;
    self->advance = advance;

    if (bitmap.rows > 0 && bitmap.width > 0) {
        size_t bytes = bitmap.rows * bitmap.width;
        unsigned char *data = NSZoneMalloc(NULL, bytes);

        for (FT_Int row = 0; row < bitmap.rows; row++) {
            memcpy(data + row * bitmap.width,
                   srcBitmap->buffer + row * srcBitmap->pitch, bitmap.width);
        }

        bitmap.buffer = data;
    }

    return self;
}

- (void) dealloc {
    if (bitmap.buffer != NULL) {
        NSZoneFree(NULL, bitmap.buffer);
    }
    [super dealloc];
}

@end
#endif
