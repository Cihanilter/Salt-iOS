

import SwiftUI
import PhotosUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingSignOutAlert = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // Header with gradient
                profileHeader

                // Content
                VStack(spacing: 16) {
                    // Stats Card
                    statsCard

                    // About Me Section
                    aboutMeSection

                    if viewModel.userProfile?.location != nil || viewModel.memberSince != nil || viewModel.email != nil {
                        // Contact Info
                        contactInfoSection
                    }

                    // Favorite Cuisines
                    favoriteCuisinesSection

                    // Sign Out Button
                    signOutButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $viewModel.isEditing) {
            EditProfileView(viewModel: viewModel)
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    // MARK: - Profile Placeholder

    private var profilePlaceholder: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 96, height: 96)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color("GraniteGray"))
            )
            .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // Gradient background
                LinearGradient(
                    stops: [
                        .init(color: Color("OutrageousOrange"), location: 0.05),
                        .init(color: Color("CoralColor"), location: 3.2)
                               ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 128)
                
             
                

                // Profile content
                HStack(alignment: .bottom) {
                    // Profile Photo
                    ZStack(alignment: .bottomTrailing) {
                        // Photo container with white border
                        Circle()
                            .fill(Color.white)
                            .frame(width: 96, height: 96)
                            .overlay(
                                Group {
                                    if let imageUrl = viewModel.userProfile?.profileImageUrl,
                                       let url = URL(string: imageUrl) {
                                        CachedAsyncImage(url: url) { phase in
                                            switch phase {
                                            case .empty:
                                                ProgressView()
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            case .failure:
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 40))
                                                    .foregroundColor(Color("GraniteGray"))
                                            @unknown default:
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 40))
                                                    .foregroundColor(Color("GraniteGray"))
                                            }
                                        }
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(Color("GraniteGray"))
                                    }
                                }
                                .frame(width: 88, height: 88)
                                .clipShape(Circle())
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                            )


                        // Camera button with PhotosPicker
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(Color("Orange"))
                                    .frame(width: 28, height: 28)

                                if viewModel.isUploadingImage {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .disabled(viewModel.isUploadingImage)
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await viewModel.uploadProfileImage(image)
                                }
                            }
                        }
                    }
                    Spacer()
                    
                    // Edit Profile Button
                    Button(action: {
                        viewModel.startEditing()
                    }) {
                        Text("Edit Profile")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                        Capsule()
                                            .fill(Color.white)
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                    )
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 16)
                .offset(y: 50)
            }
            .padding(.bottom, 60)

            // Name and Bio
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.displayName)
                    .font(.custom("OpenSans-Regular", size: 24))
                    .foregroundColor(.primary)

                if let bio = viewModel.userProfile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("GrayText"))
                        .lineSpacing(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
                       .padding(.horizontal, 16)
                       .padding(.top, 12)
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text("\(viewModel.recipesCount)")
                    .font(.custom("OpenSans-SemiBold", size: 30))
                    .foregroundColor(Color("Orange"))
                Text("Recipes Created")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GrayText"))
            }
            Spacer()
        }
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
        .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 1)
    }

    // MARK: - About Me Section

    private var aboutMeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Me")
                .font(.custom("OpenSans-Regular", size: 16))

            if let aboutMe = viewModel.userProfile?.aboutMe, !aboutMe.isEmpty {
                Text(aboutMe)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GrayText"))
            } else {
                Text("Tell us about yourself and your cooking journey...")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GrayText"))
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
        .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 1)
    }

    // MARK: - Contact Info Section

    private var contactInfoSection: some View {
        VStack(spacing: 0) {
            // Location
            if let location = viewModel.userProfile?.location, !location.isEmpty {
                ProfileInfoRow(
                    icon: "locationIcon",
                    title: "Location",
                    value: location
                )
                Divider()
                
            }

            // Member Since
            if let memberSince = viewModel.memberSince {
                ProfileInfoRow(
                    icon: "calendarIcon",
                    title: "Member Since",
                    value: memberSince
                )
                Divider()
            }

            // Email
            if let email = viewModel.email {
                ProfileInfoRow(
                    icon: "emailIcon",
                    title: "Email",
                    value: email
                )
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
        .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 1)
    }

    // MARK: - Favorite Cuisines Section

    private var favoriteCuisinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorite Cuisines")
                .font(.custom("OpenSans-Regular", size: 16))

            if let cuisines = viewModel.userProfile?.favoriteCuisines, !cuisines.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(cuisines, id: \.self) { cuisine in
                        CuisineTag(name: cuisine)
                    }
                }
            } else {
                Text("Add your favorite cuisines to personalize your experience")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(Color("GrayText"))
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
        .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 1)
    }

    // MARK: - Sign Out Button

    private var signOutButton: some View {
        Button(action: { showingSignOutAlert = true }) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .font(.custom("OpenSans-Regular", size: 16))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.red.opacity(0.1)))
            .cornerRadius(16)
 }
        .padding(.top, 10)
    }
}

// MARK: - Profile Info Row

struct ProfileInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Image(icon)
            .resizable()
            .renderingMode(.template)
            .frame(width: 22, height: 22)
            .foregroundColor(Color("OutrageousOrange"))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(Color("GrayText"))
                Text(value)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.primary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    private var iconSystemName: String {
        switch icon {
        case "location": return "mappin.circle"
        case "calendar": return "calendar"
        case "envelope": return "envelope"
        default: return icon
        }
    }
}

// MARK: - Cuisine Tag

struct CuisineTag: View {
    let name: String
    var isSelected: Bool = false

    var body: some View {
        Text(name)
            .font(.custom("OpenSans-Regular", size: 12))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color("LightOlive"))
            .cornerRadius(20)
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color("OrangeRed"), lineWidth: 2)
                    }
                }
            )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Full Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Full Name")
                            .font(.custom("OpenSans-Regular", size: 24))
                        TextField("Your name", text: $viewModel.editFullName)
                            .font(.custom("OpenSans-Regular", size: 24))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }

                    // Bio (short tagline under name)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bio")
                            .font(.custom("OpenSans-Regular", size: 14))
                        Text("Short tagline shown under your name")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundColor(Color("GrayText"))
                        TextField("e.g., Home cook & food lover", text: $viewModel.editBio)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }

                    // About Me (longer description)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Me")
                            .font(.custom("OpenSans-Regular", size: 14))
                        Text("Tell us about yourself and your cooking journey")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundColor(Color("GrayText"))
                        TextEditor(text: $viewModel.editAboutMe)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .frame(minHeight: 100)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }

                    // Location
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location")
                            .font(.custom("OpenSans-Regular", size: 14))
                        TextField("City, Country", text: $viewModel.editLocation)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }

                    // Favorite Cuisines
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Favorite Cuisines")
                            .font(.custom("OpenSans-Regular", size: 14))

                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.availableCuisines, id: \.self) { cuisine in
                                Button(action: { viewModel.toggleCuisine(cuisine) }) {
                                    CuisineTag(
                                        name: cuisine,
                                        isSelected: viewModel.editFavoriteCuisines.contains(cuisine)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelEditing()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.saveProfile() {
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

// MARK: - Preview

#Preview {
    ProfileView()
}
