//
//  GenericButton.swift
//  Salt
//

import SwiftUI
import UIKit

struct GenericButton: View {
    var textLabel: String
    var action: () -> Void
    var type: GenericButtonType
    var frameWidth: CGFloat?
    var frameHeight: CGFloat?
    var image: UIImage?
    
    init(
        textLabel: String,
        action: @escaping () -> Void,
        type: GenericButtonType,
        frameWidth: CGFloat? = nil,
        frameHeight: CGFloat? = nil,
        image: UIImage? = nil
    ) {
        self.textLabel = textLabel
        self.action = action
        self.type = type
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.image = image
    }
    
    var body: some View {
        switch type {
        case .orange:
            button
                .buttonStyle(.orange)
        case .whiteWithGrayBorder:
            button
                .buttonStyle(.whiteWithGrayBorder)
//        case .greenRadius6:
//            button
//                .buttonStyle(.greenRadius6)
//        case .whiteWithBlue:
//            button
//                .buttonStyle(.whiteWithBlue)
//        case .coral:
//            button
//                .buttonStyle(.coral)
//        case .radius17TransparentWithBorder:
//            button
//                .buttonStyle(.radius17TransparentWithBorder)
//        case .radius6TransparentWithBorder:
//            button
//                .buttonStyle(.radius6TransparentWithBorder)
            
        }
    }
    
    @ViewBuilder private var button: some View {
        Button(action: {
            action()
        }, label: {
            if let image {
                if let frameWidth = self.frameWidth {
                    imageWithLabel(image)
                        .frame(width: frameWidth, height: frameHeight ?? 93.61, alignment: .center)
                } else {
                    imageWithLabel(image)
                        .frame(maxWidth: .infinity)
                        .frame(height: frameHeight ?? 93.61)
                }
                
                
            } else {
                if let frameWidth = self.frameWidth {
                    label
                        .frame(width: frameWidth, height: frameHeight ?? 93.61, alignment: .center)
                } else {
                    label
                        .frame(maxWidth: .infinity)
                        .frame(height: frameHeight ?? 93.61)
                }
                
            }
        })
    }
    
    @ViewBuilder private func imageWithLabel(_ image: UIImage) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            
            label
        }
    }
    
    @ViewBuilder private var label: some View {
        Text(textLabel)
    }
    
    enum GenericButtonType: String {
        case orange
        case whiteWithGrayBorder
//        case greenRadius6
//        case coral
//        case radius17TransparentWithBorder
//        case whiteWithBlue
//        case radius6TransparentWithBorder
    }
}

struct GenericButtonPreviews: PreviewProvider {
    static var previews: some View {
        GenericButton(
            textLabel: "Search Again",
            action: { print("smth") },
            type: .orange,
            frameWidth: 330,
            frameHeight: 76,
            image: nil
        )
    }
}
