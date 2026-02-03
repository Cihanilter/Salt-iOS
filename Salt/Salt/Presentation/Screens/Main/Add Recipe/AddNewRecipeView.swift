
import SwiftUI
import PhotosUI

// MARK: - Add New Recipe View

struct AddNewRecipeView: View {
    @State private var selectedTab: AddRecipeTab = .import
    @State private var recipeLink = ""

    // Callback to switch to My Recipes tab
    var switchToMyRecipes: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header
            Text("Add New Recipe")
                .font(.custom("Playfair9pt-SemiBold", size: 28))
                .padding(.horizontal)
                .padding(.top, 16)

            // Tab Switcher
            TabSwitcher(selectedTab: $selectedTab)
                .padding(.horizontal)

            // Content
            if selectedTab == .create {
                CreateRecipeView(switchToMyRecipes: switchToMyRecipes)
            } else {
                ImportRecipeView(recipeLink: $recipeLink, switchToMyRecipes: switchToMyRecipes)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Tab Enum

enum AddRecipeTab {
    case create
    case `import`
}

// MARK: - Tab Switcher

struct TabSwitcher: View {
    @Binding var selectedTab: AddRecipeTab
    
    var body: some View {
        ZStack {
            // Background
            Color("LightGrayishPink")
            
            // White selector
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .frame(width: 156, height: 36)
                .offset(x: selectedTab == .create ? -82 : 82)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            
            // Buttons
            HStack(spacing: 0) {
                // Create Tab
                Button(action: { selectedTab = .create }) {
                    HStack(spacing: 4) {
                        Text("Create")
                            .font(.custom("Playfair9pt-Regular", size: 22))
                            .foregroundColor(Color.black)
                        
                        Image("createIcon")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 20, height: 20)
                            .foregroundColor(Color("GraniteGray"))
                    }
                    .frame(width: 164, height: 44)
                }
                
                // Import Tab
                Button(action: { selectedTab = .import }) {
                    HStack(spacing: 4) {
                        Text("Import")
                            .font(.custom("Playfair9pt-Regular", size: 22))
                            .foregroundColor(Color.black)
                        
                        Image("importIcon")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color("GraniteGray"))
                    }
                    .frame(width: 164, height: 44)
                }
            }
        }
        .frame(width: 328, height: 44)
        .cornerRadius(16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Import Recipe View

struct ImportRecipeView: View {
    @Binding var recipeLink: String
    @StateObject private var viewModel = RecipeImportViewModel()
    @State private var navigateToPreview = false

    // Callback to switch to My Recipes tab
    var switchToMyRecipes: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text("Enter your recipe link here")
                .font(.custom("Playfair9pt-Regular", size: 22))

            // Text Field
            ZStack(alignment: .leading) {
                if recipeLink.isEmpty {
                    Text("e.g., https://example.com/recipe/pancake")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("DarkSilver"))
                        .padding(.horizontal, 16)
                }

                TextField("", text: $recipeLink)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.black)
                    .tint(Color("OrangeRed"))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .padding(.horizontal, 16)
            }
            .frame(height: 35)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color("DarkSilver"), lineWidth: 1)
            )

            // Description
            Text("Paste the link, and we'll pull in the recipe for you to review and save.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("DarkSilver"))

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.red)
            }

            // Import Button
            HStack {
                Spacer()
                Button(action: {
                    Task {
                        await viewModel.importRecipe(from: recipeLink)
                        if viewModel.importedRecipe != nil {
                            navigateToPreview = true
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.isLoading ? "Importing..." : "Import the Recipe")
                            .font(.custom("OpenSans-SemiBold", size: 18))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color("Orange"))
                    .cornerRadius(10)
                }
                .disabled(recipeLink.isEmpty || viewModel.isLoading)
                Spacer()
            }
            .padding(.top, 27)

            Spacer()
        }
        .padding(.horizontal)
        .navigationDestination(isPresented: $navigateToPreview) {
            if let recipe = viewModel.importedRecipe {
                RecipeDetailView(
                    recipe: recipe.toRecipeDetail(),
                    mode: .preview,
                    onSave: {
                        // Get ALL data from shared storage - no closure parameters!
                        let savedData = PendingSaveDataStorage.shared.retrieve()
                        guard let recipeDetail = savedData.recipe else {
                            return false
                        }
                        return await viewModel.saveRecipe(from: recipeDetail, photos: savedData.photos)
                    },
                    onAddMoreRecipes: {
                        // Clear and go back
                        recipeLink = ""
                        viewModel.clearImport()
                        PendingSaveDataStorage.shared.clear()
                        navigateToPreview = false
                    },
                    onGoToMyRecipes: {
                        recipeLink = ""
                        viewModel.clearImport()
                        PendingSaveDataStorage.shared.clear()
                        navigateToPreview = false
                        switchToMyRecipes?()
                    }
                )
            }
        }
        .onChange(of: viewModel.savedSuccessfully) { _, saved in
            if saved {
                // Clear the link after recipe is successfully saved
                recipeLink = ""
            }
        }
    }
}

// MARK: - Imported Recipe Preview

struct ImportedRecipePreviewView: View {
    let recipe: ImportedRecipe
    @ObservedObject var viewModel: RecipeImportViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Image
                    if let imageUrl = recipe.imageUrl, let url = URL(string: imageUrl) {
                        CachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .overlay(ProgressView())
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(height: 200)
                        .clipped()
                        .cornerRadius(12)
                    }

                    // Title
                    Text(recipe.title)
                        .font(.custom("Playfair9pt-SemiBold", size: 24))

                    // Source
                    if let source = recipe.sourceName {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("From \(source)")
                        }
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("GraniteGray"))
                    }

                    // Time info
                    HStack(spacing: 20) {
                        if let prepTime = recipe.prepTimeMinutes {
                            VStack {
                                Text("\(prepTime)")
                                    .font(.custom("Playfair9pt-SemiBold", size: 18))
                                Text("Prep")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundColor(Color("GraniteGray"))
                            }
                        }
                        if let cookTime = recipe.cookTimeMinutes {
                            VStack {
                                Text("\(cookTime)")
                                    .font(.custom("Playfair9pt-SemiBold", size: 18))
                                Text("Cook")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundColor(Color("GraniteGray"))
                            }
                        }
                        VStack {
                            Text(recipe.servings)
                                .font(.custom("Playfair9pt-SemiBold", size: 18))
                            Text("Servings")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundColor(Color("GraniteGray"))
                        }
                    }
                    .padding(.vertical, 10)

                    // Description
                    if let description = recipe.description {
                        Text(description)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(Color("GraniteGray"))
                    }

                    // Ingredients
                    if !recipe.ingredients.isEmpty {
                        Text("Ingredients")
                            .font(.custom("Playfair9pt-SemiBold", size: 20))
                            .padding(.top, 10)

                        ForEach(recipe.ingredients, id: \.self) { ingredient in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color("Orange"))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(ingredient)
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                        }
                    }

                    // Instructions
                    if !recipe.instructions.isEmpty {
                        Text("Instructions")
                            .font(.custom("Playfair9pt-SemiBold", size: 20))
                            .padding(.top, 10)

                        ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundColor(Color("Orange"))
                                    .frame(width: 24, alignment: .leading)
                                Text(instruction)
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.clearImport()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.saveRecipe() {
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Create Recipe View

struct CreateRecipeView: View {
    @StateObject private var viewModel = CreateRecipeViewModel()
    @FocusState private var focusedField: CreateRecipeField?
    @State private var showingCamera = false
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?
    @State private var navigateToPreview = false
    @Environment(\.dismiss) private var dismiss

    // Callback to switch to My Recipes tab
    var switchToMyRecipes: (() -> Void)?

    // Edit mode support
    var initialRecipe: RecipeDetail? = nil
    var isEditMode: Bool = false
    var onUpdate: ((RecipeDetail, [UIImage]) -> Void)? = nil  // Returns updated recipe and new photos

    enum CreateRecipeField {
        case title, description, ingredients, instructions, prep, cook, servings, notes
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                CreateRecipeTextField(
                    title: "Title",
                    placeholder: "Give your recipe a name",
                    text: $viewModel.title
                )
                .focused($focusedField, equals: .title)

                // Description
                CreateRecipeTextEditor(
                    title: "Description",
                    placeholder: "Describe your recipe in a few words (e.g., quick, family-favorite, or festive)",
                    text: $viewModel.description,
                    
                )
                .focused($focusedField, equals: .description)

                // Ingredients
                CreateRecipeTextEditor(
                    title: "Ingredients",
                    placeholder: "Add or paste here all the ingredients\n(one per line)",
                    text: $viewModel.ingredientsText,
                 
                )
                .focused($focusedField, equals: .ingredients)

                // Instructions
                CreateRecipeTextEditor(
                    title: "Instructions",
                    placeholder: "Describe each step of the process (e.g., Preheat oven to 350°F)\n(one step per line)",
                    text: $viewModel.instructionsText,
                
                )
                .focused($focusedField, equals: .instructions)

                // Time & Servings Row
                HStack {
                    // Servings
                    HStack(spacing: 10) {
                        Button(action: {
                            if let current = Int(viewModel.servings), current > 1 {
                                viewModel.servings = "\(current - 1)"
                            }
                        }) {
                            Image("minusIcon")
                                .resizable()
                                .frame(width: 33, height: 33)
                        }
                        
                        VStack(spacing: 0) {
                            Text(viewModel.servings.isEmpty ? "2" : viewModel.servings)
                                .font(.custom("Playfair9pt-Regular", size: 20))
                            Text("servings")
                                .font(.custom("Playfair9pt-Regular", size: 18))
                        }
                        
                        Button(action: {
                            if let current = Int(viewModel.servings) {
                                viewModel.servings = "\(current + 1)"
                            } else {
                                viewModel.servings = "3"
                            }
                        }) {
                            Image("plusIcon")
                                .resizable()
                                .frame(width: 33, height: 33)
                        }
                    }
                    Spacer()
                    
                    // Prep & Cook
                    HStack(spacing: 20) {
                    // Prep Time
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Prep")
                                .font(.custom("Playfair9pt-Regular", size: 20))
                            Image("timerIcon")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 24, height: 24)
                                .foregroundColor(Color("GraniteGray"))
                        }
                        
                        TextField("mins", text: $viewModel.prepTime)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .focused($focusedField, equals: .prep)
                            .frame(width: 72, height: 35)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color("DarkSilver"), lineWidth: 1)
                            )
                    }
                    
                    // Cook Time
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Cook")
                                .font(.custom("Playfair9pt-Regular", size: 20))
                            Image("timerIcon")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 24, height: 24)
                                .foregroundColor(Color("GraniteGray"))
                        }
                        
                        TextField("mins", text: $viewModel.cookTime)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .focused($focusedField, equals: .cook)
                            .frame(width: 72, height: 35)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color("DarkSilver"), lineWidth: 1)
                            )
                    }
                    }
                }
              

                // Notes & Tips
                CreateRecipeTextEditor(
                    title: "Notes & Tips",
                    placeholder: "Add any tips, tricks, or substitutions",
                    text: $viewModel.notes,
                  
                )
                .focused($focusedField, equals: .notes)

                // Photo Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Photo")
                        .font(.custom("Playfair9pt-Regular", size: 24))

                    // Photo Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 18),
                          GridItem(.flexible(), spacing: 18),
                        GridItem(.flexible())
                    ], spacing: 18) {
                        ForEach(0..<6, id: \.self) { index in
                            if index < viewModel.photoImages.count {
                                // Show photo
                                Image(uiImage: viewModel.photoImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 110, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        Button(action: {
                                            viewModel.removePhoto(at: index)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.black.opacity(0.5)))
                                        }
                                        .padding(4),
                                        alignment: .topTrailing
                                    )
                            } else {
                                // Empty placeholder
                                Button(action: {
                                    if index == viewModel.photoImages.count {
                                        showingPhotoOptions = true
                                    }
                                }) {
                                    VStack(spacing: 8) {
                                        Image("addPhotoIcon")
                                            .resizable()
                                            .renderingMode(.template)
                                            .frame(width: 24, height: 24)
                                            .foregroundColor(Color("GraniteGray"))

                                        Text("\(index + 1)")
                                            .font(.custom("OpenSans-Regular", size: 14))
                                            .foregroundColor(Color("GraniteGray"))
                                    }
                                    .frame(width: 110, height: 100)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color("DarkSilver"), lineWidth: 1)
                                    )
                                }
                                .disabled(index != viewModel.photoImages.count)
                            }
                        }
                    }
                }

                // Error Message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.red)
                }

                // Preview & Save Button (or Update Preview in edit mode)
                HStack {
                    Spacer()
                    Button(action: {
                        if isEditMode {
                            // In edit mode, pass the updated recipe and any new photos back
                            let updatedRecipe = viewModel.toRecipeDetail()
                            // Make deep copy of images BEFORE passing to callback to avoid memory issues
                            let copiedPhotos: [UIImage] = viewModel.photoImages.compactMap { image in
                                guard let data = image.jpegData(compressionQuality: 0.8),
                                      let copy = UIImage(data: data) else {
                                    return nil
                                }
                                return copy
                            }
                            onUpdate?(updatedRecipe, copiedPhotos)
                        } else {
                            navigateToPreview = true
                        }
                    }) {
                        Text(isEditMode ? "Update Preview" : "Preview & Save")
                            .font(.custom("OpenSans-SemiBold", size: 18))
                            .foregroundColor(.white)
                            .frame(width: isEditMode ? 180 : 164, height: 45)
                            .background(Color("Orange"))
                            .cornerRadius(10)
                    }
                    .disabled(!viewModel.isValid)
                    Spacer()
                }
                .padding(.top, 10)
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .onTapGesture {
            focusedField = nil
        }
        .onAppear {
            // Initialize from recipe if in edit mode
            if let recipe = initialRecipe {
                viewModel.initializeFrom(recipe)
            }
        }
        .navigationDestination(isPresented: $navigateToPreview) {
            RecipeDetailView(
                recipe: viewModel.toRecipeDetail(),
                mode: .preview,
                pendingPhotos: viewModel.photoImages,
                onSave: {
                    // Get ALL data from shared storage - no closure parameters!
                    let savedData = PendingSaveDataStorage.shared.retrieve()
                    guard let recipeDetail = savedData.recipe else {
                        return false
                    }
                    return await viewModel.saveRecipe(from: recipeDetail, photos: savedData.photos)
                },
                onAddMoreRecipes: {
                    // Pop to root - reset state and dismiss
                    viewModel.reset()
                    PendingSaveDataStorage.shared.clear()
                    navigateToPreview = false
                },
                onGoToMyRecipes: {
                    PendingSaveDataStorage.shared.clear()
                    navigateToPreview = false
                    switchToMyRecipes?()
                }
            )
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 6 - viewModel.photoImages.count,
            matching: .images
        )
        .confirmationDialog("Add Photo", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                viewModel.photoImages.append(image)
                capturedImage = nil
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.photoImages.append(image)
                    }
                }
                selectedPhotoItems = []
            }
        }
    }
}

// MARK: - Create Recipe Text Field

struct CreateRecipeTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Playfair9pt-Regular", size: 24))

            ZStack(alignment: .topLeading) {
                           if text.isEmpty {
                               Text(placeholder)
                                   .font(.custom("OpenSans-Regular", size: 14))
                                   .foregroundColor(Color("DarkSilver"))
                                   .padding(.horizontal, 16)
                                   .padding(.vertical, 12)
                           }
                           
                           TextField("", text: $text, axis: .vertical)
                               .font(.custom("OpenSans-Regular", size: 14))
                               .foregroundColor(.primary)
                               .lineLimit(1...5)
                               .padding(.horizontal, 16)
                               .padding(.vertical, 12)
                       }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color("DarkSilver"), lineWidth: 1)
            )
        }
    }
}

// MARK: - Create Recipe Text Editor

struct CreateRecipeTextEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String
  

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Playfair9pt-Regular", size: 24))

            ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholder)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundColor(Color("DarkSilver"))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            
                            TextField("", text: $text, axis: .vertical)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundColor(.primary)
                                .lineLimit(1...10)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color("DarkSilver"), lineWidth: 1)
            )
        }
    }
}

// MARK: - Create Recipe Preview View

struct CreateRecipePreviewView: View {
    @ObservedObject var viewModel: CreateRecipeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    Text(viewModel.title)
                        .font(.custom("Playfair9pt-SemiBold", size: 24))

                    // Time info
                    if viewModel.prepTimeMinutes != nil || viewModel.cookTimeMinutes != nil {
                        HStack(spacing: 20) {
                            if let prep = viewModel.prepTimeMinutes {
                                VStack {
                                    Text("\(prep)")
                                        .font(.custom("Playfair9pt-SemiBold", size: 18))
                                    Text("Prep")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundColor(Color("GraniteGray"))
                                }
                            }
                            if let cook = viewModel.cookTimeMinutes {
                                VStack {
                                    Text("\(cook)")
                                        .font(.custom("Playfair9pt-SemiBold", size: 18))
                                    Text("Cook")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundColor(Color("GraniteGray"))
                                }
                            }
                            if let servings = viewModel.servingsInt {
                                VStack {
                                    Text("\(servings)")
                                        .font(.custom("Playfair9pt-SemiBold", size: 18))
                                    Text("Servings")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundColor(Color("GraniteGray"))
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }

                    // Description
                    if !viewModel.description.isEmpty {
                        Text(viewModel.description)
                            .font(.custom("Playfair9pt-Regular", size: 24))
                            .foregroundColor(Color("GraniteGray"))
                    }

                    // Ingredients
                    if !viewModel.ingredientsList.isEmpty {
                        Text("Ingredients")
                            .font(.custom("Playfair9pt-SemiBold", size: 20))
                            .padding(.top, 10)

                        ForEach(viewModel.ingredientsList, id: \.self) { ingredient in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color("Orange"))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(ingredient)
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                        }
                    }

                    // Instructions
                    if !viewModel.instructionsList.isEmpty {
                        Text("Instructions")
                            .font(.custom("Playfair9pt-SemiBold", size: 20))
                            .padding(.top, 10)

                        ForEach(Array(viewModel.instructionsList.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundColor(Color("Orange"))
                                    .frame(width: 24, alignment: .leading)
                                Text(instruction)
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Notes
                    if !viewModel.notes.isEmpty {
                        VStack(spacing: 10) {
                            Text("Notes & Tips")
                                .font(.custom("Playfair9pt-SemiBold", size: 20))

                            Text(viewModel.notes)
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color("PeachCream"))
                        .cornerRadius(15)
                    }
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.saveRecipe() {
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSaving)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddNewRecipeView()
}
