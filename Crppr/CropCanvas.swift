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
            interactiveCanvas(in: geometry.size)
        }
    }

    // Keep rendering, gesture composition, and accessibility in separate type-
    // checking scopes. A single chain here becomes expensive for the compiler.
    private func interactiveCanvas(in size: CGSize) -> some View {
        let layout: CropCanvasLayout = makeLayout(in: size)
        return renderedCanvas(layout: layout)
            .gesture(dragGesture(in: layout.imageRect))
            .simultaneousGesture(pinchGesture)
            // GestureState resets on cancellation as well as normal completion.
            .onChange(of: isDragging) { _, active in
                if !active { dragOrigin = nil }
            }
            .onChange(of: isPinching) { _, active in
                if !active { pinchOrigin = nil }
            }
            .modifier(CropSelectionAccessibility(
                value: accessibilityValue(for: layout.pixels),
                adjustSize: adjustSize,
                move: move,
                centerSelection: centerSelection
            ))
    }

    private func renderedCanvas(layout: CropCanvasLayout) -> some View {
        ZStack {
            Color.black.opacity(0.94)
            photoImage(in: layout.imageRect)
            if let selection = layout.selection {
                CropSelectionOverlay(imageRect: layout.imageRect, selection: selection)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }

    private func photoImage(in imageRect: CGRect) -> some View {
        Image(uiImage: photo.preview)
            .resizable()
            .interpolation(.high)
            .frame(width: imageRect.width, height: imageRect.height)
            .position(x: imageRect.midX, y: imageRect.midY)
    }

    private func makeLayout(in size: CGSize) -> CropCanvasLayout {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
        let imageRect = CropGeometry.aspectFitRect(imageSize: sourceSize, in: bounds)
        let pixels = currentPixelRect()
        let selection: CGRect?
        if let pixels, imageRect.width > 0, imageRect.height > 0 {
            selection = displayRect(for: pixels, in: imageRect)
        } else {
            selection = nil
        }
        return CropCanvasLayout(imageRect: imageRect, pixels: pixels, selection: selection)
    }

    private func currentPixelRect() -> CGRect? {
        CropGeometry.pixelCropRect(imageSize: sourceSize, center: center, scale: scale, ratio: ratio)
    }

    private func displayRect(for pixels: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + pixels.minX / sourceSize.width * imageRect.width,
            y: imageRect.minY + pixels.minY / sourceSize.height * imageRect.height,
            width: pixels.width / sourceSize.width * imageRect.width,
            height: pixels.height / sourceSize.height * imageRect.height
        )
    }

    private func dragGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, active, _ in active = true }
            .onChanged { value in dragChanged(value, in: imageRect) }
            .onEnded { _ in dragOrigin = nil }
    }

    private func dragChanged(_ value: DragGesture.Value, in imageRect: CGRect) {
        guard let pixels = currentPixelRect(), imageRect.width > 0, imageRect.height > 0 else { return }
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

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($isPinching) { _, active, _ in active = true }
            .onChanged { value in pinchChanged(value) }
            .onEnded { _ in pinchOrigin = nil }
    }

    private func pinchChanged(_ magnification: CGFloat) {
        if pinchOrigin == nil { pinchOrigin = scale }
        scale = min(1, max(CropGeometry.minimumScale, (pinchOrigin ?? scale) * magnification))
        clampCenter()
    }

    private func accessibilityValue(for pixels: CGRect?) -> String {
        guard let pixels else { return "Unavailable" }
        return "\(Int(pixels.width)) by \(Int(pixels.height)) pixels"
    }

    private func adjustSize(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: scale = min(1, scale + 0.05)
        case .decrement: scale = max(CropGeometry.minimumScale, scale - 0.05)
        @unknown default: break
        }
        clampCenter()
    }

    private func clampCenter() {
        guard let rect = currentPixelRect() else { return }
        center = CropGeometry.clampedCenter(center, cropSize: rect.size, imageSize: sourceSize)
    }

    private func move(x: CGFloat, y: CGFloat) {
        center = CGPoint(x: center.x + x, y: center.y + y)
        clampCenter()
    }

    private func centerSelection() {
        center = CGPoint(x: 0.5, y: 0.5)
    }
}

private struct CropCanvasLayout {
    let imageRect: CGRect
    let pixels: CGRect?
    let selection: CGRect?
}

private struct CropSelectionOverlay: View {
    let imageRect: CGRect
    let selection: CGRect

    var body: some View {
        ZStack {
            CropDimmedArea(imageRect: imageRect, selection: selection)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            CropGrid(rect: selection)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: selection.width, height: selection.height)
                .position(x: selection.midX, y: selection.midY)
            CropCorners(rect: selection)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
        }
    }
}

private struct CropDimmedArea: Shape {
    let imageRect: CGRect
    let selection: CGRect

    func path(in bounds: CGRect) -> Path {
        var path = Path()
        path.addRect(imageRect)
        path.addRect(selection)
        return path
    }
}

/// The modifier receives concrete callbacks, independent of the canvas renderer.
@MainActor
private struct CropSelectionAccessibility: ViewModifier {
    let value: String
    let adjustSize: @MainActor (AccessibilityAdjustmentDirection) -> Void
    let move: @MainActor (CGFloat, CGFloat) -> Void
    let centerSelection: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Crop selection")
            .accessibilityValue(value)
            .accessibilityHint("Adjust to change crop size. Additional actions move or center the selection.")
            .accessibilityAdjustableAction { direction in adjustSize(direction) }
            .accessibilityAction(named: Text("Move left")) { move(-0.05, 0) }
            .accessibilityAction(named: Text("Move right")) { move(0.05, 0) }
            .accessibilityAction(named: Text("Move up")) { move(0, -0.05) }
            .accessibilityAction(named: Text("Move down")) { move(0, 0.05) }
            .accessibilityAction(named: Text("Center crop")) { centerSelection() }
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
