//
//  NightscoutOverride.swift
//  
//
//  Created by Bill Gestrich on 11/13/22.
//

import Foundation

public struct NightscoutProfile: Codable {
    public let startDate: String
    public let loopSettings: NightscoutLoopSettings
}

public struct NightscoutLoopSettings: Codable {
    public let maximumBasalRatePerHour: Double
    public let overridePresets: [NightscoutOverridePreset]
}

public struct NightscoutOverridePreset: Codable {
    public let name: String
}
        
        