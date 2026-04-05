import MapKit
import Photos
import PhotosUI
import SwiftUI
import UIKit
import ImageIO

enum MealCaptureMode {
    case camera
    case photoLibrary
    case timeOnly
    case editTime
    case addPhoto
    case editPhoto
    case editRecord
}

struct MealEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var draft: MealEntry
    @State private var selectedImages: [SelectedMealImage] = []
    @State private var pickerSource: UIImagePickerController.SourceType?
    @State private var showingImagePicker = false
    @State private var showingPhotoLibraryPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showingPhotoSourcePopover = false
    @State private var didApplyInitialMode = false
    @State private var logsExistenceOnly: Bool
    @State private var showingLocationPicker = false
    @State private var showingDeleteMealConfirmation = false

    let baseDate: Date
    let preferredSource: MealCaptureMode
    let canDelete: Bool
    let isEditable: Bool
    let onSave: (MealEntry, [UIImage]) -> Void
    let onDelete: () -> Void

    init(
        entry: MealEntry,
        baseDate: Date,
        preferredSource: MealCaptureMode,
        canDelete: Bool,
        isEditable: Bool,
        onSave: @escaping (MealEntry, [UIImage]) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: entry)
        _logsExistenceOnly = State(initialValue: entry.status == .logged && entry.time == nil)
        self.baseDate = baseDate
        self.preferredSource = preferredSource
        self.canDelete = canDelete
        self.isEditable = isEditable
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if draft.mealKind == .custom {
                        TextField(NSLocalizedString("名称", comment: ""), text: Binding(
                            get: { draft.customTitle ?? "" },
                            set: { draft.customTitle = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isEditable)
                    }

                    timeSection
                    photoSection
                    noteSection
                    locationSection
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(draft.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        onSave(normalizedDraft, selectedImages.map(\.image))
                        dismiss()
                    }
                    .disabled(!isEditable)
                }
                if canDelete {
                    ToolbarItem(placement: .bottomBar) {
                        Button(NSLocalizedString("删除餐次", comment: ""), role: .destructive) {
                            showingDeleteMealConfirmation = true
                        }
                        .tint(.red)
                    }
                }
            }
            .onAppear {
                applyInitialModeIfNeeded()
            }
            .onChange(of: photoPickerItems) { _, newItems in
                Task { await loadSelectedPhotoItems(newItems) }
            }
            .sheet(isPresented: $showingImagePicker) {
                if let pickerSource {
                    ImagePicker(
                        sourceType: pickerSource,
                        fallbackLocationProvider: { appViewModel.locationService.latestLocation }
                    ) { selectedImage in
                        if let selectedImage {
                            let hadPhotosBeforeAppending = allPhotoCount > 0
                            selectedImages.append(selectedImage)
                            draft.status = .logged
                            draft.time = normalizedPickedDate(selectedImage.capturedAt) ?? draft.time ?? defaultLoggedTime
                            logsExistenceOnly = false
                            Task {
                                await applyAutomaticLocationIfNeeded(
                                    from: selectedImage.location,
                                    shouldAutofillFromFirstPhoto: !hadPhotosBeforeAppending
                                )
                            }
                        }
                    }
                }
            }
            .photosPicker(
                isPresented: $showingPhotoLibraryPicker,
                selection: $photoPickerItems,
                maxSelectionCount: nil,
                matching: .images,
                preferredItemEncoding: .current
            )
            .alert(NSLocalizedString("删除餐次？", comment: ""), isPresented: $showingDeleteMealConfirmation) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("删除餐次", comment: ""), role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("此操作会删除整个餐次，且无法撤销。", comment: ""))
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(NSLocalizedString("仅记录有/无", comment: ""), isOn: $logsExistenceOnly)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .tint(timeAccent)
                .disabled(!isEditable)

            if !logsExistenceOnly {
                Text(NSLocalizedString("时间", comment: ""))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)

                VStack(spacing: 12) {
                    Text(appViewModel.displayedClockTime(
                        for: draft.time ?? defaultLoggedTime,
                        recordedTimeZoneIdentifier: draft.timeZoneIdentifier
                    ))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(timeAccent)
                        .monospacedDigit()

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { draft.time ?? defaultLoggedTime },
                            set: {
                                draft.time = $0
                                draft.status = .logged
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.timeZone, appViewModel.displayedTimeZone(for: draft.timeZoneIdentifier))
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allPhotoCount == 0 {
                photoSourceTrigger {
                    DashedMealPhotoPlaceholder(title: NSLocalizedString("添加照片", comment: ""))
                        .frame(height: 220)
                }
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(draft.photoURLs, id: \.self) { photoURL in
                                mealPhotoTile {
                                    PhotoContentView(photoURL: photoURL, contentMode: .fill)
                                } removeAction: {
                                    draft.photoURLs.removeAll { $0 == photoURL }
                                }
                            }

                            ForEach(selectedImages) { selectedImage in
                                mealPhotoTile {
                                    Image(uiImage: selectedImage.image)
                                        .resizable()
                                        .scaledToFill()
                                } removeAction: {
                                    selectedImages.removeAll { $0.id == selectedImage.id }
                                }
                            }
                        }
                        .frame(minWidth: geometry.size.width, alignment: .center)
                        .padding(.vertical, 2)
                    }
                }
                .frame(height: 192)

                photoSourceTrigger {
                    Text(NSLocalizedString("添加照片", comment: ""))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func photoSourceTrigger<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button {
            presentPhotoSourceOptions()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .popover(
            isPresented: $showingPhotoSourcePopover,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            VStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(NSLocalizedString("拍照", comment: "")) {
                        showingPhotoSourcePopover = false
                        openPicker(.camera)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Button(NSLocalizedString("选择相册照片", comment: "")) {
                    showingPhotoSourcePopover = false
                    showingPhotoLibraryPicker = true
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(14)
            .frame(width: 250)
            .background(AppTheme.background)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func mealPhotoTile<Content: View>(
        @ViewBuilder content: () -> Content,
        removeAction: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            content()
                .frame(width: 132, height: 176)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button {
                removeAction()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white, Color.black.opacity(0.45))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .disabled(!isEditable)
        }
    }

    private var noteSection: some View {
        RecordNoteSection(note: Binding(
            get: { draft.note ?? "" },
            set: { draft.note = $0.isEmpty ? nil : $0 }
        ))
        .disabled(!isEditable)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("位置", comment: ""))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            if let locationName = draft.locationName {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text(locationName)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    if isEditable {
                        Button {
                            draft.locationName = nil
                            draft.latitude = nil
                            draft.longitude = nil
                            draft.isLocationManuallyEdited = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture {
                    guard isEditable else { return }
                    showingLocationPicker = true
                }
            } else {
                Button {
                    showingLocationPicker = true
                } label: {
                    Label(NSLocalizedString("添加位置", comment: ""), systemImage: "mappin.circle")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(AppTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isEditable)
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerSheet { name, lat, lon in
                draft.locationName = name
                draft.latitude = lat
                draft.longitude = lon
                draft.isLocationManuallyEdited = true
            }
        }
    }

    private var normalizedDraft: MealEntry {
        var entry = draft
        let trimmed = entry.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.mealKind == .custom {
            entry.customTitle = trimmed?.isEmpty == false ? trimmed : NSLocalizedString("加餐", comment: "")
        }

        let trimmedNote = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmedNote?.isEmpty == false ? trimmedNote : nil

        if logsExistenceOnly {
            entry.status = .logged
            entry.time = nil
            entry.timeZoneIdentifier = nil
        } else if !selectedImages.isEmpty || !entry.photoURLs.isEmpty || entry.time != nil || preferredSource == .editRecord {
            entry.status = .logged
            entry.time = entry.time ?? defaultLoggedTime
            entry.timeZoneIdentifier = appViewModel.displayedTimeZone(for: entry.timeZoneIdentifier).identifier
        } else {
            entry.status = .empty
            entry.time = nil
            entry.photoURLs = []
            entry.timeZoneIdentifier = nil
            entry.note = nil
            entry.locationName = nil
            entry.latitude = nil
            entry.longitude = nil
            entry.isLocationManuallyEdited = false
        }
        return entry
    }

    private var allPhotoCount: Int {
        draft.photoURLs.count + selectedImages.count
    }

    private var defaultLoggedTime: Date {
        let timeZone = appViewModel.displayedTimeZone(for: draft.timeZoneIdentifier)
        return baseDate.anchoringCurrentClockTime(in: timeZone)
    }

    private var timeAccent: Color {
        switch draft.mealKind {
        case .breakfast: AppTheme.wakeAccent
        case .lunch: AppTheme.accent
        case .dinner: AppTheme.sleepAccent
        case .custom: AppTheme.sunriseAccent
        }
    }

    private func applyInitialModeIfNeeded() {
        guard !didApplyInitialMode else { return }
        didApplyInitialMode = true

        switch preferredSource {
        case .timeOnly, .editTime:
            draft.status = .logged
            draft.time = draft.time ?? defaultLoggedTime
            logsExistenceOnly = false
        case .camera:
            draft.status = .logged
            logsExistenceOnly = false
            openPicker(.camera)
        case .photoLibrary:
            draft.status = .logged
            logsExistenceOnly = false
            showingPhotoLibraryPicker = true
        case .addPhoto, .editPhoto:
            draft.status = .logged
            logsExistenceOnly = false
            presentPhotoSourceOptions()
        case .editRecord:
            if draft.status == .logged && draft.time == nil {
                logsExistenceOnly = true
            }
        }
    }

    private func presentPhotoSourceOptions() {
        guard isEditable else { return }
        DispatchQueue.main.async {
            showingPhotoSourcePopover = true
        }
    }

    private func openPicker(_ source: UIImagePickerController.SourceType) {
        guard isEditable else { return }
        guard source != .camera || UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        if source == .camera {
            switch appViewModel.locationService.permissionState {
            case .authorized:
                appViewModel.locationService.refreshCurrentLocation()
            case .notDetermined:
                appViewModel.locationService.requestAccess()
            case .denied:
                break
            }
        }
        pickerSource = source
        showingImagePicker = true
    }

    @MainActor
    private func loadSelectedPhotoItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        let hadPhotosBeforeAppending = allPhotoCount > 0
        var appendedImages: [SelectedMealImage] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                continue
            }
            let parsedMetadata = metadata(from: data)
            let assetMetadata = await metadata(for: item)
            let mergedMetadata = parsedMetadata.merging(assetMetadata)
            appendedImages.append(
                SelectedMealImage(
                    image: image,
                    capturedAt: mergedMetadata.capturedAt,
                    location: mergedMetadata.location
                )
            )
        }

        if !appendedImages.isEmpty {
            selectedImages.append(contentsOf: appendedImages)
            draft.status = .logged
            draft.time = draft.time ?? normalizedPickedDate(appendedImages.first?.capturedAt) ?? defaultLoggedTime
            logsExistenceOnly = false
            await applyAutomaticLocationIfNeeded(
                from: appendedImages.first?.location,
                shouldAutofillFromFirstPhoto: !hadPhotosBeforeAppending
            )
        }

        photoPickerItems = []
    }

    private func normalizedPickedDate(_ pickedDate: Date?) -> Date? {
        guard let pickedDate else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = appViewModel.displayedTimeZone(for: draft.timeZoneIdentifier)
        let components = calendar.dateComponents([.hour, .minute], from: pickedDate)
        return baseDate.settingTime(
            hour: components.hour ?? 12,
            minute: components.minute ?? 0,
            in: appViewModel.displayedTimeZone(for: draft.timeZoneIdentifier)
        )
    }

    private func metadata(for item: PhotosPickerItem) async -> SelectedMealImage.Metadata {
        guard let itemIdentifier = item.itemIdentifier else {
            return .empty
        }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [itemIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            return .empty
        }
        return SelectedMealImage.Metadata(
            capturedAt: asset.creationDate,
            location: asset.location
        )
    }

    private func metadata(from data: Data) -> SelectedMealImage.Metadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .empty
        }

        return SelectedMealImage.Metadata(
            capturedAt: capturedDate(from: properties),
            location: imageLocation(from: properties)
        )
    }

    @MainActor
    private func applyAutomaticLocationIfNeeded(
        from location: CLLocation?,
        shouldAutofillFromFirstPhoto: Bool
    ) async {
        guard shouldAutofillFromFirstPhoto,
              let location,
              !draft.isLocationManuallyEdited,
              draft.locationName == nil,
              draft.latitude == nil,
              draft.longitude == nil else {
            return
        }

        let coordinateName = formattedCoordinateString(for: location.coordinate)
        draft.locationName = coordinateName
        draft.latitude = location.coordinate.latitude
        draft.longitude = location.coordinate.longitude
        draft.isLocationManuallyEdited = false

        let locationName = await reverseGeocodedName(for: location)
        guard !draft.isLocationManuallyEdited,
              draft.latitude == location.coordinate.latitude,
              draft.longitude == location.coordinate.longitude else {
            return
        }

        draft.locationName = locationName
    }

    private func reverseGeocodedName(for location: CLLocation) async -> String {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let placemark = placemarks?.first
        if let name = placemark?.name, !name.isEmpty {
            return name
        }
        if let locality = placemark?.locality, !locality.isEmpty {
            return locality
        }
        return formattedCoordinateString(for: location.coordinate)
    }

    private func formattedCoordinateString(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    private func imageLocation(from properties: [CFString: Any]) -> CLLocation? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude] as? CLLocationDegrees,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? CLLocationDegrees else {
            return nil
        }

        let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
        let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()
        let signedLatitude = latitudeRef == "S" ? -latitude : latitude
        let signedLongitude = longitudeRef == "W" ? -longitude : longitude
        return CLLocation(latitude: signedLatitude, longitude: signedLongitude)
    }

    private func capturedDate(from properties: [CFString: Any]) -> Date? {
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
            if let parsed = parsedExifDate(dateString, offset: offset) {
                return parsed
            }
        }

        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let dateString = tiff[kCGImagePropertyTIFFDateTime] as? String {
            return parsedExifDate(dateString, offset: nil)
        }

        return nil
    }

    private func parsedExifDate(_ dateString: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let offset, !offset.isEmpty {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            if let parsed = formatter.date(from: dateString + offset) {
                return parsed
            }
        }

        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}

private struct SelectedMealImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let capturedAt: Date?
    let location: CLLocation?

    init(
        image: UIImage,
        capturedAt: Date? = nil,
        location: CLLocation? = nil
    ) {
        self.image = image
        self.capturedAt = capturedAt
        self.location = location
    }

    struct Metadata {
        let capturedAt: Date?
        let location: CLLocation?

        static let empty = Metadata(capturedAt: nil, location: nil)

        func merging(_ fallback: Metadata) -> Metadata {
            Metadata(
                capturedAt: capturedAt ?? fallback.capturedAt,
                location: location ?? fallback.location
            )
        }
    }
}

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let fallbackLocationProvider: () -> CLLocation?
    let onImagePicked: (SelectedMealImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            fallbackLocationProvider: fallbackLocationProvider,
            onImagePicked: onImagePicked
        )
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let fallbackLocationProvider: () -> CLLocation?
        let onImagePicked: (SelectedMealImage?) -> Void

        init(
            fallbackLocationProvider: @escaping () -> CLLocation?,
            onImagePicked: @escaping (SelectedMealImage?) -> Void
        ) {
            self.fallbackLocationProvider = fallbackLocationProvider
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil)
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            let metadata = metadata(from: info, sourceType: picker.sourceType)
            onImagePicked(image.map {
                SelectedMealImage(
                    image: $0,
                    capturedAt: metadata.capturedAt,
                    location: metadata.location
                )
            })
            picker.dismiss(animated: true)
        }

        private func metadata(
            from info: [UIImagePickerController.InfoKey : Any],
            sourceType: UIImagePickerController.SourceType
        ) -> SelectedMealImage.Metadata {
            if let asset = info[.phAsset] as? PHAsset {
                return SelectedMealImage.Metadata(
                    capturedAt: asset.creationDate,
                    location: asset.location
                )
            }

            if let mediaMetadata = info[.mediaMetadata] as? [AnyHashable: Any],
               let location = imageMetadataLocation(from: mediaMetadata) {
                return SelectedMealImage.Metadata(
                    capturedAt: Date(),
                    location: location
                )
            }

            if sourceType == .camera {
                return SelectedMealImage.Metadata(
                    capturedAt: Date(),
                    location: fallbackLocationProvider()
                )
            }

            return .empty
        }

        private func imageMetadataLocation(from metadata: [AnyHashable: Any]) -> CLLocation? {
            guard let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any],
                  let latitude = gps[kCGImagePropertyGPSLatitude as String] as? CLLocationDegrees,
                  let longitude = gps[kCGImagePropertyGPSLongitude as String] as? CLLocationDegrees else {
                return nil
            }

            let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased()
            let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased()

            let signedLatitude = latitudeRef == "S" ? -latitude : latitude
            let signedLongitude = longitudeRef == "W" ? -longitude : longitude
            return CLLocation(latitude: signedLatitude, longitude: signedLongitude)
        }
    }
}
