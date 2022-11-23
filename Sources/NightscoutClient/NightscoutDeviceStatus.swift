//
//  NightscoutDeviceStatus.swift
//  
//
//  Created by Bill Gestrich on 11/23/22.
//

import Foundation

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
    public let cob: WGLoopCOB?
    public let iob: WGLoopIOB?
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
    public let startDate: Date
    public let values: [Float]?
}

public struct WGLoopCOB: Codable {
    public let timestamp: Date
    public let cob: Float
}

public struct WGLoopIOB: Codable {
    public let timestamp: Date
    public let iob: Float
}
