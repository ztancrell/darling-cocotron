/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/AppKitExport.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

typedef NSString *NSVoiceGenderName;

APPKIT_EXPORT NSVoiceGenderName const NSVoiceGenderFemale;
APPKIT_EXPORT NSVoiceGenderName const NSVoiceGenderMale;

typedef NSString *NSVoiceAttributeKey;

APPKIT_EXPORT NSVoiceAttributeKey const NSVoiceName;
APPKIT_EXPORT NSVoiceAttributeKey const NSVoiceGender;
APPKIT_EXPORT NSVoiceAttributeKey const NSVoiceDemoText;
APPKIT_EXPORT NSVoiceAttributeKey const NSVoiceLocaleIdentifier;

typedef NSString *NSSpeechPropertyKey;

APPKIT_EXPORT NSSpeechPropertyKey const NSSpeechRateProperty;
APPKIT_EXPORT NSSpeechPropertyKey const NSSpeechPitchBaseProperty;
APPKIT_EXPORT NSSpeechPropertyKey const NSSpeechVolumeProperty;

@interface NSSpeechSynthesizer : NSObject {
    NSString *_voice;
}

// The voice query API. There is no speech synthesis engine here, so the voice list is
// empty and per-voice lookups come back empty rather than reporting voices that cannot
// speak.
//
// These return objects, which matters: the catch-all stub below answers every unimplemented
// selector with a "v@:" signature, so an object-returning method left to it hands back
// whatever happened to be in the return register.
+ (NSArray *) availableVoices;
+ (NSString *) voiceAtIndex: (NSInteger) index;
- (NSDictionary *) attributesForVoice: (NSString *) voiceIdentifier;
- (instancetype) initWithVoice: (NSString *) voice;
@property (nonatomic, readonly) NSString *voice;

@end

@protocol NSSpeechSynthesizerDelegate <NSObject>

// TODO

@end
