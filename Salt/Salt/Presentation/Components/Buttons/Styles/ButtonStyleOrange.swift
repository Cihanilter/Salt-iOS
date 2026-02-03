//
//  ButtonStyleOrange.swift
//  Salt
//

import SwiftUI

struct ButtonStyleOrange: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color("Orange"))
            .foregroundColor(Color.white)
            .font(Font.custom("OpenSans-Regular", size: 14))
            .cornerRadius(16)
    }
}

extension ButtonStyle where Self == ButtonStyleOrange {
    internal static var orange: ButtonStyleOrange {
        ButtonStyleOrange()
    }
}
