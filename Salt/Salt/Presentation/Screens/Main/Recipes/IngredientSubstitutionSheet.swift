//
//  IngredientSubstitutionSheet.swift
//  Salt
//
//  "Replace ingredient": pick an ingredient, then one of its substitutes, by reason
//

import SwiftUI

/// An ingredient line by its place in the list (lines can repeat, e.g. "Salt" in two groups)
struct IngredientPosition: Hashable, Identifiable {
    let section: Int
    let line: Int
    let text: String  // the line as stored
    var id: Self { self }
}

/// Opened from the Replace ingredient button: the recipe's ingredients, then the substitutes
/// for the one picked
struct ReplaceIngredientSheet: View {
    let sections: [(heading: String?, positions: [IngredientPosition])]
    let swaps: [IngredientPosition: Substitute]
    let recipeTitle: String
    let ingredients: [String]
    let display: (String) -> String
    let onSelect: (IngredientPosition, Substitute?) -> Void  // also closes the sheet

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.positions) { position in
                            NavigationLink(value: position) {
                                row(position)
                            }
                        }
                    } header: {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                        }
                    }
                }
            }
            .navigationTitle("Which ingredient?")
            .navigationBarTitleDisplayMode(.inline)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ position: IngredientPosition) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let swap = swaps[position] {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color("Orange"))
                        .accessibilityHidden(true)
                    Text(display(swap.line))
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                Text("instead of \(display(position.text))")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(Color("GraniteGray"))
            } else {
                Text(display(position.text))
                    .font(.custom("OpenSans-Regular", size: 16))
            }
        }
    }
}

/// "Replace buttermilk": substitutes for one ingredient, by reason. Shown inside a navigation stack.
struct IngredientSubstitutesView: View {
    let line: String                  // the ingredient line as stored
    let recipeTitle: String
    let ingredients: [String]         // the whole recipe, so AI ideas fit the dish
    let current: Substitute?          // the swap in use, if any
    let display: (String) -> String   // a line as the recipe shows it (scaled, in the chosen units)
    let onSelect: (Substitute?) -> Void  // nil = back to the original; also closes the sheet

    @State private var reason: SubstitutionReason = .missing
    @State private var ideas: [SubstitutionReason: [Substitute]] = [:]
    @State private var loadingReason: SubstitutionReason?
    @State private var failedReason: SubstitutionReason?

    private var name: String { SubstitutionService.ingredientName(of: line) }
    private var builtIn: [Substitute] { SubstitutionService.shared.builtInSubstitutes(for: line, reason: reason) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(display(line))
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(Color("GraniteGray"))

                reasonPicker

                if !builtIn.isEmpty {
                    options(builtIn)
                }
                ideasSection

                if current != nil {
                    Button {
                        onSelect(nil)
                    } label: {
                        Label("Use the original", systemImage: "arrow.uturn.backward")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundColor(Color("Orange"))
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Replace \(name.isEmpty ? "ingredient" : name.lowercased())")
        .navigationBarTitleDisplayMode(.inline)
        // Nothing in the built-in list for this: ask the AI straight away
        .task(id: reason) {
            if builtIn.isEmpty { await loadIdeas() }
        }
    }

    // MARK: Reason

    private var reasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SubstitutionReason.allCases) { option in
                    let isSelected = option == reason
                    Button {
                        reason = option
                    } label: {
                        Text(option.title)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(isSelected ? Color("Orange") : Color("LightGrayishPink")))
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Options

    private func options(_ substitutes: [Substitute]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(substitutes, id: \.self) { substitute in
                Button {
                    Analytics.log(.ingredientSubstituted, ["source": substitute.source.rawValue, "reason": reason.rawValue])
                    onSelect(substitute)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display(substitute.line))
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundColor(.primary)
                        if let note = substitute.note {
                            Text(note)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundColor(Color("GraniteGray"))
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(substitute == current ? Color("Orange") : Color("LightGrayishPink"), lineWidth: 1.5)
                    )
                }
            }
        }
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
            HStack(spacing: 10) {
                ProgressView()
                message("Finding substitutes for this recipe…")
            }
        } else if failedReason == reason {
            VStack(alignment: .leading, spacing: 8) {
                message("Couldn't load suggestions.")
                ideasButton(title: "Try again")
            }
        } else if !builtIn.isEmpty {
            ideasButton(title: "More ideas for this recipe")
        }
    }

    private func ideasButton(title: String) -> some View {
        Button {
            Task { await loadIdeas() }
        } label: {
            Label(title, systemImage: "sparkles")
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundColor(Color("Orange"))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.custom("OpenSans-SemiBold", size: 16))
            .accessibilityAddTraits(.isHeader)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.custom("OpenSans-Regular", size: 14))
            .foregroundColor(Color("GraniteGray"))
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
