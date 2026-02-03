//
//  ButtonStyleWhiteBgGrayBorder.swift
//  Salt
//

import SwiftUI

struct ButtonStyleWhiteBgGrayBorder: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white)
            .foregroundColor(Color.black)
            .font(Font.custom("OpenSans-Regular", size: 14))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color("GrayButtonBorderColor"), lineWidth: 1)
            )
    }
}

extension ButtonStyle where Self == ButtonStyleWhiteBgGrayBorder {
    internal static var whiteWithGrayBorder: ButtonStyleWhiteBgGrayBorder {
        ButtonStyleWhiteBgGrayBorder()
    }
}
