//
//  GenericInputView.swift
//  Salt
//

import SwiftUI

struct GenericInputView: View {
    @State private var istextFieldIsActive: Bool = false
    @FocusState private var defaultFocus: Int?

    @Binding var properties: GenericInputProperties
    var focusField: FocusState<Int?>.Binding?
    var fieldIndex: Int?

    private var effectiveFocusField: FocusState<Int?>.Binding {
        focusField ?? $defaultFocus
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(properties.title)
                    .font(Font.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color.black)
                Spacer()
            }

            HStack(alignment: .top) {
                if properties.isSecure {
                    SecureField(text: $properties.inputText,  label: {
                        Text(properties.placeholder ?? "")
                            .foregroundColor(textColor)
                            .font(Font.custom("OpenSans-Regular", size: 14))
                            .padding(.leading, 16)
                    })
                        .font(Font.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.black)
                        .keyboardType(properties.keyboardType ?? .default)
                        .submitLabel(properties.submitLabel ?? .done)
                        .focused(effectiveFocusField, equals: fieldIndex)
                        .onSubmit {
                            properties.onSubmit?()
                        }
                } else {
                    TextField(text: $properties.inputText, axis: .horizontal, label: {
                        Text(properties.placeholder ?? "")
                            .foregroundColor(textColor)
                            .font(Font.custom("OpenSans-Regular", size: 14))
                            .padding(.leading, 16)
                    })
                    .font(Font.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.black)
                    .keyboardType(properties.keyboardType ?? .default)
                    .submitLabel(properties.submitLabel ?? .done)
                    .focused(effectiveFocusField, equals: fieldIndex)
                    .onSubmit {
                        properties.onSubmit?()
                    }
                }
                Spacer()
                if let actionInfo = properties.actionInfo, let image = actionInfo.image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
            }
            
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color("GrayGenericInputBg"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: istextFieldIsActive ? 0 : 0)
            )
            .frame(height: 48)
            .onTapGesture {
                properties.actionInfo?.tapAction()
            }

            if let error = properties.errorText {
                HStack(spacing: 8) {
//                    Image("warning")
//                        .frame(width: 24, height: 24)
                    Text(error)
                        .font(Font.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color.red)
                    Spacer()
                }
            }
        }
    }

    var hasInputText: Bool {
        return !properties.inputText.isEmpty
    }

    var hasAction: Bool {
        return properties.actionInfo != nil
    }

    var borderColor: Color {
        if let _ = properties.errorText {
            return Color.red
        }
//        else if istextFieldIsActive {
//            return .blueButtonBackground
//        }
        else {
            return .clear
        }
    }
    
    var textColor: Color {
        // Placeholder should always be gray, regardless of error state
        return Color("GrayText")
    }
}

struct GenericInputView_Previews: PreviewProvider {
    static var previews: some View {
        GenericInputView(
            properties: .constant(GenericInputProperties(
                title: "First Name",
                placeholder: "",
                isSecure: false,
                actionInfo: nil,
                keyboardType: nil,
                errorText: "This is error message",
                submitLabel: .done,
                onSubmit: nil
            ))
        )
    }
}
