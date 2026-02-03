//
//  SignUpView.swift
//  Salt
//

import SwiftUI

struct SignUpView: View {
    @ObservedObject var viewModel: SignUpViewModel
    @ObservedObject var router: AuthRouter

    var body: some View {
        ZStack {
            VStack {
                GeometryReader { geo in
                    ScrollView(.vertical) {
                    VStack(alignment: .center) {
                        Spacer()
                        Image("small_icon")
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: 64,
                                height: 64)
                            .padding(.top, 12)

                        Text("Create Account")
                            .foregroundColor(Color.black)
                            .font(Font.custom("OpenSans-Regular", size: 16))
                            .padding(.top, 12)

                        Text("Join us and start your culinary adventure")
                            .foregroundColor(Color("GrayText"))
                            .font(Font.custom("OpenSans-Regular", size: 14))
                            .padding(.top, 2)

                        GenericButton(textLabel: "Continue with Google", action: {
                            Task {
                                await viewModel.signUpWithGoogle()
                            }
                        }, type: .whiteWithGrayBorder,
                                      frameWidth: geo.size.width * 0.88,
                                      frameHeight: 48,
                                      image: .init(named: "google"))
                        .disabled(viewModel.isLoading)
                        .padding(.top, 16)
                        GenericButton(
                            textLabel: "Continue with Apple",
                            action: {
                                Task {
                                    await viewModel.signUpWithApple()
                                }
                            },
                            type: .whiteWithGrayBorder,
                            frameWidth: geo.size.width * 0.88,
                            frameHeight: 48,
                            image: .init(named: "apple")
                        )
                        .disabled(viewModel.isLoading)
                        .padding(.top, 8)
                        
                        HStack(spacing: 15) {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color("GrayButtonBorderColor"))

                            Text("or")
                                .foregroundColor(Color("GrayText"))
                                .font(Font.custom("OpenSans-Regular", size: 12))

                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color("GrayButtonBorderColor"))
                        }
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 8)
                        
                        GenericInputView(properties: $viewModel.fullName)
                            .padding(.horizontal, geo.size.width * 0.12 / 2)
                            .padding(.top, 2)
                        
                        GenericInputView(properties: $viewModel.email)
                            .padding(.horizontal, geo.size.width * 0.12 / 2)
                            .padding(.top, 2)

                        GenericInputView(properties: $viewModel.password)
                            .padding(.horizontal, geo.size.width * 0.12 / 2)
                            .padding(.top, 2)

                        GenericInputView(properties: $viewModel.confirmPassword)
                            .padding(.horizontal, geo.size.width * 0.12 / 2)
                            .padding(.top, 2)

                        // Terms and Conditions checkbox
                        HStack(alignment: .top, spacing: 8) {
                            Button(action: {
                                viewModel.agreeToTerms.toggle()
                            }) {
                                Image(systemName: viewModel.agreeToTerms ? "checkmark.square.fill" : "square")
                                    .foregroundColor(viewModel.agreeToTerms ? Color("Orange") : Color("GrayText"))
                                    .font(.system(size: 20))
                            }

                            (Text("I agree to the ")
                                .foregroundColor(Color("GrayText")) +
                             Text("Terms and Conditions")
                                .foregroundColor(Color("Orange")) +
                             Text(" and ")
                                .foregroundColor(Color("GrayText")) +
                             Text("Privacy Policy")
                                .foregroundColor(Color("Orange")))
                                .font(Font.custom("OpenSans-Regular", size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                                .onTapGesture {
                                    // TODO: Open terms and privacy policy
                                    print("terms/privacy tapped...")
                                }

                            Spacer()
                        }
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 8)

                        GenericButton(textLabel: "Create Account", action: {
                            Task {
                                await viewModel.signUp()
                            }
                        }, type: .orange,
                                      frameWidth: geo.size.width * 0.88,
                                      frameHeight: 48)
                        .disabled(viewModel.isLoading || !viewModel.agreeToTerms)
                        .opacity(viewModel.agreeToTerms ? 1.0 : 0.5)
                        .padding(.top, 12)

                        HStack(spacing: 3) {
                            Text("Already have an account?")
                                .foregroundColor(Color("GrayText"))
                                .font(Font.custom("OpenSans-Regular", size: 14))

                            Text("Sign In")
                                .foregroundColor(Color("Orange"))
                                .font(Font.custom("OpenSans-Regular", size: 16))
                        }
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 14)
                        .onTapGesture {
                            router.navigateBack()
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity) // center content within scroll width
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
            title: Text("Sign Up"),
            message: Text(viewModel.alertMessage ?? ""),
            dismissButton: .default(Text("OK")) {
                // If signup was successful, navigate back to login
                if viewModel.showSuccessMessage {
                    router.navigateToRoot()
                }
            }
        )
    }
    }
}

#Preview {
    SignUpView(viewModel: .init(), router: .init())
}
