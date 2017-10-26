//
//  MapViewController.h
//  ObjCVideoQuickstart
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

@interface MapViewController : UIViewController

@property (nonatomic, copy) NSString *identity;
@property (nonatomic, strong) CLLocation *location;

@end
