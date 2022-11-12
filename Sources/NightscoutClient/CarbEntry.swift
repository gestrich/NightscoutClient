//
//  CarbEntry.swift
//  
//
//  Created by Bill Gestrich on 12/21/20.
//

import Foundation

public struct CarbEntry {
    public let date: Date
    public let amount: Int
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
