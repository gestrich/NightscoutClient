//
//  NightscoutService.swift
//  
//
//  Created by Bill Gestrich on 12/14/20.
//

import Foundation
import AsyncHTTPClient
import NIO //For ByteBuffer
import Crypto

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

//API Reference: https://github.com/nightscout/cgm-remote-monitor

public class NightscoutService {
    
    public let baseURL: URL
    let secret: String
    let nowDateProvider: () -> Date
    private let httpClient: AsyncHTTPClient.HTTPClient
    
    public init(baseURL: URL, secret: String, nowDateProvider: @escaping () -> Date){
        
        self.baseURL = baseURL
        self.secret = secret
        self.nowDateProvider = nowDateProvider
        
        let provider = AsyncHTTPClient.HTTPClient.EventLoopGroupProvider.createNew
        self.httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: provider)
    }
    
    public func syncShutdown() throws {
        try self.httpClient.syncShutdown()
    }
    
    //curl -L "<baseURL>/api/v1/entries.json" | jq
    // curl -L -g '<baseURL>/api/v1/entries/sgv.json?find[dateString][$gte]=2020-12-29' | jq
    public func getEGVs(startDate inputStartDate: Date, endDate inputEndDate: Date?) async throws -> [NightscoutEGV] {
        var currStartDate = inputStartDate
        let proposedEndDate = inputEndDate ?? nowDateProvider()
        var currEndDate = egvRequestEndDateFromProposedRange(startDate: currStartDate, endDate: proposedEndDate)
        var egvs = [NightscoutEGV]()
        while true {
            egvs += try await getEGVsNonOptimized(startDate: currStartDate, endDate: currEndDate)
            if currEndDate < proposedEndDate {
                currStartDate = currEndDate
                currEndDate = self.egvRequestEndDateFromProposedRange(startDate: currStartDate, endDate: proposedEndDate)
            } else {
                break
            }
        }
        
        return egvs
    }
    
    public func maxEGVRequestInterval() -> TimeInterval {
        let days = 7.0
        return days * 60.0 * 60.0 * 24.0
    }

    public func egvRequestEndDateFromProposedRange(startDate: Date, endDate _inputEndDate: Date) -> Date {
        let maxEndDate = startDate.addingTimeInterval(maxEGVRequestInterval()) //Could be past our endDate, so need to check this.
        return _inputEndDate < maxEndDate ? _inputEndDate : maxEndDate
    }
    
    private func getEGVsNonOptimized(startDate: Date, endDate: Date) async throws -> [NightscoutEGV] {
        
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NightscoutServiceError.URLFormationError
        }
        
        let startDateString = dateFormatter().string(from: startDate)
        let endDateString = dateFormatter().string(from: endDate)
        
        let path = "/api/v1/entries/sgv.json"
        let startQueryItem = URLQueryItem(name: "find[dateString][$gte]", value: startDateString)
        let endQueryItem = URLQueryItem(name: "find[dateString][$lte]", value: endDateString)
        let countQueryItem = URLQueryItem(name: "count", value: "100000")
        
        urlComponents.path = path
        urlComponents.queryItems = [startQueryItem, endQueryItem, countQueryItem]
        
        let url = urlComponents.url!
        
        var request = HTTPClientRequest(url: url.absoluteString)
        request.headers.add(name: "api-secret", value: sha1Secret())
        
        let response = try await httpClient.execute(request, timeout: .seconds(60))
        
        let data = try await Data(buffer: response.body.collect(upTo: .max))
        
        var entries = [NightscoutEntryJSON]()
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(self.dateFormatter())
            entries = try decoder.decode([NightscoutEntryJSON].self, from: data)
        } catch {
            print(error)
        }
            
        /*
            Device Types:
                "loop://iPhone"
                    I believe it is just from reading sugar via Bluetooth interecpts
                    This lacks the trend information.
                "share2"
                    I believe this comes from Dexcom credentials being input to Loop
                "CGMBLEKit Dexcom G6 21.0"
                    Haven't seen this one for a while -- not sure if still a factor
        */
        return entries
            .filter({$0.device != "CGMBLEKit Dexcom G6 21.0"})
            .map({$0.toEGV()})
            .filter({$0.value > 0})
    }
    
    //curl -L "<baseURL>/api/v1/treatments.json" | jq
    public func getTreatments(startDate: Date, endDate: Date?) async throws -> NightscoutTreatmentResult {
        
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NightscoutServiceError.URLFormationError
        }
        
        let endDate = endDate ?? nowDateProvider()
        
        let startDateString = dateFormatter().string(from: startDate)
        let endDateString = dateFormatter().string(from: endDate)
        
        let path = "/api/v1/treatments.json"
        let startQueryItem = URLQueryItem(name: "find[created_at][$gte]", value: startDateString)
        let endQueryItem = URLQueryItem(name: "find[created_at][$lte]", value: endDateString)
        
        //TODO: I may want more results back.
        let countQueryItem = URLQueryItem(name: "count", value: "1000")

        urlComponents.path = path
        urlComponents.queryItems = [startQueryItem, endQueryItem, countQueryItem]
        
        let url = urlComponents.url!
        
        var request = HTTPClientRequest(url: url.absoluteString)
        request.headers.add(name: "api-secret", value: sha1Secret())
        
        let response = try await httpClient.execute(request, timeout: .seconds(60))
        
        let data = try await Data(buffer: response.body.collect(upTo: .max))
        
        var treatments = [NightscoutTreatmentJSON]()
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(self.dateFormatter())
            treatments = try decoder.decode([NightscoutTreatmentJSON].self, from: data)
        } catch {
            print(error)
        }
        
        return NightscoutTreatmentResult.getTreatmentResult(jsonObjects: treatments)
    }
    
    //curl -L -g '<baseURL>/api/v1/devicestatus.json?find[created_at][$gte]=2021-05-01' | jq | less
    public func getDeviceStatuses(startDate: Date, endDate: Date?) async throws -> [NightscoutDeviceStatus] {
        
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NightscoutServiceError.URLFormationError
        }
        
        let endDate = endDate ?? nowDateProvider()
        
        let startDateString = dateFormatter().string(from: startDate)
        let endDateString = dateFormatter().string(from: endDate)
        
        let path = "/api/v1/devicestatus.json"
        let startQueryItem = URLQueryItem(name: "find[created_at][$gte]", value: startDateString)
        let endQueryItem = URLQueryItem(name: "find[created_at][$lte]", value: endDateString)
        let countQueryItem = URLQueryItem(name: "count", value: "100000")
        
        urlComponents.path = path
        urlComponents.queryItems = [startQueryItem, endQueryItem, countQueryItem]
        
        let url = urlComponents.url!
        
        var request = HTTPClientRequest(url: url.absoluteString)
        request.headers.add(name: "api-secret", value: sha1Secret())
        
        let response = try await httpClient.execute(request, timeout: .seconds(60))
        
        let data = try await Data(buffer: response.body.collect(upTo: .max))
        
        var deviceStatuses = [NightscoutDeviceStatus]()
        
        do {
            let decoder = self.jsonDecoder()
            deviceStatuses = try decoder.decode([NightscoutDeviceStatus].self, from: data)
        } catch {
            print(error)
        }
        
        return deviceStatuses
    }
    
    public func getBasalTreatments(startDate: Date, endDate: Date?) async throws -> [WGBasalEntry] {
        return try await self.getTreatments(startDate: startDate, endDate: endDate).basalEntries
    }
    
    public func getBolusTreatments(startDate: Date, endDate: Date?) async throws -> [WGBolusEntry] {
        return try await self.getTreatments(startDate: startDate, endDate: endDate).bolusEntries
    }
    
    public func getCarbTreatments(startDate: Date, endDate: Date?) async throws -> [WGCarbEntry] {
        return try await self.getTreatments(startDate: startDate, endDate: endDate).carbEntries
    }
    
    public func sha1Secret() -> String {
        var sha1 = Insecure.SHA1()
        let sha1Data = secret.data(using: .utf8)!
        sha1.update(data: sha1Data)
        let digest = sha1.finalize()
        return String(digest.description.split(separator: " ").last ?? "")
    }
    
    public func getProfiles() async throws -> [NightscoutProfile] {
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NightscoutServiceError.URLFormationError
        }

        let path = "/api/v1/profile.json"
        urlComponents.path = path
        
        let url = urlComponents.url!
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .GET
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "api-secret", value: sha1Secret())
        
        let response = try await httpClient.execute(request, timeout: .seconds(60))
        let data = try await Data(buffer: response.body.collect(upTo: .max))
            
        let decoder = self.jsonDecoder()
        return try decoder.decode([NightscoutProfile].self, from: data)
    }
    
    public func startOverride(overrideName: String, overrideDisplay: String, durationInMinutes: Int) async throws -> HTTPClientResponse {
        
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NightscoutServiceError.URLFormationError
        }

        let path = "/api/v2/notifications/loop"
        urlComponents.path = path
        
        let url = urlComponents.url!
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "api-secret", value: sha1Secret())

        let jsonDict: [String: String] = [
            "reason":overrideName,
            "reasonDisplay":overrideDisplay,
            "eventType":"Temporary Override",
            "duration":"\(durationInMinutes)",
            "notes":""
        ]
        
        let postData = try! JSONEncoder().encode(jsonDict)
        let postLength = "\(postData.count)"
        request.headers.add(name: "Content-Length", value: postLength)
        request.body = .bytes(ByteBuffer(data: postData))
        
        return try await httpClient.execute(request, timeout: .seconds(60))
    }
    
    
    public func cancelOverride() async throws -> HTTPClientResponse {
        
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NightscoutServiceError.URLFormationError
        }

        let path = "/api/v2/notifications/loop"
        urlComponents.path = path
        
        let url = urlComponents.url!
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "api-secret", value: sha1Secret())

        let jsonDict: [String: String] = [
            "eventType":"Temporary Override Cancel",
            "duration":"0"
        ]
        
        let postData = try! JSONEncoder().encode(jsonDict)
        let postLength = "\(postData.count)"
        request.headers.add(name: "Content-Length", value: postLength)
        request.body = .bytes(ByteBuffer(data: postData))
        
        return try await httpClient.execute(request, timeout: .seconds(60))
    }
    
    public func deliverBolus(amountInUnits: Double, otp: Int) async throws -> HTTPClientResponse {
        
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NightscoutServiceError.URLFormationError
        }

        let path = "/api/v2/notifications/loop"
        urlComponents.path = path
        
        let url = urlComponents.url!
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "api-secret", value: sha1Secret())

        let jsonDict: [String: String] = [
            "eventType":"Remote Bolus Entry",
            "remoteBolus":"\(amountInUnits)",
            "otp":"\(otp)"
        ]
        
        let postData = try! JSONEncoder().encode(jsonDict)
        let postLength = "\(postData.count)"
        request.headers.add(name: "Content-Length", value: postLength)
        request.body = .bytes(ByteBuffer(data: postData))
        
        return try await httpClient.execute(request, timeout: .seconds(60))
    }
    
    public func deliverCarbs(amountInGrams: Int, amountInHours: Float, otp: Int) async throws -> HTTPClientResponse {
        
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NightscoutServiceError.URLFormationError
        }

        let path = "/api/v2/notifications/loop"
        urlComponents.path = path
        
        let url = urlComponents.url!
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "api-secret", value: sha1Secret())

        let jsonDict: [String: String] = [
            "eventType":"Remote Carbs Entry",
            "remoteCarbs":"\(amountInGrams)",
            "remoteAbsorption":"\(amountInHours)",
            "otp":"\(otp)"
        ]
        
        let postData = try! JSONEncoder().encode(jsonDict)
        let postLength = "\(postData.count)"
        request.headers.add(name: "Content-Length", value: postLength)
        request.body = .bytes(ByteBuffer(data: postData))
        
        return try await httpClient.execute(request, timeout: .seconds(60))
    }

    func dateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }
    
    func secondaryDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }
    
    func jsonDecoder() -> JSONDecoder {
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            
            var date: Date? = nil
            if let tempDate = self.dateFormatter().date(from: dateStr) {
                date = tempDate
            } else if let tempDate = self.secondaryDateFormatter().date(from: dateStr) {
                date = tempDate
            }

            guard let date_ = date else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateStr)")
            }

            return date_
        })
        return decoder

    }
    
    
}

public struct NightscoutEntryJSON: Codable {
    
    public let _id: String
    public let sgv: Int
    public let dateString: Date //"2020-12-29T14:54:31.000Z",
    //This was a float but was sometimes returning a String
    //on 12-9-2021. Seems to be a Dexcom issue.
    //Supporting both types with AnyCodableValue
    public let trend: AnyCodableValue?
    public let direction: String?
    public let device: String
    public let type: String //Need to accept Int or String
    public let utcOffset: Int
    public let sysTime: Date
    public let mills: Int?
    
    /*
     {
       "_id": "5feb436be0d1aa28f0556ec5",
       "sgv": 119,
       "date": 1609253671000,
       "dateString": "2020-12-29T14:54:31.000Z",
       "trend": 3,
       "direction": "FortyFiveUp",
       "device": "share2",
       "type": "sgv",
       "utcOffset": 0,
       "sysTime": "2020-12-29T14:54:31.000Z",
       "mills": 1609253671000
     }
     */
    
    public func toEGV() -> NightscoutEGV {
        var floatTrend: Float = 0
        if let typedTrend = trend?.floatValue {
            floatTrend = typedTrend
        } else if let stringTrend = trend?.stringValue {
            
            switch stringTrend {
            case "DoubleDown":
                floatTrend = 7
            case "FortyFiveDown":
                floatTrend = 6
            case "SingleDown":
                floatTrend = 5
                
            case "Flat":
                floatTrend = 4
                
            case "SingleUp":
                floatTrend = 3
            case "FortyFiveUp":
                floatTrend = 2
            case "DoubleUp":
                floatTrend = 1
            default:
                floatTrend = 4
            }
        }
        return NightscoutEGV(value: sgv, systemTime: sysTime, displayTime: sysTime, realtimeValue: nil, smoothedValue: nil, trendRate: floatTrend, trendDescription: "")
    }
    
    
    public enum AnyCodableValue: Codable {
        case integer(Int)
        case string(String)
        case float(Float)
        case double(Double)
        case boolean(Bool)
        case null
        
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            if let x = try? container.decode(Int.self) {
                self = .integer(x)
                return
            }
            
            if let x = try? container.decode(String.self) {
                self = .string(x)
                return
            }
            
            if let x = try? container.decode(Float.self) {
                self = .float(x)
                return
            }
            
            if let x = try? container.decode(Double.self) {
                self = .double(x)
                return
            }
            
            if let x = try? container.decode(Bool.self) {
                self = .boolean(x)
                return
            }
            
            if let x = try? container.decode(String.self) {
                     self = .string(x)
                     return
                 }
            
            if container.decodeNil() {
                self = .string("")
                return
            }
            
            throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type"))
        }
        
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .integer(let x):
                try container.encode(x)
            case .string(let x):
                try container.encode(x)
            case .float(let x):
                try container.encode(x)
            case .double(let x):
                try container.encode(x)
            case .boolean(let x):
                try container.encode(x)
            case .null:
                try container.encode(self)
                break
            }
        }
        
        //Get safe Values
        public var stringValue: String {
            switch self {
            case .string(let s):
                return s
            case .integer(let s):
                return "\(s)"
            case .double(let s):
                return "\(s)"
            case .float(let s):
                return "\(s)"
            default:
                return ""
            }
        }
        
        public var intValue: Int {
            switch self {
            case .integer(let s):
                return s
            case .string(let s):
                return (Int(s) ?? 0)
            case .float(let s):
                return Int(s)
            case .null:
                return 0
            default:
                return 0
            }
        }
        
        public var floatValue: Float {
            switch self {
            case .float(let s):
                return s
            case .integer(let s):
                return Float(s)
            case .string(let s):
                return (Float(s) ?? 0)
            default:
                return 0
            }
        }
        
        public var doubleValue: Double {
            switch self {
            case .double(let s):
                return s
            case .string(let s):
                return (Double(s) ?? 0.0)
            case .integer(let s):
                return (Double(s))
            case .float(let s):
                return (Double(s))
            default:
                return 0.0
            }
        }
        
        public var booleanValue: Bool {
            switch self {
            case .boolean(let s):
                return s
            case .integer(let s):
                return s == 1
            case .string(let s):
                let bool = (Int(s) ?? 0) == 1
                return bool
            default:
                return false
            }
        }

        
    }
}

public struct NightscoutTreatmentJSON: Codable {
    public let _id: String
    
    let timestamp: String?//"2020-12-14T04:15:02Z"
    let amount: Float? //0
    let rate: Float?//0
    let eventType: String// "Temp Basal",
    let absolute: Float?//0,
    let created_at: Date //"2020-12-14T04:15:02.000Z"
    let enteredBy: String?//"loop://iPhone",
    
    
    let temp: String?//"absolute",
    let duration: Float?//19.953699616591134,
    let utcOffset: Int//0,
    let mills: Int?//1607919302000,
    let carbs: Int?//null,
    let insulin: Float?//null
    

    func basalEntry() -> WGBasalEntry? {
        guard eventType == "Temp Basal" else {
            return nil
        }
        
        return WGBasalEntry(date: created_at, duration: duration ?? 0.0, rate: rate ?? 0.0, amount: amount ?? 0.0)
        
        
    }
    
    func bolusEntry() -> WGBolusEntry? {
        guard eventType == "Correction Bolus" else {
            return nil
        }
        
        guard let insulin = insulin else {
            return nil
        }
        
        return WGBolusEntry(date: created_at, amount: insulin)
    }
    
    func carbEntry() -> WGCarbEntry? {
        
        //guard eventType == "Meal Bolus" else { //Loop master seems to give a different value than dev
        guard eventType == "Carb Correction" else { //dev
            return nil
        }
        
        //TODO: Not sure about the time.
        return WGCarbEntry(date: created_at, amount: carbs ?? 0)
    }
    
}

public struct NightscoutTreatmentResult {
    
    public let basalEntries: [WGBasalEntry]
    public let bolusEntries: [WGBolusEntry]
    public let carbEntries: [WGCarbEntry]

    static func getTreatmentResult(jsonObjects: [NightscoutTreatmentJSON]) -> NightscoutTreatmentResult {
        var basalEntries = [WGBasalEntry]()
        var bolusEntries = [WGBolusEntry]()
        var carbEntries = [WGCarbEntry]()
        
        for jsonObj in jsonObjects {

            if let basalEntry = jsonObj.basalEntry() {
                basalEntries.append(basalEntry)
            } else if let bolusEntry = jsonObj.bolusEntry() {
                bolusEntries.append(bolusEntry)
            } else if let carbEntry = jsonObj.carbEntry() {
                carbEntries.append(carbEntry)
            }
            
        }
        
        return NightscoutTreatmentResult(basalEntries: basalEntries, bolusEntries: bolusEntries, carbEntries: carbEntries)
    }
}

public struct NightscoutDeviceStatus: Codable {
    
    public let _id: String
    public let created_at: Date
    public let loop: NightscoutLoopStatus?
    public let pump: NightscoutPumpStatus?
    public let uploader: NightscoutUploaderStatus?
    public let override: NightscoutOverride?
    
}

public struct NightscoutPumpStatus: Codable {
    public let clock: Date
    public let reservoir: Float?
    public let suspended: Bool
    public let pumpID: String
    
    public func getValidReservoir(pumpChangeDate: Date) -> Float? {
        guard pumpChangeDate <= clock else {
            assert(false, "Undefined - passing pump change date after this one")
            //
            return nil
        }
        
        guard let reservoir = reservoir else {
            return nil
        }
        
        if reservoir < 50 && clock.timeIntervalSince(pumpChangeDate) < 60 * 60 {
            //Pump values sometimes invalid right after pump change so we ignore them
            return 50
        }
        
        return reservoir
    }
}


public struct NightscoutLoopStatus: Codable {
    public let timestamp: Date
    public let name: String
    public let version: String
    public let predicted: LoopPredictedGlucose?
    public let recommendedBolus: Float?
}

public struct NightscoutUploaderStatus: Codable {
    public let timestamp: Date
    public let battery: Int
    public let name: String
}

public struct NightscoutOverride: Codable {
    public let name: String?
    public let timestamp: Date
    public let active: Bool
    public let multiplier: Float?
    public let currentCorrectionRange: NightscoutCorrectionRange?
}

public struct NightscoutCorrectionRange: Codable {
    public let minValue: Int
    public let maxValue: Int
}

public struct LoopPredictedGlucose: Codable {
    public let values: [Float]?
}


/*
 Carb Entry:
 
 Time seems to be time of EATING, not input time.
 
 - _id : "5fd7f77e8df99cafb2be144b"
 - timestamp : "2020-12-14T23:50:17Z"
 - amount : nil
 - rate : nil
 - eventType : "Meal Bolus"
 - absolute : nil
 - created_at : "2020-12-14T23:50:17.000Z"
 - enteredBy : "loop://iPhone"
 - temp : nil
 - duration : nil
 - utcOffset : 0
 - mills : 1607989817000
 ▿ carbs : Optional<Int>
 - some : 125
 - insulin : nil
 */

/*
 Bolus Entry suggested with carb entry
 
 See "insulin" for amount.
 
 - _id : "5fd7f7828df99cafb2be1686"
 - timestamp : "2020-12-14T23:38:40Z"
 - amount : nil
 - rate : nil
 - eventType : "Correction Bolus"
 - absolute : nil
 - created_at : "2020-12-14T23:38:40.000Z"
 - enteredBy : "loop://iPhone"
 - temp : nil
 ▿ duration : Optional<Float>
 - some : 2.3333333
 - utcOffset : 0
 - mills : 1607989120000
 - carbs : nil
 ▿ insulin : Optional<Float>
 - some : 3.5
 */

/*
 Temp Basal done by Loop
 
 ▿ 2 : NightscoutTreatment
 - _id : "5fd7f1fb8df99cafb2bb6048"
 - timestamp : "2020-12-14T23:15:07Z"
 - amount : nil
 ▿ rate : Optional<Float>
 - some : 0.0
 - eventType : "Temp Basal"
 ▿ absolute : Optional<Float>
 - some : 0.0
 - created_at : "2020-12-14T23:15:07.000Z"
 - enteredBy : "loop://iPhone"
 ▿ temp : Optional<String>
 - some : "absolute"
 ▿ duration : Optional<Float>
 - some : 30.0
 - utcOffset : 0
 - mills : 1607987707000
 - carbs : nil
 - insulin : nil
 */

/*
 Auto-Bolus
 
 - _id : "5fd7eaee8df99cafb2b7f052"
 - timestamp : "2020-12-14T22:45:00Z"
 - amount : nil
 - rate : nil
 - eventType : "Correction Bolus"
 - absolute : nil
 - created_at : "2020-12-14T22:45:00.000Z"
 - enteredBy : "loop://iPhone"
 - temp : nil
 ▿ duration : Optional<Float>
 - some : 0.033333335
 - utcOffset : 0
 - mills : 1607985900000
 - carbs : nil
 ▿ insulin : Optional<Float>
 - some : 0.05
 */

extension URLRequest {
    public func cURL(pretty: Bool = false) -> String {
        let newLine = pretty ? "\\\n" : ""
        let method = (pretty ? "--request " : "-X ") + "\(self.httpMethod ?? "GET") \(newLine)"
        let url: String = (pretty ? "--url " : "") + "\'\(self.url?.absoluteString ?? "")\' \(newLine)"
        
        var cURL = "curl "
        var header = ""
        var data: String = ""
        
        if let httpHeaders = self.allHTTPHeaderFields, httpHeaders.keys.count > 0 {
            for (key,value) in httpHeaders {
                header += (pretty ? "--header " : "-H ") + "\'\(key): \(value)\' \(newLine)"
            }
        }
        
        if let bodyData = self.httpBody, let bodyString = String(data: bodyData, encoding: .utf8),  !bodyString.isEmpty {
            data = "--data '\(bodyString)'"
        }
        
        cURL += method + url + header + data
        
        return cURL
    }
}

enum NightscoutServiceError: Error {
    case URLFormationError
}
