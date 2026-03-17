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
}

struct MealEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var draft: MealEntry
    @State private var selectedImage: UIImage?
    @State private var pickerSource: UIImagePickerController.SourceType?
    @State private var showingImagePicker = false
    @State private var didApplyInitialMode = false
    @State private var showingTimePicker: Bool

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
        _showingTimePicker = State(initialValue: preferredSource == .timeOnly || preferredSource == .editTime)
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

                    if shouldShowPhotoSection {
                        photoSection
                    }
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
                            onDelete()
                            dismiss()
                        }
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
                            showingTimePicker = false
                        }
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("时间", comment: ""))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            if showingTimePicker {
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
            } else {
                Button {
                    guard isEditable else { return }
                    showingTimePicker = true
                } label: {
                    HStack {
                        Text(NSLocalizedString("记录时间", comment: ""))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Text(appViewModel.displayedClockTime(
                            for: draft.time ?? defaultLoggedTime,
                            recordedTimeZoneIdentifier: draft.timeZoneIdentifier
                        ))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(timeAccent)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isEditable)
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

    private var shouldShowPhotoSection: Bool {
        switch preferredSource {
        case .timeOnly, .editTime:
            return selectedImage != nil || draft.photoURL != nil
        case .camera, .photoLibrary, .addPhoto, .editPhoto:
            return true
        }
    }

    private var normalizedDraft: MealEntry {
        var entry = draft
        let trimmed = entry.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.mealKind == .custom {
            entry.customTitle = trimmed?.isEmpty == false ? trimmed : NSLocalizedString("加餐", comment: "")
        }

        if selectedImage != nil || entry.photoURL != nil || entry.time != nil {
            entry.status = .logged
            entry.time = entry.time ?? defaultLoggedTime
            entry.timeZoneIdentifier = appViewModel.displayedTimeZone(for: entry.timeZoneIdentifier).identifier
        } else {
            entry.status = .empty
            entry.time = nil
            entry.photoURL = nil
            entry.timeZoneIdentifier = nil
        }
        return entry
    }

    private var defaultLoggedTime: Date {
        let timeZone = appViewModel.displayedTimeZone(for: draft.timeZoneIdentifier)
        switch draft.mealKind {
        case .breakfast:
            return baseDate.settingTime(hour: 8, minute: 0, in: timeZone)
        case .lunch:
            return baseDate.settingTime(hour: 12, minute: 30, in: timeZone)
        case .dinner:
            return baseDate.settingTime(hour: 18, minute: 30, in: timeZone)
        case .custom:
            return baseDate.settingTime(hour: 15, minute: 0, in: timeZone)
        }
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
        case .camera:
            draft.status = .logged
            openPicker(.camera)
        case .photoLibrary:
            draft.status = .logged
            openPicker(.photoLibrary)
        case .addPhoto, .editPhoto:
            draft.status = .logged
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
