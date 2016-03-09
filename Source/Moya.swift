import Foundation
import Result

/// Closure to be executed when a request has completed.
public typealias Completion = (result: Result<Moya.Response, Moya.Error>) -> ()

/// Represents an HTTP method.
public enum Method: String {
    case GET, POST, PUT, DELETE, OPTIONS, HEAD, PATCH, TRACE, CONNECT
}

public enum StubBehavior {
    case Never
    case Immediate
    case Delayed(seconds: NSTimeInterval)
}

/// Protocol to group endpoints as associated types in enum cases.
public protocol ServiceType { }

public extension ServiceType {
    
    /// If possible get the TargetType of current object.
    /// For Moya <= 6.2.0 its always possible. Otherwise user can create enum
    /// that conforms to ServiceType, but it doesn't necessarily have to have
    /// cases only with TargetType as associated object.
    public var resource: TargetType? {
        // If we are already TargetType, return self
        if let targetType = self as? TargetType {
            return targetType
        }
        
        // Otherwise we believe that user made enum with associated type = TargetType..
        let mirror = Mirror(reflecting: self)
        return mirror.children.first?.value as? TargetType
    }
    
}

/// Protocol to define the base URL, path, method, parameters and sample data for a target.
public protocol TargetType: ServiceType {
    var baseURL: NSURL { get }
    var path: String { get }
    var method: Moya.Method { get }
    var parameters: [String: AnyObject]? { get }
    var sampleData: NSData { get }
}

/// Protocol to define the opaque type returned from a request
public protocol Cancellable {
    func cancel()
}

/// Request provider class. Requests should be made through this class only.
public class MoyaProvider<Target: ServiceType> {
    
    /// Closure that defines the endpoints for the provider.
    public typealias EndpointClosure = TargetType -> Endpoint<TargetType>
    
    /// Closure that resolves an Endpoint into an NSURLRequest.
    public typealias RequestClosure = (Endpoint<TargetType>, NSURLRequest -> Void) -> Void
    
    /// Closure that decides if/how a request should be stubbed.
    public typealias StubClosure = TargetType -> Moya.StubBehavior
    
    public let endpointClosure: EndpointClosure
    public let requestClosure: RequestClosure
    public let stubClosure: StubClosure
    public let manager: Manager
    
    /// A list of plugins
    /// e.g. for logging, network activity indicator or credentials
    public let plugins: [PluginType]
    
    /// Initializes a provider.
    public init(endpointClosure: EndpointClosure = MoyaDefaults.DefaultEndpointMapping,
        requestClosure: RequestClosure = MoyaDefaults.DefaultRequestMapping,
        stubClosure: StubClosure = MoyaDefaults.NeverStub,
        manager: Manager = MoyaDefaults.DefaultAlamofireManager(),
        plugins: [PluginType] = []) {
            
            self.endpointClosure = endpointClosure
            self.requestClosure = requestClosure
            self.stubClosure = stubClosure
            self.manager = manager
            self.plugins = plugins
    }
    
    /// Returns an Endpoint based on the token, method, and parameters by invoking the endpointsClosure.
    public func endpoint(token: TargetType) -> Endpoint<TargetType> {
        return endpointClosure(token)
    }
    
    /// Designated request-making method. Returns a Cancellable token to cancel the request later.
    public func request(target: Target, completion: Moya.Completion) -> Cancellable {
        guard let target = target.resource else {
            fatalError("Your Moya setup is wrong.")
        }
        
        let endpoint = self.endpoint(target)
        let stubBehavior = self.stubClosure(target)
        var cancellableToken = CancellableWrapper()
        
        let performNetworking = { (request: NSURLRequest) in
            if cancellableToken.isCancelled { return }
            
            switch stubBehavior {
            case .Never:
                cancellableToken.innerCancellable = self.sendRequest(target, request: request, completion: completion)
            default:
                cancellableToken.innerCancellable = self.stubRequest(target, request: request, completion: completion, endpoint: endpoint, stubBehavior: stubBehavior)
            }
        }
        
        requestClosure(endpoint, performNetworking)
        
        return cancellableToken
    }
    
    /// When overriding this method, take care to `notifyPluginsOfImpendingStub` and to perform the stub using the `createStubFunction` method.
    /// Note: this was previously in an extension, however it must be in the original class declaration to allow subclasses to override.
    internal func stubRequest(target: TargetType, request: NSURLRequest, completion: Moya.Completion, endpoint: Endpoint<TargetType>, stubBehavior: Moya.StubBehavior) -> CancellableToken {
        let cancellableToken = CancellableToken { }
        notifyPluginsOfImpendingStub(request, target: target)
        let plugins = self.plugins
        let stub: () -> () = createStubFunction(cancellableToken, forTarget: target, withCompletion: completion, endpoint: endpoint, plugins: plugins)
        switch stubBehavior {
        case .Immediate:
            stub()
        case .Delayed(let delay):
            let killTimeOffset = Int64(CDouble(delay) * CDouble(NSEC_PER_SEC))
            let killTime = dispatch_time(DISPATCH_TIME_NOW, killTimeOffset)
            dispatch_after(killTime, dispatch_get_main_queue()) {
                stub()
            }
        case .Never:
            fatalError("Method called to stub request when stubbing is disabled.")
        }
        
        return cancellableToken
    }
}

/// Mark: Defaults

public class MoyaDefaults {
    
    // These functions are default mappings to MoyaProvider's properties: endpoints, requests, manager, etc.
    
    public final class func DefaultEndpointMapping(target: TargetType) -> Endpoint<TargetType> {
        let url = target.baseURL.URLByAppendingPathComponent(target.path).absoluteString
        return Endpoint(URL: url, sampleResponseClosure: {.NetworkResponse(200, target.sampleData)}, method: target.method, parameters: target.parameters)
    }
    
    public final class func DefaultRequestMapping(endpoint: Endpoint<TargetType>, closure: NSURLRequest -> Void) {
        return closure(endpoint.urlRequest)
    }
    
    public final class func DefaultAlamofireManager() -> Manager {
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.HTTPAdditionalHeaders = Manager.defaultHTTPHeaders
        
        let manager = Manager(configuration: configuration)
        manager.startRequestsImmediately = false
        return manager
    }
    
}

/// Mark: Stubbing

public extension MoyaDefaults {
    
    // Swift won't let us put the StubBehavior enum inside the provider class, so we'll
    // at least add some class functions to allow easy access to common stubbing closures.
    
    public final class func NeverStub(_: TargetType) -> Moya.StubBehavior {
        return .Never
    }
    
    public final class func ImmediatelyStub(_: TargetType) -> Moya.StubBehavior {
        return .Immediate
    }
    
    public final class func DelayedStub(seconds: NSTimeInterval)(_: TargetType) -> Moya.StubBehavior {
        return .Delayed(seconds: seconds)
    }
}

internal extension MoyaProvider {
    
    func sendRequest(target: TargetType, request: NSURLRequest, completion: Moya.Completion) -> CancellableToken {
        let alamoRequest = manager.request(request)
        let plugins = self.plugins
        
        // Give plugins the chance to alter the outgoing request
        plugins.forEach { $0.willSendRequest(alamoRequest, target: target) }
        
        // Perform the actual request
        alamoRequest.response { (_, response: NSHTTPURLResponse?, data: NSData?, error: NSError?) -> () in
            let result = convertResponseToResult(response, data: data, error: error)
            // Inform all plugins about the response
            plugins.forEach { $0.didReceiveResponse(result, target: target) }
            completion(result: result)
        }

        alamoRequest.resume()

        return CancellableToken(request: alamoRequest)
    }
    
    /// Creates a function which, when called, executes the appropriate stubbing behavior for the given parameters.
    internal final func createStubFunction(token: CancellableToken, forTarget target: TargetType, withCompletion completion: Moya.Completion, endpoint: Endpoint<TargetType>, plugins: [PluginType]) -> (() -> ()) {
        return {
            if (token.canceled) {
                let error = Moya.Error.Underlying(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil))
                plugins.forEach { $0.didReceiveResponse(.Failure(error), target: target) }
                completion(result: .Failure(error))
                return
            }
            
            switch endpoint.sampleResponseClosure() {
            case .NetworkResponse(let statusCode, let data):
                let response = Moya.Response(statusCode: statusCode, data: data, response: nil)
                plugins.forEach { $0.didReceiveResponse(.Success(response), target: target) }
                completion(result: .Success(response))
            case .NetworkError(let error):
                let error = Moya.Error.Underlying(error)
                plugins.forEach { $0.didReceiveResponse(.Failure(error), target: target) }
                completion(result: .Failure(error))
            }
        }
    }
    
    /// Notify all plugins that a stub is about to be performed. You must call this if overriding `stubRequest`.
    internal final func notifyPluginsOfImpendingStub(request: NSURLRequest, target: TargetType) {
        let alamoRequest = manager.request(request)
        plugins.forEach { $0.willSendRequest(alamoRequest, target: target) }
    }
}

internal func convertResponseToResult(response: NSHTTPURLResponse?, data: NSData?, error: NSError?) ->
    Result<Moya.Response, Moya.Error> {
    switch (response, data, error) {
    case let (.Some(response), .Some(data), .None):
        let response = Moya.Response(statusCode: response.statusCode, data: data, response: response)
        return .Success(response)
    case let (_, _, .Some(error)):
        let error = Moya.Error.Underlying(error)
        return .Failure(error)
    default:
        let error = Moya.Error.Underlying(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
        return .Failure(error)
    }
}

private struct CancellableWrapper: Cancellable {
    var innerCancellable: CancellableToken? = nil
    
    private var isCancelled = false
    
    func cancel() {
        innerCancellable?.cancel()
    }
}
