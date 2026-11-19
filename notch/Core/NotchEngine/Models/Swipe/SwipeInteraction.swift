//
//  SwipeInteraction.swift
//  notch
//
//  Created by Евгений Петрукович on 11/8/26.
//

import SwiftUI

enum SwipeInteraction: Equatable {
    case dismiss
    case restore
    case horizontalDismiss
    case horizontalExpand
    case simultaneousDismiss(verticalProgress: CGFloat, horizontalProgress: CGFloat)
    case combined(
        verticalDirection: VerticalSwipeDirection,
        verticalProgress: CGFloat,
        horizontalDirection: HorizontalSwipeDirection,
        horizontalProgress: CGFloat
    )
}
