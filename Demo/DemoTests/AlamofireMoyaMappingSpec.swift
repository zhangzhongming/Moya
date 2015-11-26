import Quick
import Nimble
import Alamofire
@testable import Moya

final class AlamofireMoyaMappingSpec: QuickSpec {
    override func spec() {
        it("returns the correct alamofire method type") {
            expect(Moya.Method.GET.toAlamofire) == Alamofire.Method.GET
            expect(Moya.Method.POST.toAlamofire) == Alamofire.Method.POST
            expect(Moya.Method.PUT.toAlamofire) == Alamofire.Method.PUT
            expect(Moya.Method.DELETE.toAlamofire) == Alamofire.Method.DELETE
            expect(Moya.Method.OPTIONS.toAlamofire) == Alamofire.Method.OPTIONS
            expect(Moya.Method.HEAD.toAlamofire) == Alamofire.Method.HEAD
            expect(Moya.Method.PATCH.toAlamofire) == Alamofire.Method.PATCH
            expect(Moya.Method.TRACE.toAlamofire) == Alamofire.Method.TRACE
            expect(Moya.Method.CONNECT.toAlamofire) == Alamofire.Method.CONNECT
        }
        
        describe("translates parameter encoding to alamofire parameter encoding") {
            
            it("converts to alamofire URL encoding") {
                let alamofireEncoding = Moya.ParameterEncoding.URL.toAlamofire
                
                if case .URL = alamofireEncoding {
                    expect(true).to(beTrue())
                } else {
                    fail("Expected url encoding, got \(alamofireEncoding)")
                }
            }
            
            it("converts to alamofire JSON encoding") {
                let alamofireEncoding = Moya.ParameterEncoding.JSON.toAlamofire
                
                if case .JSON = alamofireEncoding {
                    expect(true).to(beTrue())
                } else {
                    fail("Expected json encoding, got \(alamofireEncoding)")
                }
            }
            
            it("converts to alamofire PropertyList encoding") {
                let alamofireEncoding = Moya.ParameterEncoding.PropertyList(NSPropertyListFormat.BinaryFormat_v1_0, 0).toAlamofire

                if case let .PropertyList(format, writeOptions) = alamofireEncoding {
                    expect(format) == NSPropertyListFormat.BinaryFormat_v1_0
                    expect(writeOptions) == 0
                } else {
                    fail("Expected property list encoding, got \(alamofireEncoding)")
                }
            }
            
            it("converts to alamofire Custom encoding") {
                var called: Bool = false
                
                let closure: (URLRequestConvertible, [String: AnyObject]?) -> (NSMutableURLRequest, NSError?) = { req, params in
                    called = true
                    return (NSMutableURLRequest(), nil)
                }
                let alamofireEncoding = Moya.ParameterEncoding.Custom(closure).toAlamofire
                
                if case let .Custom(closure) = alamofireEncoding {
                    let req = NSURLRequest()
                    closure(req, nil)
                    expect(called).to(beTrue())
                } else {
                    fail("Expected custom closure encoding, got \(alamofireEncoding)")
                }
            }
        }
    }
}
