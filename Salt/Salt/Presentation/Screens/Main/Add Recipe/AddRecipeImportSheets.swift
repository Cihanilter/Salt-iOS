//
//  AddRecipeImportSheets.swift
//  Salt
//
//  The import sheets on Add Recipe (Figma "Add Recipe — Final"): Link, Photo and Text,
//  each with one Large Primary action, plus the error states of the Link sheet.
//

import SwiftUI

// MARK: - Import failure

/// How an import error is shown: which field turns red and what the next step is
enum ImportFailure: Equatable {
    /// The link opens something that isn't a recipe: red field, "Paste another link"
    case notARecipe(String)
    /// The link is fine but the site/post can't be read (yet): "Use a screenshot instead"
    case couldNotImport(String)
    /// Offline, timed out or busy: "Try again"
    case temporary(String)
    /// Photo or text that has no recipe in it
    case unreadable(String)

    var message: String {
        switch self {
        case .notARecipe(let m), .couldNotImport(let m), .temporary(let m), .unreadable(let m): m
        }
    }

    var marksField: Bool {
        switch self {
        case .notARecipe, .unreadable: true
        case .couldNotImport, .temporary: false
        }
    }

    init(_ error: RecipeImportError) {
        switch error {
        case .invalidUrl:
            self = .notARecipe(error.errorDescription ?? "")
        case .noRecipeFound(nil):
            self = .notARecipe(String(localized: "We couldn't find a recipe on this page. Check that the link opens a recipe post or page."))
        case .noRecipeFound(.some), .postUnavailable, .pageUnavailable:
            // A post without a written recipe is best imported from screenshots
            self = .couldNotImport(error.errorDescription ?? "")
        case .failed:
            // The failed link is reported with the importFailed analytics event
            self = .couldNotImport(String(localized: "We couldn't import this one yet. Our team has been notified and is looking into it."))
        case .offline, .timedOut, .serviceBusy:
            self = .temporary(error.errorDescription ?? "")
        case .noTextInPhoto, .noRecipeInPhoto, .noRecipeInText:
            self = .unreadable(error.errorDescription ?? "")
        }
    }
}

/// Quiet gray line under the Import button for free users
struct FreeImportsLine: View {
    let left: Int?

    var body: some View {
        if let left, left > 0 {
            Text(left == 1 ? "Last free import" : "\(left) free imports left")
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Sheet container

/// White sheet that fits its content: 18 sides, 24 corner radius, grabber.
struct SaltFittedSheet: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 32)
            .padding(.bottom, 16)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(SaltRadius.sheet)
            .presentationBackground(SaltColor.surfaceScreen)
    }
}

extension View {
    func saltFittedSheet() -> some View { modifier(SaltFittedSheet()) }
}

// MARK: - Link sheet

struct LinkImportSheet: View {
    @Binding var link: String
    let isImporting: Bool
    let failure: ImportFailure?
    let freeImportsLeft: Int?
    let onImport: () -> Void
    let onClearFailure: () -> Void
    let onUseScreenshot: () -> Void
    let onPasteAsText: () -> Void

    @FocusState private var isFocused: Bool

    private var hasLink: Bool {
        !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paste a recipe link")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.bottom, 24)

            HStack(spacing: 8) {
                TextField("", text: $link, prompt: Text("instagram.com/reel/…").foregroundStyle(SaltColor.textSecondary))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($isFocused)
                    .onSubmit { if hasLink && !isImporting { onImport() } }
                    .frame(height: 28)
                    .saltInput(isFocused: isFocused, hasError: failure?.marksField == true)
                    .disabled(isImporting)

                SystemPasteButton(style: .secondary, cornerRadius: SaltRadius.input) { pasted in
                    link = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    onClearFailure()
                }
                .frame(width: 76, height: 52)
                .disabled(isImporting)
            }
            .onChange(of: link) { _, _ in
                if failure != nil { onClearFailure() }
            }

            Group {
                if let failure {
                    SaltFieldError(message: failure.message)
                } else {
                    Text("Works with Instagram, TikTok, YouTube and most food blogs.")
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
            .padding(.bottom, 24)

            actions

            if failure == nil {
                Group {
                    if isImporting {
                        Text("Reading the recipe. This usually takes a few seconds.")
                            .font(SaltFont.body)
                            .foregroundStyle(SaltColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    } else {
                        FreeImportsLine(left: freeImportsLeft)
                    }
                }
                .padding(.top, 16)
            }
        }
        .saltFittedSheet()
        .onAppear {
            if !hasLink && failure == nil { isFocused = true }
        }
    }

    @ViewBuilder private var actions: some View {
        switch failure {
        case .notARecipe:
            VStack(spacing: 12) {
                Button("Paste another link") {
                    link = ""
                    onClearFailure()
                    isFocused = true
                }
                .buttonStyle(.salt())
                Button("Paste as text instead", action: onPasteAsText)
                    .buttonStyle(.salt(.secondary))
            }
        case .couldNotImport:
            VStack(spacing: 12) {
                Button("Use a screenshot instead", action: onUseScreenshot)
                    .buttonStyle(.salt())
                Button("Paste as text instead", action: onPasteAsText)
                    .buttonStyle(.salt(.secondary))
            }
        case .temporary:
            VStack(spacing: 12) {
                Button("Try again", action: onImport)
                    .buttonStyle(.salt())
                Button("Paste as text instead", action: onPasteAsText)
                    .buttonStyle(.salt(.secondary))
            }
        case .unreadable, nil:
            Button(action: onImport) {
                SaltButtonLabel(title: isImporting ? "Importing…" : "Import recipe", isLoading: isImporting)
            }
            .buttonStyle(.salt())
            // Gray until a link is in; while importing it stays orange with a spinner,
            // but can't be tapped twice
            .opacity(isImporting ? 0.85 : 1)
            .environment(\.isEnabled, hasLink || isImporting)
            .allowsHitTesting(hasLink && !isImporting)
        }
    }
}

// MARK: - Photo sheet

struct PhotoImportSheet: View {
    let maxPhotos: Int
    let failure: ImportFailure?
    let onTakePhoto: () -> Void
    let onChooseFromLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add from a photo")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.bottom, 24)

            PhotoSourcesIllustration()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

            Group {
                if let failure {
                    SaltFieldError(message: failure.message)
                } else {
                    Text("Cookbook pages, screenshots and handwritten recipe cards — Salt reads them all.")
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 16)

            VStack(spacing: 12) {
                if CameraView.isAvailable {
                    Button("Take a photo", action: onTakePhoto)
                        .buttonStyle(.salt())
                    Button("Choose from library", action: onChooseFromLibrary)
                        .buttonStyle(.salt(.secondary))
                } else {
                    Button("Choose from library", action: onChooseFromLibrary)
                        .buttonStyle(.salt())
                }
            }

            Text("Up to \(maxPhotos) photos for recipes that span several pages.")
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        .saltFittedSheet()
    }
}

/// A cookbook page, a phone screenshot and a handwritten card, drawn (no real photos)
private struct PhotoSourcesIllustration: View {
    var body: some View {
        ZStack {
            page
                .rotationEffect(.degrees(-6))
                .offset(x: -58, y: 8)
            phone
            handwrittenCard
                .rotationEffect(.degrees(-6))
                .offset(x: 62, y: 4)
        }
        .frame(height: 100)
        .accessibilityHidden(true)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(SaltColor.surfacePink).frame(height: 22)
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(SaltColor.borderSubtle).frame(width: i == 3 ? 30 : 50, height: 2.5)
            }
        }
        .padding(7)
        .frame(width: 64, height: 84, alignment: .top)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(SaltColor.borderSubtle, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var phone: some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 4).fill(SaltColor.surfaceWarmStrong).frame(height: 28)
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(SaltColor.borderSubtle).frame(width: i == 2 ? 22 : 40, height: 2.5)
            }
        }
        .padding(6)
        .frame(width: 52, height: 94, alignment: .top)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SaltColor.textPrimary, lineWidth: 2))
    }

    private var handwrittenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(SaltColor.actionPrimary).frame(width: i == 0 ? 26 : 40, height: 2.5)
                    .rotationEffect(.degrees(-4))
            }
        }
        .padding(9)
        .frame(width: 66, height: 82, alignment: .topLeading)
        .background(SaltColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(SaltColor.actionPrimary, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - Text sheet

struct TextImportSheet: View {
    @Binding var text: String
    let isImporting: Bool
    let failure: ImportFailure?
    let freeImportsLeft: Int?
    let onImport: () -> Void
    let onClearFailure: () -> Void

    @FocusState private var isFocused: Bool

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paste recipe text")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.bottom, 24)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Grandma's lemon cake\n3 eggs, 200g sugar, 1 lemon…\nBeat the eggs with the sugar until pale, then…")
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textSecondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .disabled(isImporting)
            }
            .frame(height: 124)
            .saltInput(isFocused: isFocused, hasError: failure != nil)
            .onChange(of: text) { _, _ in
                if failure != nil { onClearFailure() }
            }

            Group {
                if let failure {
                    SaltFieldError(message: failure.message)
                } else {
                    Text("Salt will sort it into a title, ingredients and steps. You can edit everything before saving.")
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
            .padding(.bottom, 24)

            Button(action: onImport) {
                SaltButtonLabel(title: isImporting ? "Importing…" : "Import recipe", isLoading: isImporting)
            }
            .buttonStyle(.salt())
            .opacity(isImporting ? 0.85 : 1)
            .environment(\.isEnabled, hasText || isImporting)
            .allowsHitTesting(hasText && !isImporting)

            Group {
                if isImporting {
                    Text("Reading the recipe. This usually takes a few seconds.")
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else {
                    FreeImportsLine(left: freeImportsLeft)
                }
            }
            .padding(.top, 16)
        }
        .saltFittedSheet()
        .onAppear {
            if text.isEmpty { isFocused = true }
        }
    }
}

// MARK: - Previews

#Preview("Link sheet") {
    Color.gray.sheet(isPresented: .constant(true)) {
        LinkImportSheet(
            link: .constant("instagram.com/reel/C8xQ2"),
            isImporting: false,
            failure: .notARecipe("We couldn't find a recipe on this page. Check that the link opens a recipe post or page."),
            freeImportsLeft: 1,
            onImport: {}, onClearFailure: {}, onUseScreenshot: {}, onPasteAsText: {}
        )
    }
}

#Preview("Photo sheet") {
    Color.gray.sheet(isPresented: .constant(true)) {
        PhotoImportSheet(maxPhotos: 5, failure: nil, onTakePhoto: {}, onChooseFromLibrary: {})
    }
}

#Preview("Text sheet") {
    Color.gray.sheet(isPresented: .constant(true)) {
        TextImportSheet(text: .constant(""), isImporting: false, failure: nil, freeImportsLeft: 2, onImport: {}, onClearFailure: {})
    }
}
