//
//  IngredientSubstitutionSheet.swift
//  Salt
//
//  "Swap an ingredient": pick an ingredient, then one of its substitutes, by reason
//

import SwiftUI

/// An ingredient line by its place in the list (lines can repeat, e.g. "Salt" in two groups)
struct IngredientPosition: Hashable, Identifiable {
    let section: Int
    let line: Int
    let text: String  // the line as stored
    var id: Self { self }
}

/// Opened from the Swap an ingredient link: the recipe's ingredients, then the substitutes
/// for the one picked. A white sheet with a Playfair title; swipe down to close.
struct ReplaceIngredientSheet: View {
    let sections: [(heading: String?, positions: [IngredientPosition])]
    let swaps: [IngredientPosition: Substitute]
    let recipeTitle: String
    let ingredients: [String]
    let display: (String) -> String
    let onSelect: (IngredientPosition, Substitute?) -> Void  // also closes the sheet

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Swap an ingredient")
                        .font(SaltFont.h2)
                        .foregroundStyle(SaltColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 8)

                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        if let heading = section.heading {
                            Text(heading)
                                .font(SaltFont.h3)
                                .foregroundStyle(SaltColor.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, 20)
                        }
                        ForEach(Array(section.positions.enumerated()), id: \.element) { index, position in
                            NavigationLink(value: position) {
                                row(position)
                            }
                            .buttonStyle(.plain)
                            if index < section.positions.count - 1 {
                                Divider().overlay(SaltColor.borderSubtle)
                            }
                        }
                    }
                }
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .background(SaltColor.surfaceScreen)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: IngredientPosition.self) { position in
                IngredientSubstitutesView(
                    line: position.text,
                    recipeTitle: recipeTitle,
                    ingredients: ingredients,
                    current: swaps[position],
                    display: display,
                    onSelect: { onSelect(position, $0) }
                )
            }
        }
        .swapSheetStyle()
    }

    private func row(_ position: IngredientPosition) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let swap = swaps[position] {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image("swapIcon")
                            .resizable()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(SaltColor.iconAccent)
                            .alignmentGuide(.firstTextBaseline) { $0.height * 0.75 }
                            .accessibilityHidden(true)
                        Text(display(swap.line))
                            .font(SaltFont.bodyLarge)
                            .foregroundStyle(SaltColor.textPrimary)
                    }
                    Text("instead of \(display(position.text))")
                        .font(SaltFont.caption)
                        .foregroundStyle(SaltColor.textSecondary)
                } else {
                    Text(display(position.text))
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textPrimary)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SaltColor.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

/// "Swap": the ingredient in a soft box, the reason as chips, then substitutes with a small
/// "Use". Shown inside a navigation stack; the back chevron returns to the ingredient list.
struct IngredientSubstitutesView: View {
    let line: String                  // the ingredient line as stored
    let recipeTitle: String
    let ingredients: [String]         // the whole recipe, so AI ideas fit the dish
    let current: Substitute?          // the swap in use, if any
    let display: (String) -> String   // a line as the recipe shows it (scaled, in the chosen units)
    var showsBack = true              // false when opened straight from a swapped line
    let onSelect: (Substitute?) -> Void  // nil = back to the original; also closes the sheet

    @Environment(\.dismiss) private var dismiss
    @State private var reason: SubstitutionReason = .missing
    @State private var ideas: [SubstitutionReason: [Substitute]] = [:]
    @State private var loadingReason: SubstitutionReason?
    @State private var failedReason: SubstitutionReason?

    private var builtIn: [Substitute] { SubstitutionService.shared.builtInSubstitutes(for: line, reason: reason) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 20)

                Text(display(line))
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(SaltColor.surfaceWarmSubtle, in: RoundedRectangle(cornerRadius: SaltRadius.input, style: .continuous))

                Text("Why do you want to swap it?")
                    .font(SaltFont.bodyStrong)
                    .foregroundStyle(SaltColor.textSecondary)
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                reasonPicker
                    .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 20) {
                    if !builtIn.isEmpty {
                        options(builtIn)
                    }
                    ideasSection

                    if current != nil {
                        Button {
                            onSelect(nil)
                        } label: {
                            Label("Use the original", systemImage: "arrow.uturn.backward")
                                .font(SaltFont.bodyLargeStrong)
                                .foregroundStyle(SaltColor.textAccent)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .background(SaltColor.surfaceScreen)
        .toolbar(.hidden, for: .navigationBar)
        // Nothing in the built-in list for this: ask the AI straight away
        .task(id: reason) {
            if builtIn.isEmpty { await loadIdeas() }
        }
    }

    /// Short "Swap" title; the ingredient itself is in the box below
    private var header: some View {
        HStack(spacing: 12) {
            if showsBack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SaltColor.iconDefault)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, -12)
                .padding(.vertical, -10)
                .accessibilityLabel("Back")
            }
            Text("Swap")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Reason

    /// Chips (selected = peach + ✓); the row scrolls edge to edge
    private var reasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SubstitutionReason.allCases) { option in
                    SaltChip(title: option.title, isSelected: option == reason) {
                        reason = option
                    }
                    .accessibilityAddTraits(option == reason ? .isSelected : [])
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
        }
        .padding(.horizontal, -SaltSpacing.screenMargin)
    }

    // MARK: Options

    private func options(_ substitutes: [Substitute]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(substitutes, id: \.self) { substitute in
                Button {
                    Analytics.log(.ingredientSubstituted, ["source": substitute.source.rawValue, "reason": reason.rawValue])
                    onSelect(substitute)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(display(substitute.line))
                                .font(SaltFont.bodyLargeStrong)
                                .foregroundStyle(SaltColor.textPrimary)
                            if let note = substitute.note {
                                Text(note)
                                    .font(SaltFont.body)
                                    .foregroundStyle(SaltColor.textSecondary)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Use")
                            .font(SaltFont.bodyLargeStrong)
                            .foregroundStyle(SaltColor.textAccent)
                    }
                    .padding(16)
                    .background(SaltColor.surfaceScreen, in: RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
                            .stroke(substitute == current ? SaltColor.actionPrimary : SaltColor.borderSubtle, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Gray skeleton cards in the shape of the suggestions, with one line of text
    private var loadingCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Finding swaps for this recipe…")
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    SaltSkeleton(cornerRadius: 7)
                        .frame(width: 220, height: 14)
                    SaltSkeleton(cornerRadius: 5)
                        .frame(maxWidth: 280)
                        .frame(height: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .overlay(
                    RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
                        .stroke(SaltColor.borderSubtle, lineWidth: 1)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finding swaps for this recipe")
    }

    // MARK: Ideas for this recipe

    @ViewBuilder
    private var ideasSection: some View {
        if let found = ideas[reason] {
            VStack(alignment: .leading, spacing: 10) {
                if !builtIn.isEmpty {
                    sectionTitle("Ideas for this recipe")
                }
                if found.isEmpty {
                    message("No other substitutes found.")
                } else {
                    options(found)
                }
            }
        } else if loadingReason == reason {
            loadingCards
        } else if failedReason == reason {
            VStack(alignment: .leading, spacing: 8) {
                message("Couldn't load suggestions.")
                ideasButton(title: "Try again")
            }
        } else if !builtIn.isEmpty {
            ideasButton(title: "More ideas for this recipe")
        }
    }

    private func ideasButton(title: LocalizedStringResource) -> some View {
        Button {
            Task { await loadIdeas() }
        } label: {
            Label(title, systemImage: "sparkles")
                .font(SaltFont.bodyLargeStrong)
                .foregroundStyle(SaltColor.textAccent)
        }
        .frame(minHeight: 44)
    }

    private func sectionTitle(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(SaltFont.bodyLargeStrong)
            .foregroundStyle(SaltColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func message(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(SaltFont.body)
            .foregroundStyle(SaltColor.textSecondary)
    }

    private func loadIdeas() async {
        let requested = reason
        guard ideas[requested] == nil, loadingReason != requested else { return }
        loadingReason = requested
        failedReason = nil
        defer { if loadingReason == requested { loadingReason = nil } }

        do {
            let found = try await SubstitutionService.shared.aiSubstitutes(
                for: line, recipeTitle: recipeTitle, ingredients: ingredients, reason: requested
            )
            // Leave out what the built-in list already shows
            let shown = Set(SubstitutionService.shared.builtInSubstitutes(for: line, reason: requested)
                .map { $0.line.lowercased() })
            ideas[requested] = found.filter { !shown.contains($0.line.lowercased()) }
        } catch {
            failedReason = requested
        }
    }
}

extension View {
    /// The swap sheets: white like every other sheet (not iOS gray), with a grabber
    func swapSheetStyle() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(SaltRadius.sheet)
            .presentationBackground(SaltColor.surfaceScreen)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        NavigationStack {
            IngredientSubstitutesView(
                line: "1 cup buttermilk",
                recipeTitle: "Buttermilk pancakes",
                ingredients: ["2 cups all-purpose flour", "1 cup buttermilk", "2 large eggs"],
                current: nil,
                display: { IngredientScaler.display($0) },
                onSelect: { _ in }
            )
        }
        .swapSheetStyle()
    }
}

#Preview("Which ingredient") {
    let lines = ["2 cups all-purpose flour", "1 cup buttermilk", "2 large eggs"]
    let positions = lines.enumerated().map { IngredientPosition(section: 0, line: $0, text: $1) }
    Color.clear.sheet(isPresented: .constant(true)) {
        ReplaceIngredientSheet(
            sections: [(nil, positions)],
            swaps: [positions[1]: Substitute(line: "1 cup milk with lemon juice", note: nil, source: .builtIn)],
            recipeTitle: "Buttermilk pancakes",
            ingredients: lines,
            display: { IngredientScaler.display($0) },
            onSelect: { _, _ in }
        )
    }
}
