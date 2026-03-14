import SwiftUI
import UIKit
import Photos

enum MealCaptureMode {
    case camera
    case photoLibrary
    case timeOnly
}

struct MealEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MealEntry
    @State private var selectedImage: UIImage?
    @State private var pickerSource: UIImagePickerController.SourceType?
    @State private var showingImagePicker = false
    @State private var didAutoPresentSource = false

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
                VStack(alignment: .leading, spacing: 20) {
                    timePicker
                    photoBlock

                    if draft.mealKind == .custom {
                        TextField("名称", text: Binding(
                            get: { draft.customTitle ?? "" },
                            set: { draft.customTitle = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isEditable)
                    }
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(draft.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(normalizedDraft, selectedImage)
                        dismiss()
                    }
                    .disabled(!isEditable)
                }
                if canDelete {
                    ToolbarItem(placement: .bottomBar) {
                        Button("删除", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                guard !didAutoPresentSource else { return }
                didAutoPresentSource = true
                prepareDraftForLoggingIfNeeded()
                switch preferredSource {
                case .camera:
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        pickerSource = .camera
                        showingImagePicker = true
                    }
                case .photoLibrary:
                    pickerSource = .photoLibrary
                    showingImagePicker = true
                case .timeOnly:
                    break
                }
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
        }
    }

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("时间")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            DatePicker(
                "时间",
                selection: Binding(
                    get: { draft.time ?? defaultLoggedTime },
                    set: {
                        draft.time = $0
                        draft.status = .logged
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
        }
        .disabled(!isEditable)
    }

    private var photoBlock: some View {
        VStack(spacing: 12) {
            if let selectedImage {
                previewImage(Image(uiImage: selectedImage))
            } else if let photoURL = draft.photoURL, let uiImage = UIImage(contentsOfFile: photoURL) {
                previewImage(Image(uiImage: uiImage))
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(AppTheme.secondaryText)
                    )
            }

            HStack(spacing: 10) {
                actionButton(icon: "camera") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                    pickerSource = .camera
                    showingImagePicker = true
                }
                actionButton(icon: "photo.on.rectangle") {
                    pickerSource = .photoLibrary
                    showingImagePicker = true
                }
                actionButton(icon: "trash") {
                    selectedImage = nil
                    draft.photoURL = nil
                }
            }
        }
    }

    private func actionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }

    private func previewImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var normalizedDraft: MealEntry {
        var entry = draft
        if selectedImage != nil || entry.photoURL != nil {
            entry.status = .logged
        }
        if entry.status == .logged && entry.time == nil {
            entry.time = defaultLoggedTime
        }
        if entry.status != .logged {
            entry.time = nil
            if selectedImage == nil {
                entry.photoURL = nil
            }
        }
        if entry.mealKind == .custom {
            let trimmed = entry.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.customTitle = (trimmed?.isEmpty == false) ? trimmed : "加餐"
        }
        return entry
    }

    private var defaultLoggedTime: Date {
        switch draft.mealKind {
        case .breakfast:
            return baseDate.settingTime(hour: 8, minute: 0)
        case .lunch:
            return baseDate.settingTime(hour: 12, minute: 30)
        case .dinner:
            return baseDate.settingTime(hour: 18, minute: 30)
        case .custom:
            return baseDate.settingTime(hour: 15, minute: 0)
        }
    }

    private func prepareDraftForLoggingIfNeeded() {
        if draft.status != .logged || draft.time == nil {
            draft.status = .logged
            draft.time = draft.time ?? defaultLoggedTime
        }
    }

    private func normalizedPickedDate(_ pickedDate: Date?) -> Date? {
        guard let pickedDate else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: pickedDate)
        return baseDate.settingTime(hour: components.hour ?? 12, minute: components.minute ?? 0)
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
