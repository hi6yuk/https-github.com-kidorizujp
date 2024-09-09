//
//  Item.swift
//  kidorizu.jp
//
//  Created by 本田宏幸 on 2024/09/09.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
