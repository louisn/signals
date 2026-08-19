import XCTest
@testable import SignalKit

final class TrackerTagClassifierTests: XCTestCase {
    private func classify(
        manufacturerData: Data? = nil,
        serviceUUIDs: [String] = [],
        serviceData: [String: Data] = [:]
    ) -> TrackerTagType? {
        TrackerTagClassifier.classify(.init(
            manufacturerData: manufacturerData,
            serviceUUIDs: serviceUUIDs,
            serviceData: serviceData
        ))
    }

    func testSeparatedAppleFindMyFrameIsATag() {
        // 0x12 with the long "separated" length byte (0x19) = unattended tracker.
        XCTAssertEqual(classify(manufacturerData: Data([0x4C, 0x00, 0x12, 0x19, 0x10])), .appleFindMy)
    }

    func testNearbyAppleFindMyFrameIsNotATag() {
        // 0x12 with the short "nearby" length byte (0x02): broadcast by every
        // Apple device near its owner, not a tracker -- must not be flagged.
        XCTAssertNil(classify(manufacturerData: Data([0x4C, 0x00, 0x12, 0x02, 0x00])))
    }

    func testOtherAppleAdvertisementIsNotATag() {
        // 0x07 = AirPods proximity pairing, not offline finding.
        XCTAssertNil(classify(manufacturerData: Data([0x4C, 0x00, 0x07, 0x19])))
    }

    func testNonAppleManufacturerIsNotATag() {
        XCTAssertNil(classify(manufacturerData: Data([0x75, 0x00, 0x12, 0x19])))
    }

    func testTruncatedManufacturerDataIsNotATag() {
        XCTAssertNil(classify(manufacturerData: Data([0x4C, 0x00])))
    }

    func testServiceUUIDTags() {
        XCTAssertEqual(classify(serviceUUIDs: ["FEED"]), .tile)
        XCTAssertEqual(classify(serviceUUIDs: ["FD5A"]), .samsungSmartTag)
        XCTAssertEqual(classify(serviceUUIDs: ["FE33"]), .chipolo)
        XCTAssertEqual(classify(serviceUUIDs: ["fd5a"]), .samsungSmartTag)
    }

    func testUnknownServiceUUIDIsNotATag() {
        XCTAssertNil(classify(serviceUUIDs: ["180F", "180A"]))
    }

    func testGoogleFindMyDeviceFrame() {
        XCTAssertEqual(classify(serviceData: ["FEAA": Data([0x40, 0xAB, 0xCD])]), .googleFindMyDevice)
    }

    func testClassicEddystoneIsNotATag() {
        XCTAssertNil(classify(serviceData: ["FEAA": Data([0x00, 0xAB, 0xCD])]))
    }

    func testEmptyAdvertisementIsNotATag() {
        XCTAssertNil(classify())
    }

    func testTagTypeRoundTripsThroughPayloadEncoding() throws {
        let payload = BLEAdvertisementPayload(
            peripheralUUID: UUID().uuidString,
            name: nil,
            rssi: -60,
            serviceUUIDs: [],
            txPower: nil,
            tagType: TrackerTagType.appleFindMy.rawValue
        )
        let data = try SignalPayload.bleAdvertisement(payload).encodedData()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["tag_type"] as? String, "apple_find_my")
    }
}
