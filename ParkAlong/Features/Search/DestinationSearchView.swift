import SwiftUI

struct DestinationSearchView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @State private var query = ""
    @State private var isResolving = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Find a destination",
                        systemImage: "map",
                        description: Text("Search for a place or address in central Melbourne.")
                    )
                } else if isResolving {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Searching places")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Searching places")
                } else if viewModel.searchResults.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(viewModel.searchResults) { result in
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
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityLabel("\(result.name), \(result.subtitle)")
                        .accessibilityIdentifier(identifier(for: result))
                    }
                    .listStyle(.plain)
                }
            }
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
                    .adaptiveGlassSurface(cornerRadius: 14)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("destination-search-field")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .onChange(of: query) { _, newValue in
                        beginSearch(for: newValue)
                    }
                    .onSubmit {
                        searchTask?.cancel()
                        searchTask = Task { await resolve(query) }
                    }
            }
        }
        .adaptiveToolbarMinimizationBehavior()
        .onAppear {
            fieldFocused = true
        }
        .onDisappear {
            searchTask?.cancel()
            viewModel.searchResults = []
        }
    }

    private func identifier(for result: ParkingDestination) -> String {
        if result.id == "flinders" || result.name.localizedCaseInsensitiveCompare("Flinders Street Station") == .orderedSame {
            return "search-result-flinders"
        }
        return "search-result-\(result.id)"
    }

    private func beginSearch(for value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isResolving = false
            viewModel.searchResults = []
            return
        }

        isResolving = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await resolve(trimmed)
        }
    }

    @MainActor
    private func resolve(_ value: String) async {
        isResolving = true
        await viewModel.search(query: value)
        guard !Task.isCancelled else { return }
        isResolving = false
    }
}
