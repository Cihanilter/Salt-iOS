//
//  ActivityView.swift
//  Salt
//
//  System share sheet, for content that's only ready after an async step
//  (ShareLink needs its item up front)
//

import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    /// Called when the sheet closes: what was picked (e.g. Messages, Copy), and whether it went through
    var onComplete: ((UIActivity.ActivityType?, Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            onComplete?(activityType, completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
