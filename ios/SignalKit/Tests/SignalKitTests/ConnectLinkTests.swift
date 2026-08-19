import XCTest
@testable import SignalKit

final class ConnectLinkTests: XCTestCase {
    private let deviceID = "A1B2C3D4-1111-2222-3333-444455556666"

    private func url(_ s: String) -> URL { URL(string: s)! }

    func testParsesValidLink() {
        let link = ConnectLink.parse(url(
            "signals://connect?base=https%3A%2F%2Fsignals-api-dev.fly.dev&device_id=\(deviceID)&key=abc123"
        ))
        XCTAssertEqual(link?.base, URL(string: "https://signals-api-dev.fly.dev"))
        XCTAssertEqual(link?.deviceID, UUID(uuidString: deviceID))
        XCTAssertEqual(link?.apiKey, "abc123")
    }

    func testWrongSchemeReturnsNil() {
        XCTAssertNil(ConnectLink.parse(url("https://connect?base=https%3A%2F%2Fx.com&device_id=\(deviceID)&key=abc")))
    }

    func testWrongHostReturnsNil() {
        XCTAssertNil(ConnectLink.parse(url("signals://other?base=https%3A%2F%2Fx.com&device_id=\(deviceID)&key=abc")))
    }

    func testMissingKeyReturnsNil() {
        XCTAssertNil(ConnectLink.parse(url("signals://connect?base=https%3A%2F%2Fx.com&device_id=\(deviceID)")))
    }

    func testEmptyKeyReturnsNil() {
        XCTAssertNil(ConnectLink.parse(url("signals://connect?base=https%3A%2F%2Fx.com&device_id=\(deviceID)&key=")))
    }

    func testInvalidDeviceIDReturnsNil() {
        XCTAssertNil(ConnectLink.parse(url("signals://connect?base=https%3A%2F%2Fx.com&device_id=not-a-uuid&key=abc")))
    }

    func testMissingBaseReturnsNil() {
        XCTAssertNil(ConnectLink.parse(url("signals://connect?device_id=\(deviceID)&key=abc")))
    }

    func testCustomBaseURLIsPreserved() {
        let link = ConnectLink.parse(url(
            "signals://connect?base=http%3A%2F%2F10.0.0.5%3A8080&device_id=\(deviceID)&key=k"
        ))
        XCTAssertEqual(link?.base, URL(string: "http://10.0.0.5:8080"))
    }
}
