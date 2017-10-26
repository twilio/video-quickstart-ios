//
//  MapViewController.swift
//  VideoQuickStart
//
//  Created by Ryan Payne on 10/25/17.
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit

class MapViewController: UIViewController {

    var identity: String?
    var location: CLLocation?

    @IBOutlet weak var mapView: MKMapView!

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let location = self.location {
            let center = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))

            mapView!.setRegion(region, animated: true)

            let annotation: MKPointAnnotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2DMake(location.coordinate.latitude, location.coordinate.longitude);

            if let identity = identity {
                self.title = identity
                annotation.title = identity
            }

            mapView!.addAnnotation(annotation)
        }
    }
}
