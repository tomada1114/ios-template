import Foundation
import MyAppCore
import Testing

@Suite("HTTPResponse")
struct HTTPResponseTests {
    static let url = URL(string: "https://example.invalid/items") ?? URL(fileURLWithPath: "/")

    @Test(arguments: [
        (199, false),
        (200, true),
        (299, true),
        (300, false),
    ])
    func `isSuccess holds for a 2xx status and nothing else`(statusCode: Int, expected: Bool) {
        let response = HTTPResponse(statusCode: statusCode, headers: [:], body: Data())
        #expect(response.isSuccess == expected)
    }

    @Test
    func `a response keeps the status, headers, and body it was made with`() {
        let body = Data("not here".utf8)
        let response = HTTPResponse(
            statusCode: 404,
            headers: ["Content-Type": "text/plain"],
            body: body,
        )
        #expect(response.statusCode == 404)
        #expect(response.headers == ["Content-Type": "text/plain"])
        #expect(response.body == body)
    }

    @Test
    func `a request defaults to a bodiless GET with no headers and a 30-second timeout`() {
        let request = HTTPRequest(url: Self.url)
        #expect(request.method == .get)
        #expect(request.url == Self.url)
        #expect(request.headers.isEmpty)
        #expect(request.body == nil)
        #expect(request.timeout == .seconds(30))
    }

    @Test
    func `a request keeps every field it was made with`() {
        let body = Data(#"{"title":"Milk"}"#.utf8)
        let request = HTTPRequest(
            method: .post,
            url: Self.url,
            headers: ["Content-Type": "application/json"],
            body: body,
            timeout: .milliseconds(1_500),
        )
        #expect(request.method == .post)
        #expect(request.headers == ["Content-Type": "application/json"])
        #expect(request.body == body)
        #expect(request.timeout == .milliseconds(1_500))
    }

    @Test(arguments: [
        (HTTPRequest.Method.delete, "DELETE"),
        (.get, "GET"),
        (.patch, "PATCH"),
        (.post, "POST"),
        (.put, "PUT"),
    ])
    func `a method's raw value is its HTTP token`(method: HTTPRequest.Method, token: String) {
        #expect(method.rawValue == token)
    }
}
