import MapKit
import SwiftUI

struct LocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @StateObject private var searchCompleter = LocationSearchCompleter()
    @State private var searchText = ""
    @State private var selectedName: String?
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @FocusState private var isSearchFocused: Bool

    let onConfirm: (String, Double, Double) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mapSection

                searchBar

                List {
                    if selectedName != nil {
                        selectedLocationRow
                    }

                    currentLocationButton

                    if !searchCompleter.results.isEmpty {
                        Section {
                            ForEach(searchCompleter.results, id: \.self) { completion in
                                resultRow(completion)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("位置", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("确认", comment: "")) {
                        if let name = selectedName, let coord = selectedCoordinate {
                            onConfirm(name, coord.latitude, coord.longitude)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedName == nil)
                }
            }
        }
    }

    private var mapSection: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let coord = selectedCoordinate {
                    Marker(selectedName ?? "", coordinate: coord)
                }
            }
            .onTapGesture { position in
                guard let coordinate = proxy.convert(position, from: .local) else { return }
                isSearchFocused = false
                selectCoordinate(coordinate)
            }
        }
        .frame(minHeight: 260, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)
            TextField(NSLocalizedString("搜索位置", comment: ""), text: $searchText)
                .font(.system(size: 16, design: .rounded))
                .focused($isSearchFocused)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchCompleter.update(query: "")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.elevatedSurface)
        .onChange(of: searchText) { _, newValue in
            searchCompleter.update(query: newValue)
        }
    }

    @ViewBuilder
    private var selectedLocationRow: some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(AppTheme.accent)
            Text(selectedName ?? "")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Image(systemName: "checkmark")
                .foregroundStyle(AppTheme.accent)
                .fontWeight(.semibold)
        }
    }

    private var currentLocationButton: some View {
        Button {
            useCurrentLocation()
        } label: {
            Label(NSLocalizedString("使用当前位置", comment: ""), systemImage: "location.fill")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.accent)
        }
    }

    private func resultRow(_ completion: MKLocalSearchCompletion) -> some View {
        Button {
            isSearchFocused = false
            resolveCompletion(completion)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(completion.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                if !completion.subtitle.isEmpty {
                    Text(completion.subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func useCurrentLocation() {
        guard let location = appViewModel.locationService.latestLocation else {
            appViewModel.locationService.refreshCurrentLocation()
            return
        }
        Task {
            let geocoder = CLGeocoder()
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            let name = placemarks?.first?.name ?? placemarks?.first?.locality ?? NSLocalizedString("当前位置", comment: "")
            selectedName = name
            selectedCoordinate = location.coordinate
            cameraPosition = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            ))
        }
    }

    private func resolveCompletion(_ completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let title = completion.title
        Task {
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else { return }
            selectedName = title
            selectedCoordinate = item.placemark.coordinate
            cameraPosition = .region(MKCoordinateRegion(
                center: item.placemark.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            ))
        }
    }

    private func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        selectedCoordinate = coordinate
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        ))
        Task {
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            selectedName = placemarks?.first?.name ?? placemarks?.first?.locality ?? String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        }
    }
}

@MainActor
private final class LocationSearchCompleter: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        if query.isEmpty {
            results = []
        } else {
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {}
}
