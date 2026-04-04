import MapKit
import Photos
import SwiftUI
import UIKit

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
    @State private var selectedImage: UIImage?
    @State private var pickerSource: UIImagePickerController.SourceType?
    @State private var showingImagePicker = false
    @State private var didApplyInitialMode = false
    @State private var logsExistenceOnly: Bool
    @State private var showingTimePicker: Bool
    @State private var showingLocationPicker = false
    @State private var showingDeleteMealConfirmation = false
    @State private var showingRemovePhotoConfirmation = false

    let baseDate: Date
    let preferredSource: MealCaptureMode
    let canDelete: Bool
    let isEditable: Bool
    let onSave: (MealEntry, UIImage?) -> Void
    let onDelete: () -> Void

    init(
        entry: MealEntry,
        baseDate: Date,
        preferredSource: MealCaptureMode,
        canDelete: Bool,
        isEditable: Bool,
        onSave: @escaping (MealEntry, UIImage?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: entry)
        _logsExistenceOnly = State(initialValue: entry.status == .logged && entry.time == nil)
        _showingTimePicker = State(initialValue: true)
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
                        onSave(normalizedDraft, selectedImage)
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
            .sheet(isPresented: $showingImagePicker) {
                if let pickerSource {
                    ImagePicker(sourceType: pickerSource) { image, capturedAt in
                        selectedImage = image
                        if image != nil {
                            draft.status = .logged
                            draft.time = normalizedPickedDate(capturedAt) ?? draft.time ?? defaultLoggedTime
                        }
                    }
                }
            }
            .alert(NSLocalizedString("删除餐次？", comment: ""), isPresented: $showingDeleteMealConfirmation) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("删除餐次", comment: ""), role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("此操作会删除整个餐次，且无法撤销。", comment: ""))
            }
            .alert(NSLocalizedString("删除照片？", comment: ""), isPresented: $showingRemovePhotoConfirmation) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("删除照片", comment: ""), role: .destructive) {
                    selectedImage = nil
                    draft.photoURL = nil
                }
            } message: {
                Text(NSLocalizedString("此操作会移除这张照片，且无法撤销。", comment: ""))
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
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else if let photoURL = draft.photoURL {
                PhotoContentView(photoURL: photoURL, contentMode: .fill)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }

            HStack(spacing: 10) {
                photoActionButton(title: NSLocalizedString("拍照", comment: ""), systemImage: "camera") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                    pickerSource = .camera
                    showingImagePicker = true
                }

                photoActionButton(title: NSLocalizedString("相册", comment: ""), systemImage: "photo.on.rectangle") {
                    pickerSource = .photoLibrary
                    showingImagePicker = true
                }
            }

            if selectedImage != nil || draft.photoURL != nil {
                Button(NSLocalizedString("移除照片", comment: ""), role: .destructive) {
                    showingRemovePhotoConfirmation = true
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .disabled(!isEditable)
            }
        }
    }

    private func photoActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
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
        } else if selectedImage != nil || entry.photoURL != nil || entry.time != nil || preferredSource == .editRecord {
            entry.status = .logged
            entry.time = entry.time ?? defaultLoggedTime
            entry.timeZoneIdentifier = appViewModel.displayedTimeZone(for: entry.timeZoneIdentifier).identifier
        } else {
            entry.status = .empty
            entry.time = nil
            entry.photoURL = nil
            entry.timeZoneIdentifier = nil
            entry.note = nil
            entry.locationName = nil
            entry.latitude = nil
            entry.longitude = nil
        }
        return entry
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
            openPicker(.photoLibrary)
        case .addPhoto, .editPhoto, .editRecord:
            if draft.status == .logged && draft.time == nil {
                logsExistenceOnly = true
            }
        }
    }

    private func openPicker(_ source: UIImagePickerController.SourceType) {
        guard isEditable else { return }
        guard source != .camera || UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        pickerSource = source
        showingImagePicker = true
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
}

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?, Date?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage?, Date?) -> Void

        init(onImagePicked: @escaping (UIImage?, Date?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil, nil)
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            let capturedAt = capturedDate(from: info, sourceType: picker.sourceType)
            onImagePicked(image, capturedAt)
            picker.dismiss(animated: true)
        }

        private func capturedDate(
            from info: [UIImagePickerController.InfoKey : Any],
            sourceType: UIImagePickerController.SourceType
        ) -> Date? {
            if let asset = info[.phAsset] as? PHAsset, let creationDate = asset.creationDate {
                return creationDate
            }
            if sourceType == .camera {
                return Date()
            }
            return nil
        }
    }
}
