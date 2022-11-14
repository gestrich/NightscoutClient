import XCTest
@testable import NightscoutClient

final class NightscoutClientTests: XCTestCase {
    
    let service = NightscoutService(baseURL: URL(string: "https://gestrich-sugar-test.herokuapp.com")!, secret: "RS89JLJ9A6YR", referenceDate: Date())
    
    func shutdown() throws {
        try service.syncShutdown()
    }
    
    func testExample() async throws {

//        let profile = try await service.getProfiles()
//        print(profile)
//        try await service.deliverBolus(amountInUnits: 1.0, otp: 12345)
        try await service.deliverCarbs(amountInGrams: 2, amountInHours: 3, otp: 12345)
        try service.syncShutdown()
    }
}
