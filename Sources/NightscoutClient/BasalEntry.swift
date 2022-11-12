//
//  BasalEntry.swift
//  
//
//  Created by Bill Gestrich on 12/21/20.
//

import Foundation

public struct BasalEntry {
    public let date: Date
    public let duration: Float
    public let rate: Float
    public let amount: Float
}

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
