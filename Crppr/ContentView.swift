import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var photo: LoadedPhoto?
    @AppStorage("ratioWidthTenths") private var ratioWidthTenths = 10
    @AppStorage("ratioHeightTenths") private var ratioHeightTenths = 10
    @State private var widthInput = "1"
    @State private var heightInput = "1"
    @State private var center = CGPoint(x: 0.5, y: 0.5)
    @State private var scale: CGFloat = 0.85
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var notice: Notice?
    @FocusState private var focusedRatio: RatioField?

    private enum RatioField: Hashable {
        case width, height
    }

    private var isBusy: Bool { isLoading || isSaving }
    private var inputRatio: CropRatio? {
        guard let width = CropRatio.parseTenths(widthInput),
              let height = CropRatio.parseTenths(heightInput) else { return nil }
        return CropRatio(widthTenths: width, heightTenths: height)
    }
    private var isRatioValid: Bool { inputRatio != nil }
    private var appliedRatio: CropRatio {
        CropRatio(widthTenths: ratioWidthTenths, heightTenths: ratioHeightTenths) ?? .square
    }
    private var ratioDescription: String {
        "\(CropRatio.text(for: appliedRatio.widthTenths)):\(CropRatio.text(for: appliedRatio.heightTenths))"
    }
    private var sourceSize: CGSize? {
        photo.map { CGSize(width: CGFloat($0.image.width), height: CGFloat($0.image.height)) }
    }
    private var cropRect: CGRect? {
        guard let sourceSize else { return nil }
        return CropGeometry.pixelCropRect(
            imageSize: sourceSize, center: center, scale: scale, ratio: appliedRatio
        )
    }
    private var pixelLabel: String {
        guard let cropRect else { return "Image too small for this ratio" }
        return "\(Int(cropRect.width)) × \(Int(cropRect.height)) px"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let photo {
                    editor(photo: photo)
                } else {
                    ContentUnavailableView {
                        Label("Every crop, exact.", systemImage: "crop")
                    } description: {
                        Text("Choose a photo, set a ratio, and move the box to find your crop.")
                    } actions: {
                        photoPicker
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Crppr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if photo != nil {
                    ToolbarItem(placement: .topBarTrailing) { photoPicker }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedRatio = nil
                        if isRatioValid { normalizeRatioInputs() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if photo != nil {
                    Button(action: saveCrop) {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !isRatioValid || cropRect == nil)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
            .disabled(isBusy)
            .overlay {
                if isBusy {
                    ZStack {
                        Color(.systemBackground).opacity(0.85)
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(isSaving ? "Saving to Photos…" : "Loading photo…")
                                .font(.subheadline)
                            if isLoading {
                                Button("Cancel") {
                                    selectedItem = nil
                                    isLoading = false
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .ignoresSafeArea()
                }
            }
            .alert(item: $notice) { notice in
                if notice.offerSettings {
                    return Alert(
                        title: Text(notice.title), message: Text(notice.message),
                        primaryButton: .default(Text("Open Settings")) {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        },
                        secondaryButton: .cancel()
                    )
                }
                return Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                if CropRatio(widthTenths: ratioWidthTenths, heightTenths: ratioHeightTenths) == nil {
                    ratioWidthTenths = 10
                    ratioHeightTenths = 10
                }
                normalizeRatioInputs()
            }
            .onChange(of: widthInput) { _, _ in applyRatioInputs() }
            .onChange(of: heightInput) { _, _ in applyRatioInputs() }
            .onChange(of: scale) { _, _ in clampCenter() }
            .task(id: selectedItem) {
                guard let selectedItem else { return }
                focusedRatio = nil
                isLoading = true
                do {
                    let loaded = try await PhotoPipeline.load(item: selectedItem)
                    try Task.checkCancellation()
                    photo = loaded
                    center = CGPoint(x: 0.5, y: 0.5)
                    scale = 0.85
                } catch {
                    guard !Task.isCancelled else { return }
                    notice = Notice(title: "Couldn’t open photo", message: error.localizedDescription)
                }
                if !Task.isCancelled {
                    isLoading = false
                    // Clear the selection so the same asset can be selected again after a failed load.
                    self.selectedItem = nil
                }
            }
        }
    }

    private var photoPicker: some View {
        let title = photo == nil ? "Choose Photo" : "Change Photo"
        return PhotosPicker(selection: $selectedItem, matching: .images, preferredItemEncoding: .current) {
            Label(title, systemImage: "photo.on.rectangle")
        }
        .disabled(isBusy)
    }

    private func editor(photo: LoadedPhoto) -> some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                HStack(spacing: 20) {
                    cropArea(photo: photo)
                    ScrollView { controls }
                        .frame(width: min(320, geometry.size.width * 0.42))
                }
                .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        cropArea(photo: photo)
                            .frame(height: max(220, min(460, geometry.size.height * 0.53)))
                        controls
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func cropArea(photo: LoadedPhoto) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR CROP")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                Spacer(minLength: 4)
                Text(pixelLabel)
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            CropCanvas(photo: photo, ratio: appliedRatio, center: $center, scale: $scale)
                .id(ObjectIdentifier(photo.image))
                .allowsHitTesting(!isBusy)
            Text("Drag the box to move. Pinch to resize.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Aspect ratio").font(.headline)
                    Spacer()
                    Button {
                        focusedRatio = nil
                        let previousWidth = widthInput
                        widthInput = heightInput
                        heightInput = previousWidth
                        applyRatioInputs()
                    } label: {
                        Label("Swap", systemImage: "arrow.left.arrow.right")
                    }
                    .font(.subheadline)
                    .disabled(!isRatioValid)
                    .accessibilityLabel("Swap ratio width and height")
                }

                HStack(alignment: .bottom, spacing: 12) {
                    ratioField("Width", text: $widthInput, field: .width)
                    Text(":")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 7)
                        .accessibilityHidden(true)
                    ratioField("Height", text: $heightInput, field: .height)
                }

                Text(isRatioValid ? "Each side: 0.1–999.9 · up to one decimal place" : "Enter 0.1–999.9 on each side, with at most one decimal place.")
                    .font(.caption)
                    .foregroundStyle(isRatioValid ? Color.secondary : Color.red)
                Text("Applied: \(ratioDescription)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Applied ratio, \(CropRatio.text(for: appliedRatio.widthTenths)) to \(CropRatio.text(for: appliedRatio.heightTenths))")
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 8) {
                HStack {
                    Text("Crop size").font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Reset") {
                        focusedRatio = nil
                        center = CGPoint(x: 0.5, y: 0.5)
                        scale = 0.85
                    }
                    .font(.subheadline)
                    .accessibilityLabel("Reset crop size and position")
                }
                Slider(value: $scale, in: 0.15...1) {
                    Text("Crop size")
                } minimumValueLabel: {
                    Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
                } maximumValueLabel: {
                    Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
                }
                .accessibilityValue("\(Int((scale * 100).rounded())) percent")
            }

            Text(cropRect == nil ? "This photo is too small for that exact ratio. Try another ratio or photo." : "Saves a new photo. Your original stays unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private func ratioField(_ title: String, text: Binding<String>, field: RatioField) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.title3.monospacedDigit())
                .focused($focusedRatio, equals: field)
                .accessibilityLabel("Ratio \(title.lowercased())")
                .accessibilityHint("Enter 0.1 to 999.9 with at most one decimal place")
        }
        .frame(maxWidth: .infinity)
    }

    private func applyRatioInputs() {
        guard let ratio = inputRatio else { return }
        ratioWidthTenths = ratio.widthTenths
        ratioHeightTenths = ratio.heightTenths
        clampCenter()
    }

    private func normalizeRatioInputs() {
        widthInput = CropRatio.text(for: appliedRatio.widthTenths)
        heightInput = CropRatio.text(for: appliedRatio.heightTenths)
    }

    private func clampCenter() {
        guard let sourceSize, let cropRect else { return }
        center = CropGeometry.clampedCenter(center, cropSize: cropRect.size, imageSize: sourceSize)
    }

    private func saveCrop() {
        guard !isBusy, isRatioValid, let photo, let cropRect else { return }
        focusedRatio = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await PhotoPipeline.save(image: photo.image, cropRect: cropRect)
                notice = Notice(title: "Saved to Photos", message: "Your \(Int(cropRect.width)) × \(Int(cropRect.height)) crop is saved. The original photo is unchanged.")
            } catch {
                notice = Notice(
                    title: "Couldn’t save photo", message: error.localizedDescription,
                    offerSettings: (error as? PhotoPipelineError) == .photoAccessDenied
                )
            }
        }
    }
}

private struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var offerSettings = false
}
