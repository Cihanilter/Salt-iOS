//
//  ExploreSearchFilters.swift
//  Salt
//
//  Filter chips under the Explore search bar (Ingredients, Total time, Cuisine, Meal type)
//  and the sheet each one opens. One sheet template: grabber, Playfair title, Reset (gray
//  until something is chosen), content, and a Primary button with the live result count.
//

import SwiftUI

enum SearchFilterKind: String, Identifiable, CaseIterable {
    case ingredients, time, cuisine, mealType

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ingredients: "Ingredients"
        case .time: "Total time"
        case .cuisine: "Cuisine"
        case .mealType: "Meal type"
        }
    }
}

// MARK: - Chips Row

/// Filter chips: outline when empty; once applied, peach + ✓ showing the chosen value
struct SearchFiltersBar: View {
    let filters: RecipeSearchFilters
    let onSelect: (SearchFilterKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilterKind.allCases) { kind in
                    let label = label(for: kind)
                    SaltChip(title: label ?? kind.title, isSelected: label != nil, showsChevron: true) {
                        onSelect(kind)
                    }
                    .accessibilityLabel(label.map { "\(kind.title): \($0)" } ?? kind.title)
                    .accessibilityAddTraits(label != nil ? .isSelected : [])
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
        }
    }

    private func label(for kind: SearchFilterKind) -> String? {
        switch kind {
        case .ingredients: filters.ingredientsLabel
        case .time: filters.timeLabel
        case .cuisine: filters.cuisineLabel
        case .mealType: filters.mealTypeLabel
        }
    }
}

// MARK: - Filter Sheet

/// Edits one filter; "Show 12 recipes" applies it. Swipe down cancels.
struct SearchFilterSheet: View {
    let kind: SearchFilterKind
    @Binding var filters: RecipeSearchFilters
    /// Results the (not yet applied) filters would give; nil when unknown
    let countResults: (RecipeSearchFilters) async -> Int?
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecipeSearchFilters()
    @State private var ingredientText = ""
    @State private var liveCount: Int?
    @State private var isCounting = false
    @FocusState private var isIngredientFocused: Bool

    private var usesTallSheet: Bool {
        kind == .cuisine || kind == .mealType
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SaltSheetHeader(title: kind.title) {
                Button("Reset", action: resetThisFilter)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(hasValue ? SaltColor.textAccent : SaltColor.textDisabled)
                    .disabled(!hasValue)
            }
            .padding(.bottom, 20)

            Group {
                if usesTallSheet {
                    ScrollView(showsIndicators: false) {
                        content
                            .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    content
                }
            }

            footer
                .padding(.top, 20)
        }
        .modifier(FilterSheetSizing(isTall: usesTallSheet))
        .onAppear { draft = filters }
        .task(id: draft) {
            // Debounced so quick taps don't each run a count
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isCounting = true
            liveCount = await countResults(draft)
            isCounting = false
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .ingredients: ingredientsContent
        case .time: timeContent
        case .cuisine: cuisineContent
        case .mealType: mealTypeContent
        }
    }

    // MARK: Footer

    /// "Show 12 recipes"; a combination with no results → disabled "No matches" + a hint
    @ViewBuilder private var footer: some View {
        let noMatches = liveCount == 0 && draft.isActive
        VStack(spacing: 12) {
            if noMatches {
                Text(noMatchesHint)
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Button(action: apply) {
                Text(buttonTitle)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.salt())
            .disabled(noMatches)
            .animation(.easeInOut(duration: 0.2), value: liveCount)
        }
    }

    private var buttonTitle: String {
        guard draft.isActive, let liveCount else { return String(localized: "Show recipes") }
        if liveCount == 0 { return String(localized: "No matches") }
        return liveCount == 1 ? String(localized: "Show 1 recipe") : String(localized: "Show \(liveCount) recipes")
    }

    private var noMatchesHint: String {
        switch kind {
        case .ingredients where draft.ingredients.count > 1:
            String(localized: "No recipe has all \(draft.ingredients.count). Try removing an ingredient.")
        case .time:
            String(localized: "Nothing that quick yet. Try a longer time.")
        default:
            String(localized: "Nothing matches all your filters. Try removing one.")
        }
    }

    // MARK: Ingredients

    private var ingredientsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recipes with all of these ingredients")
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
                .padding(.bottom, 16)

            HStack(spacing: 10) {
                TextField("", text: $ingredientText, prompt: Text("Add an ingredient").foregroundStyle(SaltColor.textSecondary))
                    .focused($isIngredientFocused)
                    .submitLabel(.done)
                    .onSubmit { addIngredient(ingredientText) }
                    .textInputAutocapitalization(.never)
                Button("Add") { addIngredient(ingredientText) }
                    .font(SaltFont.bodyLargeStrong)
                    .foregroundStyle(ingredientText.trimmingCharacters(in: .whitespaces).isEmpty ? SaltColor.textDisabled : SaltColor.textAccent)
                    .disabled(ingredientText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(height: 28)
            .saltInput(isFocused: isIngredientFocused)
            .padding(.bottom, 24)

            Text("Popular")
                .font(SaltFont.h3)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.bottom, SaltSpacing.titleToContent)

            ChipFlow(spacing: 8) {
                // Typed ingredients first, then the quick picks
                ForEach(ingredientOptions, id: \.self) { ingredient in
                    let isSelected = draft.ingredients.contains { $0.caseInsensitiveCompare(ingredient) == .orderedSame }
                    SaltChip(title: ingredient, isSelected: isSelected) {
                        if isSelected {
                            draft.ingredients.removeAll { $0.caseInsensitiveCompare(ingredient) == .orderedSame }
                        } else {
                            addIngredient(ingredient)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var ingredientOptions: [String] {
        let suggested = RecipeSearchFilters.suggestedIngredients
        let typed = draft.ingredients.filter { ingredient in
            !suggested.contains { $0.caseInsensitiveCompare(ingredient) == .orderedSame }
        }
        return typed + suggested
    }

    private func addIngredient(_ text: String) {
        let ingredient = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ingredient.isEmpty,
              !draft.ingredients.contains(where: { $0.caseInsensitiveCompare(ingredient) == .orderedSame }) else {
            ingredientText = ""
            return
        }
        draft.ingredients.append(ingredient)
        ingredientText = ""
    }

    // MARK: Total time

    /// Single choice, so a radio list instead of chips
    private var timeContent: some View {
        VStack(spacing: 0) {
            timeRow(title: String(localized: "Any time"), minutes: nil)
            ForEach(RecipeSearchFilters.timeOptions, id: \.self) { minutes in
                Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)
                timeRow(
                    title: minutes == 60 ? String(localized: "Under 1 hour") : String(localized: "Under \(minutes) minutes"),
                    minutes: minutes
                )
            }
        }
    }

    private func timeRow(title: String, minutes: Int?) -> some View {
        let isSelected = draft.maxTotalMinutes == minutes
        return Button(action: { draft.maxTotalMinutes = minutes }) {
            HStack {
                Text(title)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
                Spacer()
                ZStack {
                    if isSelected {
                        Circle().fill(SaltColor.actionPrimary)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Circle().stroke(SaltColor.borderDefault, lineWidth: 1)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Cuisine

    private var cuisineContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recipes from any of these cuisines")
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
            ChipFlow(spacing: 8) {
                ForEach(RecipeSearchFilters.cuisineOptions, id: \.self) { cuisine in
                    SaltChip(title: cuisine, isSelected: draft.cuisines.contains(cuisine)) {
                        if draft.cuisines.contains(cuisine) {
                            draft.cuisines.remove(cuisine)
                        } else {
                            draft.cuisines.insert(cuisine)
                        }
                    }
                    .accessibilityAddTraits(draft.cuisines.contains(cuisine) ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Meal type

    private var mealTypeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recipes of any of these types")
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
            ChipFlow(spacing: 8) {
                // The same categories as the chips on Explore
                ForEach(DishType.all) { dishType in
                    SaltChip(title: dishType.displayName, isSelected: draft.dishTypes.contains(dishType.name)) {
                        if draft.dishTypes.contains(dishType.name) {
                            draft.dishTypes.remove(dishType.name)
                        } else {
                            draft.dishTypes.insert(dishType.name)
                        }
                    }
                    .accessibilityAddTraits(draft.dishTypes.contains(dishType.name) ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Actions

    private var hasValue: Bool {
        switch kind {
        case .ingredients: !draft.ingredients.isEmpty || !ingredientText.isEmpty
        case .time: draft.maxTotalMinutes != nil
        case .cuisine: !draft.cuisines.isEmpty
        case .mealType: !draft.dishTypes.isEmpty
        }
    }

    private func resetThisFilter() {
        switch kind {
        case .ingredients:
            draft.ingredients = []
            ingredientText = ""
        case .time: draft.maxTotalMinutes = nil
        case .cuisine: draft.cuisines = []
        case .mealType: draft.dishTypes = []
        }
    }

    private func apply() {
        isIngredientFocused = false
        // An ingredient typed but not added still counts
        if kind == .ingredients { addIngredient(ingredientText) }
        filters = draft
        dismiss()
        onApply()
    }
}

/// Half-height white sheet; Cuisine and Meal type can grow to full height
private struct FilterSheetSizing: ViewModifier {
    let isTall: Bool

    func body(content: Content) -> some View {
        if isTall {
            content
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.top, 32)
                .padding(.bottom, 16)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(SaltRadius.sheet)
                .presentationBackground(SaltColor.surfaceScreen)
        } else {
            content.saltFittedSheet()
        }
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
