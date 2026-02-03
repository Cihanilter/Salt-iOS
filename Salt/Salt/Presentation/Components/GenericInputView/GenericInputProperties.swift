//
//  GenericInputProperties.swift
//  Salt
//

import Foundation
import UIKit
import SwiftUI

struct GenericInputProperties {
	struct ActionInfo {
		let image: UIImage?
		let tapAction: () -> Void
	}

	let title: String
    let placeholder: String?
    var isSecure: Bool
	let actionInfo: ActionInfo?
	let keyboardType: UIKeyboardType?
	var errorText: String?
    let submitLabel: SubmitLabel?
    var onSubmit: (() -> Void)?

	var inputText: String = ""

    static var initial: GenericInputProperties {
        .init(title: "", placeholder: nil, isSecure: false, actionInfo: nil, keyboardType: nil, errorText: nil, submitLabel: nil, onSubmit: nil)
    }
}
