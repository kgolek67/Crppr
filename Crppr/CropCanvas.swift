import SwiftUI

/// The entire photo stays visible; only the fixed-ratio selection moves or resizes.
@MainActor
struct CropCanvas: View {
    let photo: LoadedPhoto
    let ratio: CropRatio
    @Binding var center: CGPoint
    @Binding var scale: CGFloat

    @State private var dragOrigin: CGPoint?
    @State private var pinchOrigin: CGFloat?
    @GestureState private var isDragging = false
    @GestureState private var isPinching = false

    private var sourceSize: CGSize {
        CGSize(width: CGFloat(photo.image.width), height: CGFloat(photo.image.height))
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 12, dy: 12)
            let imageRect = CropGeometry.aspectFitRect(imageSize: sourceSize, in: bounds)
            let pixels = CropGeometry.pixelCropRect(
                imageSize: sourceSize, center: center, scale: scale, ratio: ratio
            )

            ZStack {
                Color.black.opacity(0.94)
                Image(uiImage: photo.preview)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                if let pixels, imageRect.width > 0 {
                    let selection = displayRect(for: pixels, in: imageRect)
                    Path { path in
                        path.addRect(imageRect)
                        path.addRect(selection)
                    }
                    .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

                    CropGrid(rect: selection)
                        .stroke(.white.opacity(0.45), lineWidth: 0.5)
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .frame(width: selection.width, height: selection.height)
                        .position(x: selection.midX, y: selection.midY)
                    CropCorners(rect: selection)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, active, _ in active = true }
                .onChanged { value in
                    guard let pixels, imageRect.width > 0, imageRect.height > 0 else { return }
                    if dragOrigin == nil {
                        dragOrigin = CGPoint(x: pixels.midX / sourceSize.width, y: pixels.midY / sourceSize.height)
                    }
                    guard let origin = dragOrigin else { return }
                    let proposed = CGPoint(
                        x: origin.x + value.translation.width / imageRect.width,
                        y: origin.y + value.translation.height / imageRect.height
                    )
                    center = CropGeometry.clampedCenter(proposed, cropSize: pixels.size, imageSize: sourceSize)
                }
                .onEnded { _ in dragOrigin = nil }
            )
            .simultaneousGesture(MagnificationGesture()
                .updating($isPinching) { _, active, _ in active = true }
                .onChanged { value in
                    if pinchOrigin == nil { pinchOrigin = scale }
                    scale = min(1, max(0.15, (pinchOrigin ?? scale) * value))
                    clampCenter()
                }
                .onEnded { _ in pinchOrigin = nil }
            )
            // GestureState resets on cancellation as well as normal completion.
            .onChange(of: isDragging) { _, active in
                if !active { dragOrigin = nil }
            }
            .onChange(of: isPinching) { _, active in
                if !active { pinchOrigin = nil }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Crop selection")
            .accessibilityValue(pixels.map { "\(Int($0.width)) by \(Int($0.height)) pixels" } ?? "Unavailable")
            .accessibilityHint("Adjust to change crop size. Additional actions move or center the selection.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: scale = min(1, scale + 0.05)
                case .decrement: scale = max(0.15, scale - 0.05)
                @unknown default: break
                }
                clampCenter()
            }
            .accessibilityAction(named: Text("Move left")) { move(x: -0.05, y: 0) }
            .accessibilityAction(named: Text("Move right")) { move(x: 0.05, y: 0) }
            .accessibilityAction(named: Text("Move up")) { move(x: 0, y: -0.05) }
            .accessibilityAction(named: Text("Move down")) { move(x: 0, y: 0.05) }
            .accessibilityAction(named: Text("Center crop")) { center = CGPoint(x: 0.5, y: 0.5) }
        }
    }

    private func displayRect(for pixels: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + pixels.minX / sourceSize.width * imageRect.width,
            y: imageRect.minY + pixels.minY / sourceSize.height * imageRect.height,
            width: pixels.width / sourceSize.width * imageRect.width,
            height: pixels.height / sourceSize.height * imageRect.height
        )
    }

    private func clampCenter() {
        guard let rect = CropGeometry.pixelCropRect(
            imageSize: sourceSize, center: center, scale: scale, ratio: ratio
        ) else { return }
        center = CropGeometry.clampedCenter(center, cropSize: rect.size, imageSize: sourceSize)
    }

    private func move(x: CGFloat, y: CGFloat) {
        center = CGPoint(x: center.x + x, y: center.y + y)
        clampCenter()
    }
}

private struct CropGrid: Shape {
    let rect: CGRect

    func path(in bounds: CGRect) -> Path {
        Path { path in
            for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
                let x = rect.minX + rect.width * fraction
                let y = rect.minY + rect.height * fraction
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
    }
}

private struct CropCorners: Shape {
    let rect: CGRect

    func path(in bounds: CGRect) -> Path {
        let length = min(18, min(rect.width, rect.height) / 3)
        return Path { path in
            for (x, y, dx, dy) in [
                (rect.minX, rect.minY, CGFloat(1), CGFloat(1)),
                (rect.maxX, rect.minY, CGFloat(-1), CGFloat(1)),
                (rect.minX, rect.maxY, CGFloat(1), CGFloat(-1)),
                (rect.maxX, rect.maxY, CGFloat(-1), CGFloat(-1))
            ] {
                path.move(to: CGPoint(x: x, y: y + dy * length))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + dx * length, y: y))
            }
        }
    }
}
