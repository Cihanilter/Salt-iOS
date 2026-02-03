//
//  SwipeBackGesture.swift
//  Salt
//
//  Re-enables iOS swipe-back gesture when navigation bar is hidden
//

import SwiftUI
import UIKit

// MARK: - UINavigationController Extension

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        // Re-enable swipe back gesture even when nav bar is hidden
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only enable if there's more than one view controller in the stack
        return viewControllers.count > 1
    }
}
