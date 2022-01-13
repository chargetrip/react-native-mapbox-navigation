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
        let coordinates = [
            CLLocationCoordinate2D.init(latitude: 0, longitude: 0),
            CLLocationCoordinate2D.init(latitude: 0, longitude: 0)
        ]
        
        do {
            let accessToken = Bundle.main.object(forInfoDictionaryKey: "MGLMapboxAccessToken") as? String
            let decoder = JSONDecoder()

            decoder.userInfo = [
                .options: RouteOptions(coordinates: coordinates, profileIdentifier: .automobile),
                .credentials: DirectionsCredentials(
                    accessToken: accessToken,
                    host: URL(string: "https://api.mapbox.com")!
                )
            ]
            
            let stringSwift = route as String
            let jsonData = Data(stringSwift.utf8)
            let result = try decoder.decode(Route.self, from: jsonData)
            let shape = result.shape
            let encodedPolyline = Polyline(coordinates: shape!.coordinates).encodedPolyline
            let polyline = Polyline(encodedPolyline: encodedPolyline, precision: 1e6)
            
            let correctedPrecisionRoute = Route(
                legs: result.legs,
                shape: LineString(polyline.coordinates!),
                distance: result.distance,
                expectedTravelTime: result.expectedTravelTime,
                typicalTravelTime: result.typicalTravelTime
            )
            
            return correctedPrecisionRoute
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
        
        let coordinates = [
            CLLocationCoordinate2D.init(latitude: 0, longitude: 0),
            CLLocationCoordinate2D.init(latitude: 0, longitude: 0)
        ]
        
        let routeOptions = NavigationRouteOptions(coordinates: coordinates, profileIdentifier: .automobile)
        let navigationService = MapboxNavigationService(route: mappedRoute, routeIndex: 0, routeOptions: routeOptions, simulating: shouldSimulateRoute ? .always : .never)
        navigationService.router.reroutesProactively = false

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

extension MapboxNavigationView: NavigationViewControllerDelegate {
    func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
      if (!canceled) {
        return;
      }
      onCancelNavigation?(["message": ""]);
    }
    
    func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) -> Bool {
      onArrive?(["message": ""]);
      return true;
    }
    
    func navigationService(_ navigationViewController: NavigationViewController, willRerouteFrom location: CLLocation) {
        print("Will reroute")
        return
    }
    
    func navigationViewController(_ navigationViewController: NavigationViewController, shouldRerouteFrom location: CLLocation) -> Bool {
    print("Wants reroute")
            
    return false
    }
     
    func navigationViewController(_ navigationViewController: NavigationViewController, didUpdate progress: RouteProgress, with location: CLLocation, rawLocation: CLLocation) {
      onLocationChange?(["longitude": location.coordinate.longitude, "latitude": location.coordinate.latitude])
      onRouteProgressChange?(["distanceTraveled": progress.distanceTraveled,
                              "durationRemaining": progress.durationRemaining,
                              "fractionTraveled": progress.fractionTraveled,
                              "distanceRemaining": progress.distanceRemaining])
    }

}
