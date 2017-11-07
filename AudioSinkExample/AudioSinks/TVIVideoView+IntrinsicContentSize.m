//
//  TVIVideoView+IntrinsicContentSize.m
//  AudioSinkExample
//
//  Copyright © 2017 Twilio Inc. All rights reserved.
//

#import "TVIVideoView+IntrinsicContentSize.h"

@implementation TVIVideoView (IntrinsicContentSize)

- (CGSize)intrinsicContentSize {
    // TVIVideoView does not define an intrinsic size. We will use the current dimensions as a placeholder.
    // UIStackView will use this as a part of its layout process.
    return CGSizeMake(self.videoDimensions.width, self.videoDimensions.height);
}

@end
