//
//  ExploreSearchFilters.swift
//  Salt
//
//  Filter chips under the Explore search bar (Ingredients, Total time, Cuisine, Meal type)
//  and the sheet each one opens.
//

import SwiftUI

enum SearchFilterKind: String, Identifiable, CaseIterable {
    case ingredients, time, cuisine, mealType

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ingredients: "Ingredients"
        case .time: "Total Time"
        case .cuisine: "Cuisine"
        case .mealType: "Meal Type"
        }
    }
}

// MARK: - Chips Row

/// Horizontal row of filter chips; a chip shows its selection once set (e.g. "Under 30 min")
struct SearchFiltersBar: View {
    let filters: RecipeSearchFilters
    let onSelect: (SearchFilterKind) -> Void
    let onClearAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // First, so all filters can be removed with one tap
                if filters.isActive {
                    Button(action: onClearAll) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Reset")
                        }
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Color("OrangeRed")))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset all filters")
                    .transition(.scale.combined(with: .opacity))
                }

                ForEach(SearchFilterKind.allCases) { kind in
                    let label = label(for: kind)
                    FilterChip(title: label ?? kind.title, isActive: label != nil) {
                        onSelect(kind)
                    }
                    .accessibilityLabel(label.map { "\(kind.title): \($0)" } ?? kind.title)
                }
            }
            .padding(.horizontal, 18)
            .animation(.easeInOut(duration: 0.2), value: filters.isActive)
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

private struct FilterChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.custom(isActive ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 14))
            .foregroundColor(isActive ? Color("OrangeRed") : .primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(isActive ? Color("Orange").opacity(0.12) : Color(.systemBackground)))
            .overlay(Capsule().stroke(isActive ? Color("Orange") : Color("DarkSilver"), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Filter Sheet

/// Edits one filter; Show Results applies it and searches
struct SearchFilterSheet: View {
    let kind: SearchFilterKind
    @Binding var filters: RecipeSearchFilters
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecipeSearchFilters()
    @State private var ingredientText = ""
    @FocusState private var isIngredientFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch kind {
                    case .ingredients: ingredientsContent
                    case .time: timeContent
                    case .cuisine: cuisineContent
                    case .mealType: mealTypeContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            // Swiping down on the options hides the Ingredients keyboard
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(action: apply) {
                    Text("Show Results")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color("Orange"))
                        .cornerRadius(10)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset", action: resetThisFilter)
                        .disabled(!hasValue)
                }
            }
        }
        .presentationDetents(kind == .cuisine ? [.large] : [.medium, .large])
        .onAppear { draft = filters }
    }

    // MARK: Ingredients

    private var ingredientsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recipes with all of these ingredients")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("GraniteGray"))

            HStack(spacing: 10) {
                TextField("Add an ingredient", text: $ingredientText)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .focused($isIngredientFocused)
                    .submitLabel(.done)
                    .onSubmit { addIngredient(ingredientText) }
                    .textInputAutocapitalization(.never)
                Button("Add") { addIngredient(ingredientText) }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundColor(Color("OrangeRed"))
                    .disabled(ingredientText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("DarkSilver"), lineWidth: 1))

            if !draft.ingredients.isEmpty {
                ChipFlow(spacing: 8) {
                    ForEach(draft.ingredients, id: \.self) { ingredient in
                        Button(action: { draft.ingredients.removeAll { $0 == ingredient } }) {
                            HStack(spacing: 6) {
                                Text(ingredient)
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundColor(Color("OrangeRed"))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Capsule().fill(Color("Orange").opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(ingredient)")
                    }
                }
            }

            Text("Popular")
                .font(.custom("Playfair9pt-SemiBold", size: 18))
                .padding(.top, 4)
            ChipFlow(spacing: 8) {
                ForEach(RecipeSearchFilters.suggestedIngredients.filter { suggestion in
                    !draft.ingredients.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
                }, id: \.self) { suggestion in
                    OptionChip(title: suggestion, isSelected: false) {
                        addIngredient(suggestion)
                    }
                }
            }
        }
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

    private var timeContent: some View {
        VStack(spacing: 0) {
            timeRow(title: "Any time", minutes: nil)
            ForEach(RecipeSearchFilters.timeOptions, id: \.self) { minutes in
                Divider()
                timeRow(title: "Under \(minutes) minutes", minutes: minutes)
            }
        }
    }

    private func timeRow(title: String, minutes: Int?) -> some View {
        let isSelected = draft.maxTotalMinutes == minutes
        return Button(action: { draft.maxTotalMinutes = minutes }) {
            HStack {
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Color("Orange") : Color("DarkSilver"))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Cuisine

    private var cuisineContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recipes from any of these cuisines")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("GraniteGray"))
            ChipFlow(spacing: 8) {
                ForEach(RecipeSearchFilters.cuisineOptions, id: \.self) { cuisine in
                    OptionChip(title: cuisine, isSelected: draft.cuisines.contains(cuisine)) {
                        if draft.cuisines.contains(cuisine) {
                            draft.cuisines.remove(cuisine)
                        } else {
                            draft.cuisines.insert(cuisine)
                        }
                    }
                }
            }
        }
    }

    // MARK: Meal type

    private var mealTypeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recipes of any of these types")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("GraniteGray"))
            ChipFlow(spacing: 8) {
                ForEach(MealType.allCases) { mealType in
                    OptionChip(title: mealType.displayName, isSelected: draft.mealTypes.contains(mealType)) {
                        if draft.mealTypes.contains(mealType) {
                            draft.mealTypes.remove(mealType)
                        } else {
                            draft.mealTypes.insert(mealType)
                        }
                    }
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
        case .mealType: !draft.mealTypes.isEmpty
        }
    }

    private func resetThisFilter() {
        switch kind {
        case .ingredients:
            draft.ingredients = []
            ingredientText = ""
        case .time: draft.maxTotalMinutes = nil
        case .cuisine: draft.cuisines = []
        case .mealType: draft.mealTypes = []
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

/// Selectable chip in the filter sheets
private struct OptionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(isSelected ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 14))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(isSelected ? Color("Orange") : Color(.systemBackground)))
                .overlay(Capsule().stroke(isSelected ? Color("Orange") : Color("DarkSilver"), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full
private struct ChipFlow: Layout {
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
