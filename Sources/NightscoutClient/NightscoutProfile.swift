//
//  NightscoutOverride.swift
//  
//
//  Created by Bill Gestrich on 11/13/22.
//

import Foundation

public struct NightscoutProfile: Codable {
    public let startDate: String
    public let loopSettings: NightscoutLoopSettings?
    public let store: NightscoutLoopStore?
}

public struct NightscoutLoopSettings: Codable {
    public let maximumBasalRatePerHour: Double
    public let overridePresets: [NightscoutOverridePreset]
    public let scheduleOverride: NightscoutOverridePreset?
}

public struct NightscoutLoopStore: Codable {
    public let Default: NightscoutLoopDefaultStore
}

public struct NightscoutLoopDefaultStore: Codable {
    public let basal: [NightscoutLoopStoreBasal]
}

public struct NightscoutLoopStoreBasal: Codable {
    public let timeAsSeconds: Int
    public let value: Double
}

public struct NightscoutOverridePreset: Codable {
    public let name: String
    public let symbol: String
    public let duration: Int //in seconds
    
    public var durationInSeconds: Int {
        return duration
    }
    
    public var durationInMinutes: Int {
        return duration / 60
    }
}
        
        
