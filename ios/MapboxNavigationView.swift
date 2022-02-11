import MapboxCoreNavigation
import MapboxDirections
import MapboxNavigation
import Foundation
import Turf
import Polyline

extension UIView {
  var parentViewController: UIViewController? {
    var parentResponder: UIResponder? = self
    while parentResponder != nil {
      parentResponder = parentResponder!.next
      if let viewController = parentResponder as? UIViewController {
        return viewController
      }
    }
      return nil
  }
}

extension CLLocationCoordinate2D: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(longitude)
        try container.encode(latitude)
    }
     
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let longitude = try container.decode(CLLocationDegrees.self)
        let latitude = try container.decode(CLLocationDegrees.self)
        self.init(latitude: latitude, longitude: longitude)
    }
}

struct WaypointCTProperties: Codable {
    let text: String?
}

struct WaypointCT: Codable {
    let geometry: CLLocationCoordinate2D
    let type: String
    let properties: WaypointCTProperties
}


extension MapboxNavigationView: NavigationViewControllerDelegate {
    
    func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) -> Bool {
        let isFinalLeg = navigationViewController.navigationService.routeProgress.isFinalLeg
        
        do {

            let encoder = JSONEncoder()
            let waypointData = try encoder.encode(waypoint)
            let waypointString = String(data: waypointData, encoding: .utf8)
            
            onArrive?([
                "waypoint": waypointString,
                "isFinalLeg": isFinalLeg,
                "index": navigationViewController.navigationService.routeProgress.legIndex
            ])
            
            if !isFinalLeg {
                print("Advance legs!")
                navigationViewController.navigationService.router.advanceLegIndex()
                navigationViewController.navigationService.start()
                print("Should have started..")
            }
            
        } catch {
            print("Error onDidArive : \(error)")
        }
        
     return isFinalLeg
    }

    
    func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
      if (!canceled) {
        return;
      }
      onCancelNavigation?(["message": ""]);
    }
    

    
    func navigationService(_ navigationViewController: NavigationViewController, willRerouteFrom location: CLLocation) {
        print("Will reroute")
        return
    }
    
    func navigationViewController(_ navigationViewController: NavigationViewController, shouldRerouteFrom location: CLLocation) -> Bool {
        print("Will trigger onReroute")
        onReroute?(["coordinate": [location.coordinate.longitude, location.coordinate.latitude],
                    "speed": location.speed,
                    "altitude": location.altitude,
                    "course": location.course,
                    "legIndex": navigationViewController.navigationService.routeProgress.legIndex
        ])
      
    return true
    }
     
    func navigationViewController(_ navigationViewController: NavigationViewController, didUpdate progress: RouteProgress, with location: CLLocation, rawLocation: CLLocation) {
      onLocationChange?(["longitude": location.coordinate.longitude, "latitude": location.coordinate.latitude])
      onRouteProgressChange?(["distanceTraveled": progress.distanceTraveled,
                              "durationRemaining": progress.durationRemaining,
                              "fractionTraveled": progress.fractionTraveled,
                              "distanceRemaining": progress.distanceRemaining])
    }
    
    // func navigationMapView(_ mapView: NavigationMapView, shapeFor waypoints: [Waypoint]) -> MGLShape? {
    //     var pointFeatures: [MGLPointFeature] = []
        
    //     for waypoint in waypoints {
    //         let point = MGLPointFeature()
    //         point.attributes = ["title" : waypoint.name!]
    //         pointFeatures.append(point)
    //     }
        
    //     let shapeCollection = MGLShapeCollectionFeature(shapes: pointFeatures)
    //     return shapeCollection
    // }
    
    func navigationViewController(_ navigationViewController: NavigationViewController, waypointSymbolStyleLayerWithIdentifier identifier: String, source: MGLSource) -> MGLStyleLayer? {
        let styleLayer = MGLSymbolStyleLayer(identifier: identifier, source: source)
        return styleLayer
    }

    func navigationViewController(_ navigationViewController: NavigationViewController, waypointStyleLayerWithIdentifier identifier: String, source: MGLSource) -> MGLStyleLayer? {
        drawIcons()
        let styleLayer = MGLSymbolStyleLayer(identifier: identifier, source: source)
        return styleLayer
    }
    
    func getWaypointOptions() -> [Waypoint] {
        let originCoordinate = CLLocationCoordinate2D(latitude: origin[1] as! Double, longitude: origin[0] as! Double)
        let destinationCoordinate = CLLocationCoordinate2D(latitude: destination[1] as! Double, longitude: destination[0] as! Double)
    
        var mappedWaypoints: [Waypoint] = [ Waypoint(coordinate: originCoordinate) ]
        
        waypoints.forEach { dictionary in
            guard let dict = dictionary as? [String: Any] else { return }
 
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
                let data = try JSONDecoder().decode(WaypointCT.self, from: jsonData)
                let coordinate = CLLocationCoordinate2D(latitude: data.geometry.latitude, longitude: data.geometry.longitude)
                
                mappedWaypoints.append(Waypoint(coordinate: coordinate))
                
            } catch {
                print(error)
            }
        }
        
        mappedWaypoints.append(Waypoint(coordinate: destinationCoordinate)) // Add destination

        return mappedWaypoints
    }
    
    func drawIcons() {
        if let style = self.navViewController?.mapView?.style {
            var stationFeatures: [MGLPointFeature] = []
            var finalFeatures: [MGLPointFeature] = []
            var viaFeatures: [MGLPointFeature] = []

            waypoints.forEach { dictionary in
                guard let dict = dictionary as? [String: Any] else { return }

                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
                    let data = try JSONDecoder().decode(WaypointCT.self, from: jsonData)
                    
                    let newFeature = MGLPointFeature()
                    newFeature.coordinate = data.geometry
                    newFeature.attributes = [:]
                    
                    switch(data.type) {
                        case "stationVia":
                        newFeature.attributes = [
                            "text": data.properties.text!
                        ]
                            stationFeatures.append(newFeature)
                        case "station":
                        newFeature.attributes = [
                            "text": data.properties.text!
                        ]
                            stationFeatures.append(newFeature)
                        case "via":
                            newFeature.attributes = [
                                "text": data.properties.text!
                            ]
                            viaFeatures.append(newFeature)
                    default:
                        return
                    }
                    
                } catch {
                    print(error)
                }
            }

            if !stationFeatures.isEmpty {
                style.setImage(UIImage(named: "station")!, forName: "stationIcon")
                
                if let iconSource = style.source(withIdentifier: "stationSource") as? MGLShapeSource {
                    let collection = MGLShapeCollectionFeature(shapes: stationFeatures)
                    iconSource.shape = collection
                } else {
                    let iconSource = MGLShapeSource(identifier: "stationSource", features: stationFeatures, options: nil)
                    let symbols = MGLSymbolStyleLayer(identifier: "stationLayer", source: iconSource)
                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)
                    symbols.textAllowsOverlap = NSExpression(forConstantValue: true)
                    symbols.iconImageName = NSExpression(forConstantValue: "stationIcon")
                    symbols.text = NSExpression(forKeyPath: "text")
                    symbols.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -25)))
                    symbols.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0.70, dy: -3.25))) // .5
                    symbols.textFontNames = NSExpression(forConstantValue: NSArray(array: ["Roboto Bold"]))
                    symbols.textFontSize = NSExpression(forConstantValue: NSNumber(value: 12))
                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)
        
                    style.addSource(iconSource)
                    style.addLayer(symbols)
                }
            }
            
            if !viaFeatures.isEmpty {
                style.setImage(UIImage(named: "via")!, forName: "viaIcon")
                
                if let iconSource = style.source(withIdentifier: "viaSource") as? MGLShapeSource {
                    let collection = MGLShapeCollectionFeature(shapes: viaFeatures)
                    iconSource.shape = collection
                } else {
                    let iconSource = MGLShapeSource(identifier: "viaSource", features: viaFeatures, options: nil)
                    let symbols = MGLSymbolStyleLayer(identifier: "viaLayer", source: iconSource)
                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)
                    symbols.textAllowsOverlap = NSExpression(forConstantValue: true)
                    symbols.iconImageName = NSExpression(forConstantValue: "viaIcon")
                    symbols.text = NSExpression(forKeyPath: "text")
                    symbols.textColor = NSExpression(forConstantValue: UIColor.white)
                    symbols.textFontNames = NSExpression(forConstantValue: NSArray(array: ["Roboto Bold"]))
                    symbols.textFontSize = NSExpression(forConstantValue: NSNumber(value: 16))
                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)
        
                    style.addSource(iconSource)
                    style.addLayer(symbols)
                }
            }
            
            let finalFeature = MGLPointFeature()
            finalFeature.coordinate = CLLocationCoordinate2D(latitude: destination[1] as! Double, longitude: destination[0] as! Double)
            finalFeature.attributes = [:]
            finalFeatures.append(finalFeature)
            
            style.setImage(UIImage(named: "destination")!, forName: "finalIcon")
            
            if let iconSource = style.source(withIdentifier: "finalSource") as? MGLShapeSource {
                let collection = MGLShapeCollectionFeature(shapes: finalFeatures)
                iconSource.shape = collection
            } else {
                let iconSource = MGLShapeSource(identifier: "finalSource", features: finalFeatures, options: nil)
                let symbols = MGLSymbolStyleLayer(identifier: "finalLayer", source: iconSource)
                symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)
                symbols.textAllowsOverlap = NSExpression(forConstantValue: true)
                symbols.iconImageName = NSExpression(forConstantValue: "finalIcon")
                symbols.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -20)))
                
                style.addSource(iconSource)
                style.addLayer(symbols)
            }
            
        }
    }

}
    
class MapboxNavigationView: UIView {
    weak var navViewController: NavigationViewController?
      
    @objc var shouldSimulateRoute: Bool = false
    @objc var showsEndOfRouteFeedback: Bool = false
    @objc var hideStatusView: Bool = false
    @objc var mute: Bool = false
    @objc var route: NSString = ""
    @objc var onLocationChange: RCTDirectEventBlock?
    @objc var onRouteProgressChange: RCTDirectEventBlock?
    @objc var onError: RCTDirectEventBlock?
    @objc var onCancelNavigation: RCTDirectEventBlock?
    @objc var onArrive: RCTDirectEventBlock?
    @objc var origin: NSArray = [] {
      didSet { setNeedsLayout() }
    }
    @objc var destination: NSArray = [] {
      didSet { setNeedsLayout() }
    }
    @objc var waypoints: [NSDictionary] = [] {
      didSet { setNeedsLayout() }
    }
    @objc var onReroute: RCTDirectEventBlock?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if (navViewController == nil) {
            embed()
        } else {
           navViewController?.view.frame = bounds
        }
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        // cleanup and teardown any existing resources
        self.navViewController?.removeFromParent()
    }
    
    private func getMappedRoute() -> Route? {
        let stringSwift = route as String
        let jsonData = Data(stringSwift.utf8)
        let waypointOptions = getWaypointOptions()
        
        do {
            // Prepare decoder
            let decoder = JSONDecoder()
            decoder.userInfo = [
                .options: RouteOptions(waypoints: waypointOptions, profileIdentifier: .automobile),
                .credentials: DirectionsCredentials(
                    accessToken: Bundle.main.object(forInfoDictionaryKey: "MGLMapboxAccessToken") as? String,
                    host: URL(string: "https://api.mapbox.com")!
                )
            ]
            
            let result = try decoder.decode(Route.self, from: jsonData)
            
            return result
        } catch let error {
            print(error)
            self.onError!(["message": error.localizedDescription])
        }
        
        return nil
    }
    
    private func embed() {
        guard let mappedRoute = getMappedRoute(), let parentVC = self.parentViewController else {
            return
        }
        
        let waypointOptions = getWaypointOptions()
        let routeOptions = NavigationRouteOptions(waypoints: waypointOptions, profileIdentifier: .automobile)
        routeOptions.allowsUTurnAtWaypoint = true

        let navigationService = MapboxNavigationService(route: mappedRoute, routeIndex: 0, routeOptions: routeOptions, simulating: shouldSimulateRoute ? .always : .never)
        navigationService.router.reroutesProactively = false
        navigationService.router.refreshesRoute = false

        let navigationOptions = NavigationOptions(navigationService: navigationService)
        let navigationViewController = NavigationViewController(for: mappedRoute, routeIndex: 0, routeOptions: routeOptions, navigationOptions: navigationOptions)
        navigationViewController.showsEndOfRouteFeedback = self.showsEndOfRouteFeedback
        StatusView.appearance().isHidden = self.hideStatusView
        NavigationSettings.shared.voiceMuted = self.mute;
        navigationViewController.delegate = self
        navigationViewController.view.frame = self.frame
        self.addSubview(navigationViewController.view)
        navigationViewController.didMove(toParent: self.parentViewController)


        parentVC.addChild(navigationViewController)
        self.addSubview(navigationViewController.view)
        navigationViewController.view.frame = self.bounds
        navigationViewController.didMove(toParent: parentVC)
        self.navViewController = navigationViewController
 
    }
}
