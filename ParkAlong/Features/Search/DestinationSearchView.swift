import SwiftUI

struct DestinationSearchView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @State private var query = ""
    @State private var recentQueries: [String] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            searchBody
                .navigationTitle("Search")
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
                    searchField
                }
        }
        .adaptiveToolbarMinimizationBehavior()
        .onAppear {
            fieldFocused = true
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var searchField: some View {
        TextField("Place, address, or parking", text: $query)
            .textFieldStyle(.plain)
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .adaptiveGlassSurface(cornerRadius: 14, isInteractive: true)
            .focused($fieldFocused)
            .submitLabel(.search)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
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

    private var searchBody: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyQuerySections
            } else {
                loadingSection
                failureSection
                resultSections
                emptyResultsSection
            }
        }
        .listStyle(.insetGrouped)
        .overlay(alignment: .top) {
            if viewModel.searchState == .loading, !viewModel.searchResults.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Updating results")
                        .font(.footnote.weight(.medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .adaptiveGlassSurface(cornerRadius: 16)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("search-loading")
                .accessibilityLabel("Updating results")
            }
        }
        .accessibilityIdentifier("search-results-container")
    }

    @ViewBuilder
    private var emptyQuerySections: some View {
        Section {
            Button {
                Task {
                    await viewModel.useCurrentLocation()
                    dismiss()
                }
            } label: {
                Label("Current location", systemImage: "location.fill")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("search-current-location")

            Button {
                Task {
                    viewModel.isSearching = false
                    dismiss()
                    await viewModel.refresh(force: true)
                }
            } label: {
                Label("Search this map area", systemImage: "map")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("search-this-area")
        }

        if !recentQueries.isEmpty {
            Section("Recent") {
                ForEach(recentQueries, id: \.self) { item in
                    Button {
                        query = item
                    } label: {
                        Label(item, systemImage: "clock")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
            }
        } else {
            Section {
                ContentUnavailableView(
                    "Find a place or parking",
                    systemImage: "magnifyingglass",
                    description: Text("Search for an address, landmark, or ParkAlong parking near the visible map.")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Find a place or parking. Search for an address, landmark, or ParkAlong parking near the visible map.")
                .accessibilityIdentifier("search-idle")
            }
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        if viewModel.searchState == .loading, viewModel.searchResults.isEmpty {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching places and parking")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("search-loading")
                .accessibilityLabel("Searching places and parking")
            }
        }
    }

    @ViewBuilder
    private var failureSection: some View {
        if case .failed(let message) = viewModel.searchState {
            Section {
                ContentUnavailableView {
                    Label("Search unavailable", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task { await resolve(query) }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("search-retry")
                }
                .accessibilityIdentifier("search-error")
            }
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        let places = viewModel.searchResults.filter { $0.kind != .parking }
        let parking = viewModel.searchResults.filter { $0.kind == .parking }

        if !places.isEmpty {
            Section("Places") {
                ForEach(places) { result in
                    resultRow(result, kindLabel: "Place", systemImage: "mappin.and.ellipse")
                }
            }
        }

        if !parking.isEmpty {
            Section("ParkAlong parking") {
                ForEach(parking) { result in
                    resultRow(result, kindLabel: "ParkAlong parking", systemImage: "parkingsign.circle.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyResultsSection: some View {
        if viewModel.searchState == .empty, viewModel.searchResults.isEmpty {
            Section {
                ContentUnavailableView.search(text: query)
                    .accessibilityIdentifier("search-empty")
            }
        }
    }

    private func resultRow(_ result: ParkingDestination, kindLabel: String, systemImage: String) -> some View {
        Button {
            remember(query)
            Task { await viewModel.chooseDestination(result) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(result.kind == .parking ? Color.accentColor : Color.secondary)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(result.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(kindLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(result.kind == .parking ? Color.accentColor : Color.secondary)
                        .accessibilityIdentifier(result.kind == .parking ? "search-result-kind-parking" : "search-result-kind-place")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("\(result.name), \(result.subtitle), \(kindLabel)")
        .accessibilityHint(result.kind == .parking ? "Shows this parking location" : "Shows this place on the map")
        .accessibilityIdentifier(identifier(for: result))
    }

    private func identifier(for result: ParkingDestination) -> String {
        if result.id == "flinders" {
            return "search-result-flinders"
        }
        if result.kind == .parking {
            return "search-result-parking-\(result.id)"
        }
        return "search-result-\(result.id)"
    }

    private func remember(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentQueries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentQueries.insert(trimmed, at: 0)
        if recentQueries.count > 6 {
            recentQueries = Array(recentQueries.prefix(6))
        }
    }

    private func beginSearch(for value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask = Task { await viewModel.search(query: "") }
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await resolve(trimmed)
        }
    }

    @MainActor
    private func resolve(_ value: String) async {
        await viewModel.search(query: value)
    }
}
