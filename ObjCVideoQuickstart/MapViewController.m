//
//  MapViewController.m
//  ObjCVideoQuickstart
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//
#import "MapViewController.h"

#import <MapKit/MapKit.h>

@interface MapViewController ()

@property (weak, nonatomic) IBOutlet MKMapView *mapView;

@end

@implementation MapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    CLLocationCoordinate2D center = CLLocationCoordinate2DMake(self.location.coordinate.latitude, self.location.coordinate.longitude);
    MKCoordinateRegion region = MKCoordinateRegionMake(center, MKCoordinateSpanMake(0.01, 0.01));

    MKPointAnnotation *annotation = [MKPointAnnotation new];
    annotation.coordinate = CLLocationCoordinate2DMake(self.location.coordinate.latitude, self.location.coordinate.longitude);
    annotation.title = self.identity;

    [self.mapView setRegion:region animated:YES];
    [self.mapView addAnnotation:annotation];

    self.title = self.identity;
}

@end
