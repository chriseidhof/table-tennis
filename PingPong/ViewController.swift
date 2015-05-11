//
//  ViewController.swift
//  PingPong
//
//  Created by Chris Eidhof on 26.07.14.
//  Copyright (c) 2014 objc.io. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit


struct Table {
    let id: String
    let location: CLLocationCoordinate2D
    let info: String
    // TODO
}

class Parser : NSObject, NSXMLParserDelegate {
    let parser : NSXMLParser
    var tables : [Table] = []
    
    init(url: NSURL) {
        parser = NSXMLParser(contentsOfURL: url)!
    }

    func parse() -> [Table] {
        if tables.count == 0 {
            parser.delegate = self
            parser.parse()
        }
        
        return tables
    }
    
    func parser(parser: NSXMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [NSObject : AnyObject]) {
        if elementName != "marker" { return }
        
        let mkTable = {id in { location in {info in Table(id: id, location: location, info: info) } } }
        let mkLocation = {lat in { lon in CLLocationCoordinate2D(latitude: lat, longitude: lon) } }
        
        let id = string(attributeDict, "id")
        let location = pure(mkLocation) <*> double(attributeDict, "lat") <*> double(attributeDict, "lng")
        let info = string(attributeDict, "info")
        if let table = pure(mkTable) <*> id <*> location <*> info {
            tables.append(table)
        } else {
            println("Couldn't parse \(elementName) \(attributeDict)")
        }
    }
}

class Annotation : NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String
    var subtitle: String
    
    init(table: Table) {
        self.coordinate = table.location
        self.title = table.id
        self.subtitle = table.info
    }
}

class ClusterAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var count: Int
    
    var title: String { return "\(count)" }
    
    init(coordinate: CLLocationCoordinate2D, count: Int) {
        self.coordinate = coordinate
        self.count = count
    }

}

extension CGRect {
    static func fromMapRect(rect: MKMapRect) -> CGRect {
        var result = CGRect()
        result.origin.x = CGFloat(rect.origin.x)
        result.origin.y = CGFloat(rect.origin.y)
        result.size.width = CGFloat(rect.size.width)
        result.size.height = CGFloat(rect.size.height)
        return result
    }
    
    static func fromRegion(region: MKCoordinateRegion) -> CGRect {
        let midX = CGFloat(region.center.latitude)
        let midY = CGFloat(region.center.longitude)
        let width = CGFloat(region.span.latitudeDelta)
        let height = CGFloat(region.span.longitudeDelta)
        return CGRect(origin: CGPoint(x: midX-width/2, y: midY-height/2), size: CGSizeMake(width, height))
    }
    
    func squareCellsWithWidth(cellWidth: CGFloat) -> [CGRect] {
        let horizontalCells = Int(ceil(width / cellWidth))
        let verticalCells = Int(ceil(height / cellWidth))
        var result: [CGRect] = []
        for i in 0..<horizontalCells {
            for j in 0..<verticalCells {
                let cell = CGRect(x: origin.x + cellWidth*CGFloat(i), y: origin.y + cellWidth * CGFloat(j), width: cellWidth, height: cellWidth)
                result.append(cell)
            }
        }
        return result
    }
    
    func centerInRect(rect: CGRect) -> CGRect {
        let offsetX = (rect.size.width - width) / 2
        let offsetY = (rect.size.height - height) / 2
        return CGRect(x: origin.x + offsetX, y: origin.y + offsetY, width: width, height: height)
    }
}

struct Cluster<A> {
    var position: CLLocationCoordinate2D
    var points: [Point<A>]
    var count: Int {
        return points.count
    }
}

enum ClusterOrPoint<A> {
    case CPoint(Point<A>)
    case CCluster(Cluster<A>)
}

func average(locations: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
    let ratio = Double(locations.count)
    return locations.reduce(CLLocationCoordinate2D(latitude: 0, longitude: 0)) { (result, coord) in
        CLLocationCoordinate2D(latitude: result.latitude + coord.latitude/ratio, longitude: result.longitude + coord.longitude/ratio)
    }
}

func cluster(points: [Point<Annotation>]) -> ClusterOrPoint<Annotation>? {
    if let point = points.first where points.count == 1 {
        return .CPoint(point)
    } else if points.count > 0 { // TODO calculate real average
        let coordinates = points.map { $0.value.unbox.coordinate }
        return .CCluster(Cluster(position: average(coordinates), points: points))
    }
    return nil
}

func compact<A>(x: [A?]) -> [A] {
    return x.reduce([]) { (var arr, el) in
        if let e = el {
            arr.append(e)
        }
        return arr
    }
}

func imageWithNumber(x: Int) -> UIImage {
    let rect = CGRectMake(0, 0, 25,25)
    UIGraphicsBeginImageContext(rect.size)
    let ref = UIGraphicsGetCurrentContext()
    UIColor.greenColor().setFill()
    CGContextFillEllipseInRect(ref, rect)
    UIColor.blackColor().set()
    let str = NSAttributedString(string: "\(x)")
    var boundingRect = str.boundingRectWithSize(rect.size, options: NSStringDrawingOptions.allZeros, context: nil)
    boundingRect.origin = CGPointZero
    let centered = boundingRect.centerInRect(rect)
    println(centered)
    str.drawInRect(centered)
    let result = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return result
}

class Delegate: NSObject, MKMapViewDelegate {
    var quadTree: QuadTree<Annotation> = empty(mapRegion)
    
    let annotationIdentifier = "ClusterIdentifier"
    
    
    func mapView(mapView: MKMapView!, regionDidChangeAnimated animated: Bool) {
        let rect = CGRect.fromRegion(mapView.region)
        let numberOfRegions: CGFloat = 6
        let cellWidth = rect.width / numberOfRegions
        println(cellWidth)
        
        let searchRect = CGRectMake(rect.origin.x - fmod(rect.origin.x, cellWidth), rect.origin.y - fmod(rect.origin.y, cellWidth), rect.width + cellWidth, rect.height + cellWidth)
        
        let anns = annotationsInRect(rect, quadTree)
        let cells = rect.squareCellsWithWidth(cellWidth)
        let clusteredAnns: [(ClusterOrPoint<Annotation>?)] = map(cells) { cell in
            let anns = annotationsInRect(cell, self.quadTree)
            return cluster(anns)
        }
        
        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations(compact(map(clusteredAnns) { (pointOrCluster: ClusterOrPoint<Annotation>?) -> MKAnnotation? in
            if let subject = pointOrCluster {
            switch subject {
            case .CPoint(let p): return p.value.unbox
            case .CCluster(let c): return ClusterAnnotation(coordinate: c.position, count: c.count)
            }
            }
            return nil
        }))
    }
    
    func mapView(mapView: MKMapView!, viewForAnnotation annotation: MKAnnotation!) -> MKAnnotationView! {
        if let point = annotation as? Annotation {
            let view = MKPinAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.canShowCallout = true
            view.pinColor = .Green
            return view
        } else if let point = annotation as? ClusterAnnotation,
                  let annotationView =  mapView.dequeueReusableAnnotationViewWithIdentifier(annotationIdentifier)
                                     ?? MKAnnotationView(annotation: point, reuseIdentifier: annotationIdentifier)
        {
            annotationView.image = imageWithNumber(point.count)
            return annotationView
        }
        return nil
    }
    
    func mapView(mapView: MKMapView!, annotationView view: MKAnnotationView!, calloutAccessoryControlTapped control: UIControl!) {
        // todo
    }
}

extension CLLocationCoordinate2D {
    var cgPoint: CGPoint {
        return CGPoint(x: latitude, y: longitude)
    }
}

extension CGPoint {
    var location: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: Double(x), longitude: Double(y))
    }
}

class ViewController: UIViewController {
    
    var tables : [Table] = []
    var delegate: Delegate = Delegate()
    var quadTree: QuadTree<Annotation> = empty(mapRegion) {
        didSet {
            delegate.quadTree = quadTree
        }
    }
    
    @IBOutlet var mapView : MKMapView!
    
    lazy var locationManager: CLLocationManager = CLLocationManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let url = NSBundle.mainBundle().URLForResource("places", withExtension: "xml")!
        
        navigationItem.leftBarButtonItem = MKUserTrackingBarButtonItem(mapView: mapView)
        if CLLocationManager.authorizationStatus() == CLAuthorizationStatus.NotDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        
        mapView.delegate = delegate
        
        backgroundJob({
            let parser = Parser(url: url)

            self.tables = parser.parse()
            let anns = self.tables.map {
                Annotation(table: $0)
            }
            self.quadTree = buildTree(mapRegion, anns.map { ann in
                let point: CGPoint = ann.coordinate.cgPoint
                return Point(point: point, value: Box(ann))
            })
            return anns
            }) { (annotations: [Annotation] ) in
            //self.mapView.addAnnotations(annotations)
            ()
        }
    }

}

