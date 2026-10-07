#import <QuartzCore/CALayer.h>

// ponytail: an ordinary layer. Its one difference on macOS, that sublayers keep their depth instead
// of being flattened into its plane, means nothing to a renderer that draws in two dimensions.
@interface CATransformLayer : CALayer
@end

@implementation CATransformLayer
@end
