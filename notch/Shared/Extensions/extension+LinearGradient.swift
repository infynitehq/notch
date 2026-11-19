//
//  extension+LinearGradient.swift
//  notch
//
//  Created by Евгений Петрукович on 7/16/26.
//

import SwiftUI

extension LinearGradient {
    static var orangeGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .yellow, .orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
