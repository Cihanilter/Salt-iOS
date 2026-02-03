//
//  ForgotPasswordView.swift
//  Salt
//

import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject var viewModel: ForgotPasswordViewModel
    @ObservedObject var router: AuthRouter

    var body: some View {
        ZStack {
            VStack {
                GeometryReader { geo in
                    ScrollView(.vertical) {
                    VStack(alignment: .center, spacing: 20) {
                        // Back button
                        Button(action: {
                            router.navigateBack()
                        }) {
                            HStack{
                                HStack(spacing: 8) {
                                    Image("backIcon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(
                                            width: 20,
                                            height: 20)
                                    
                                    Text("Back to Sign In")
                                        .foregroundColor(Color("GrayText"))
                                        .font(Font.custom("OpenSans-Regular", size: 14))
                                }
                                Spacer()
                            }
                        }
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 120)

                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Forgot Password?")
                                    .foregroundColor(Color.black)
                                    .font(Font.custom("OpenSans-Regular", size: 16))
                                
                                Text("No worries! Enter your email address and we'll send you a link to reset your password.")
                                    .foregroundColor(Color("GrayText"))
                                    .font(Font.custom("OpenSans-Regular", size: 14))
                                    .lineSpacing(4)
                                    .padding(.top, 12)
                                
                            }
                            Spacer()
                        }
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 20)

                        GenericInputView(properties: $viewModel.email)
                            .padding(.horizontal, geo.size.width * 0.12 / 2)
                            .padding(.top, 36)

                        GenericButton(textLabel: "Send Reset Link", action: {
                            Task {
                                await viewModel.resetPassword()
                            }
                        }, type: .orange,
                                      frameWidth: geo.size.width - (geo.size.width * 0.12 / 2) * 2,
                                      frameHeight: 48)
                        .disabled(viewModel.isLoading)
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 24)

                        HStack(spacing: 3) {
                            Text("Remember your password?")
                                .foregroundColor(Color("GrayText"))
                                .font(Font.custom("OpenSans-Regular", size: 14))

                            Text("Sign In")
                                .foregroundColor(Color("Orange"))
                                .font(Font.custom("OpenSans-Regular", size: 16))
                        }
                     
                        .padding(.top, 32)
                        .onTapGesture {
                            router.navigateBack()
                        }

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
            title: Text("Reset Password"),
            message: Text(viewModel.alertMessage ?? ""),
            dismissButton: .default(Text("OK")) {
                // If reset was successful, navigate back to login
                if viewModel.showSuccessMessage {
                    router.navigateBack()
                }
            }
        )
    }
    .navigationBarHidden(true)
    }
}

#Preview {
    ForgotPasswordView(viewModel: .init(), router: .init())
}
