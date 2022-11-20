//
//  WGBolusEntry.swift
//  
//
//  Created by Bill Gestrich on 12/21/20.
//

import Foundation

public struct WGBolusEntry {
    public let date: Date
    public let amount: Float
}


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
