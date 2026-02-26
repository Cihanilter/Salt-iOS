//
//  SetNewPasswordView.swift
//  Salt
//

import SwiftUI

struct SetNewPasswordView: View {
    @ObservedObject var viewModel: SetNewPasswordViewModel
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            VStack {
                GeometryReader { geo in
                    ScrollView(.vertical) {
                        VStack(alignment: .center, spacing: 20) {
                            // Close button
                            HStack {
                                Spacer()
                                Button(action: {
                                    onComplete()
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(Color("GrayText"))
                                        .font(.system(size: 18, weight: .medium))
                                        .padding(8)
                                }
                            }
                            .padding(.horizontal, geo.size.width * 0.12 / 2)
                            .padding(.top, 60)

                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Set New Password")
                                        .foregroundColor(Color.black)
                                        .font(Font.custom("OpenSans-Regular", size: 16))

                                    Text("Enter your new password below. Make sure it's at least 10 characters with numbers and special characters.")
                                        .foregroundColor(Color("GrayText"))
                                        .font(Font.custom("OpenSans-Regular", size: 14))
                                        .lineSpacing(4)
                                        .padding(.top, 12)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, geo.size.width * 0.12 / 2)
                            .padding(.top, 20)

                            GenericInputView(properties: $viewModel.password)
                                .padding(.horizontal, geo.size.width * 0.12 / 2)
                                .padding(.top, 36)

                            GenericInputView(properties: $viewModel.confirmPassword)
                                .padding(.horizontal, geo.size.width * 0.12 / 2)
                                .padding(.top, 16)

                            GenericButton(textLabel: "Update Password", action: {
                                Task {
                                    await viewModel.updatePassword()
                                }
                            }, type: .orange,
                                          frameWidth: geo.size.width - (geo.size.width * 0.12 / 2) * 2,
                                          frameHeight: 48)
                            .disabled(viewModel.isLoading)
                            .padding(.horizontal, geo.size.width * 0.12 / 2)
                            .padding(.top, 24)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            // Loading overlay
            if viewModel.isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text("Password Update"),
                message: Text(viewModel.alertMessage ?? ""),
                dismissButton: .default(Text("OK")) {
                    // If update was successful, close the sheet
                    if viewModel.showSuccessMessage {
                        onComplete()
                    }
                }
            )
        }
        .background(Color.white)
    }
}

#Preview {
    SetNewPasswordView(viewModel: .init(), onComplete: {})
}
