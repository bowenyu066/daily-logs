import SwiftUI
import UIKit

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
                    statusPicker
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
                    ImagePicker(sourceType: pickerSource) { image in
                        selectedImage = image
                    }
                }
            }
        }
    }

    private var statusPicker: some View {
        Picker("状态", selection: $draft.status) {
            ForEach(MealStatus.allCases, id: \.self) { status in
                Text(status.title).tag(status)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!isEditable)
    }

    private var timePicker: some View {
        Group {
            if draft.status == .logged {
                DatePicker(
                    "时间",
                    selection: Binding(
                        get: { draft.time ?? baseDate.settingTime(hour: 8, minute: 0) },
                        set: { draft.time = $0 }
                    )
                )
                .labelsHidden()
                .datePickerStyle(.wheel)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .frame(height: 110)
                    .overlay(
                        Text(draft.status == .skipped ? "跳过" : "--")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(draft.status == .skipped ? AppTheme.warning : AppTheme.secondaryText)
                    )
            }
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
}

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?) -> Void

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
        let onImagePicked: (UIImage?) -> Void

        init(onImagePicked: @escaping (UIImage?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil)
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            onImagePicked(image)
            picker.dismiss(animated: true)
        }
    }
}
