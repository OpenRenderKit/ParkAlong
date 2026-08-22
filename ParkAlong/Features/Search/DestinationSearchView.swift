import SwiftUI

struct DestinationSearchView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty && viewModel.searchResults.isEmpty {
                    Text("No matching places in central Melbourne.")
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.searchResults) { result in
                    Button {
                        Task { await viewModel.chooseDestination(result) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(result.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("\(result.name), \(result.subtitle)")
                    .accessibilityIdentifier(identifier(for: result))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.isSearching = false
                        dismiss()
                    }
                    .frame(minHeight: 44)
                }
            }
            .safeAreaInset(edge: .top) {
                TextField("Place or address", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("destination-search-field")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .onChange(of: query) { _, newValue in
                        Task { await viewModel.search(query: newValue) }
                    }
                    .onSubmit {
                        Task { await viewModel.search(query: query) }
                    }
            }
        }
        .onAppear {
            fieldFocused = true
        }
        .onDisappear {
            viewModel.searchResults = []
        }
    }

    private func identifier(for result: ParkingDestination) -> String {
        if result.id == "flinders" || result.name.localizedCaseInsensitiveCompare("Flinders Street Station") == .orderedSame {
            return "search-result-flinders"
        }
        return "search-result-\(result.id)"
    }
}
