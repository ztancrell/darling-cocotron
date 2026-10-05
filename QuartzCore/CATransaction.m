#import "CATransactionGroup.h"
#import "CATransactionInternal.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CATransaction.h>

NSString *const kCATransactionAnimationDuration =
        @"kCATransactionAnimationDuration";
NSString *const kCATransactionDisableActions = @"kCATransactionDisableActions";
NSString *const kCATransactionAnimationTimingFunction =
        @"kCATransactionAnimationTimingFunction";
NSString *const kCATransactionCompletionBlock =
        @"kCATransactionCompletionBlock";

@implementation CATransaction

static NSMutableArray *transactionStack() {
    NSMutableDictionary *shared = [NSCurrentThread() sharedDictionary];
    id stack = [shared objectForKey: @"CATransactionStack"];

    if (stack == nil) {
        stack = [NSMutableArray array];
        [shared setObject: stack forKey: @"CATransactionStack"];
    }

    return stack;
}

static CATransactionGroup *currentTransactionGroup() {
    id stack = transactionStack();

    CATransactionGroup *result = [stack lastObject];

    return result;
}

static CATransactionGroup *createImplicitTransactionGroupIfNeeded() {
    CATransactionGroup *check = currentTransactionGroup();

    if (check == nil) {
        check = [[CATransactionGroup alloc] init];

        [transactionStack() addObject: check];
        [check release]; // The stack owns the active transaction.
        [[NSRunLoop currentRunLoop]
                performSelector: @selector(commit)
                         target: [CATransaction class]
                       argument: nil
                          order: 0
                          modes: [NSArray arrayWithObject:
                                                  NSDefaultRunLoopMode]];
    }

    return check;
}

+ (BOOL) disableActions {
    return [[self valueForKey: kCATransactionDisableActions] boolValue];
}

+ (CFTimeInterval) animationDuration {
    return [[self valueForKey: kCATransactionAnimationDuration] doubleValue];
}

+ (CAMediaTimingFunction *) animationTimingFunction {
    return [self valueForKey: kCATransactionAnimationTimingFunction];
}

//+(void (^)(void))completionBlock;

+ valueForKey: (NSString *) key {
    CATransactionGroup *group = createImplicitTransactionGroupIfNeeded();

    return [group valueForKey: key];
}

+ (void) setAnimationDuration: (CFTimeInterval) value {
    [self setValue: [NSNumber numberWithDouble: value]
            forKey: kCATransactionAnimationDuration];
}

+ (void) setAnimationTimingFunction: (CAMediaTimingFunction *) value {
    [self setValue: value forKey: kCATransactionAnimationTimingFunction];
}

//+(void)setCompletionBlock:(void (^)(void))value;
+ (void) setDisableActions: (BOOL) value {
    [self setValue: [NSNumber numberWithBool: value]
            forKey: kCATransactionDisableActions];
}

+ (void) setValue: value forKey: (NSString *) key {
    CATransactionGroup *group = createImplicitTransactionGroupIfNeeded();

    [group setValue: value forKey: key];
}

+ (void) begin {
    CATransactionGroup *group = [[CATransactionGroup alloc] init];

    [group setExplicitlyBegan: YES];
    [transactionStack() addObject: group];
    [group release];
}

+ (BOOL) hasOpenTransaction {
    CATransactionGroup *group = currentTransactionGroup();

    return group != nil && [group isExplicitlyBegan];
}

// Private API (Chromium uses it to line its frames up with window changes).
// Phases: 0 before layout, 1 before the commit, 2 after it. Layout and commit
// are not separate steps here, so 0 and 1 run back to back.
static NSString *commitHandlersKey(int phase) {
    return [NSString stringWithFormat: @"CACommitHandlers%d", phase];
}

+ (BOOL) addCommitHandler: (void (^)(void)) handler forPhase: (int) phase {
    if (handler == nil || phase < 0 || phase > 2)
        return NO;

    CATransactionGroup *group = createImplicitTransactionGroupIfNeeded();
    NSMutableArray *handlers = [group valueForKey: commitHandlersKey(phase)];

    if (handlers == nil) {
        handlers = [NSMutableArray array];
        [group setValue: handlers forKey: commitHandlersKey(phase)];
    }
    [handlers addObject: [[handler copy] autorelease]];
    return YES;
}

static void runCommitHandlers(CATransactionGroup *group, int phase) {
    // A handler may add handlers; those belong to a later commit.
    NSArray *handlers = [[[group valueForKey: commitHandlersKey(phase)] copy]
            autorelease];

    for (void (^handler)(void) in handlers)
        handler();
}

+ (void) commit {
    CATransactionGroup *group = [[currentTransactionGroup() retain] autorelease];

    if (group == nil)
        return;
    runCommitHandlers(group, 0);
    runCommitHandlers(group, 1);
    // Not removeLastObject: a handler may have left a transaction of its own open.
    [transactionStack() removeObjectIdenticalTo: group];
    runCommitHandlers(group, 2);
}

+ (void) flush {
}

+ (void) lock {
}

+ (void) unlock {
}

@end
