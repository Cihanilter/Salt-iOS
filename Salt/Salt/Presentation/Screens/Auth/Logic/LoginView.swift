//
//  Login.swift
//  Salt
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel
    @ObservedObject var router: AuthRouter
    @FocusState private var focusedField: Int?

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
                            .padding(.top, 50)
                        
                        Text("Welcome Back")
                            .foregroundColor(Color.black)
                            .font(Font.custom("OpenSans-Regular", size: 16))
                            .padding(.top, 12)
                        
                        Text("Sign in to continue your cooking journey")
                            .foregroundColor(Color("GrayText"))
                            .font(Font.custom("OpenSans-Regular", size: 14))
                            .padding(.top, 2)
                        GenericButton(textLabel: "Continue with Google", action: {
                            Task {
                                await viewModel.signInWithGoogle()
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
                                    await viewModel.signInWithApple()
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
                        
                        GenericInputView(
                            properties: $viewModel.email,
                            focusField: $focusedField,
                            fieldIndex: 0
                        )
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 8)
                        .onChange(of: viewModel.email.inputText) { _ in
                            if viewModel.email.onSubmit == nil {
                                viewModel.email.onSubmit = {
                                    focusedField = 1
                                }
                            }
                        }

                        GenericInputView(
                            properties: $viewModel.password,
                            focusField: $focusedField,
                            fieldIndex: 1
                        )
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 8)
                        .onChange(of: viewModel.password.inputText) { _ in
                            if viewModel.password.onSubmit == nil {
                                viewModel.password.onSubmit = {
                                    focusedField = nil
                                    Task {
                                        await viewModel.signIn()
                                    }
                                }
                            }
                        }
                        
                        HStack {
                            Spacer()
                            
                            Text("Forgot Password?")
                                .foregroundColor(Color("Orange"))
                                .font(Font.custom("OpenSans-Regular", size: 14))
                                .onTapGesture {
                                    router.navigate(to: .forgotPassword)
                                }
                        }
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 12)
                        
                        GenericButton(textLabel: "Sign In", action: {
                            Task {
                                await viewModel.signIn()
                            }
                        }, type: .orange,
                                      frameWidth: geo.size.width * 0.88,
                                      frameHeight: 48)
                        .disabled(viewModel.isLoading)
                        .padding(.top, 12)
                        
                        HStack(spacing: 3) {
                            Text("Don't have an account?")
                                .foregroundColor(Color("GrayText"))
                                .font(Font.custom("OpenSans-Regular", size: 14))
                                
                            
                            Text("Sign Up")
                                .foregroundColor(Color("Orange"))
                                .font(Font.custom("OpenSans-Regular", size: 16))
                              
                        }
                        .padding(.horizontal, geo.size.width * 0.12 / 2)
                        .padding(.top, 14)
                        .onTapGesture {
                            router.navigate(to: .signUp)
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
            title: Text("Sign In"),
            message: Text(viewModel.alertMessage ?? ""),
            dismissButton: .default(Text("OK"))
        )
    }
    }
}

#Preview {
    LoginView(viewModel: .init(), router: .init())
}
