import CoreGraphics
import Foundation
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Immutable decoded image data. The original pixels stay separate from the smaller UI preview.
struct LoadedPhoto: @unchecked Sendable {
    let image: CGImage
    let preview: UIImage
}

enum PhotoPipelineError: LocalizedError, Equatable {
    case noImage
    case decodeFailed
    case invalidCrop
    case imageEncodingFailed
    case photoAccessDenied

    var errorDescription: String? {
        switch self {
        case .noImage:
            return "This photo could not be loaded. Try choosing another photo."
        case .decodeFailed:
            return "This image format could not be opened. Try a JPEG, HEIC, or PNG photo."
        case .invalidCrop:
            return "This photo is too small for the selected crop ratio. Choose another ratio or photo."
        case .imageEncodingFailed:
            return "The cropped image could not be prepared. Please try again."
        case .photoAccessDenied:
            return "Allow Crppr to add photos in Settings, then try saving again."
        }
    }
}

@MainActor
enum PhotoPipeline {
    /// The system picker supplies only the selected photo; broad library access is unnecessary.
    static func load(item: PhotosPickerItem) async throws -> LoadedPhoto {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw PhotoPipelineError.noImage
        }
        try Task.checkCancellation()

        let worker = Task.detached(priority: .userInitiated) {
            try decode(data)
        }
        let photo = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return photo
    }

    /// Crop integer source pixels directly: no stretching, resampling, or JPEG recompression.
    static func save(image: CGImage, cropRect: CGRect) async throws {
        try Task.checkCancellation()
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            throw PhotoPipelineError.photoAccessDenied
        }
        try Task.checkCancellation()

        let worker = Task.detached(priority: .userInitiated) {
            try encodeCrop(image: image, cropRect: cropRect)
        }
        let fileURL = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Task.checkCancellation()

        // PhotoKit reads the temporary PNG before this operation's completion callback.
        // Keeping the encoded image on disk avoids a second large in-memory pixel buffer.
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: fileURL, options: nil)
        }
    }

    nonisolated private static func decode(_ data: Data) throws -> LoadedPhoto {
        try autoreleasepool {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            width.intValue > 0, height.intValue > 0 else {
                throw PhotoPipelineError.decodeFailed
            }

            // ImageIO applies all EXIF rotations and mirror orientations. The maximum source
            // dimension prevents downsampling the export image, including portrait photos.
            let maximumDimension = max(width.intValue, height.intValue)
            let fullOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, fullOptions as CFDictionary) else {
                throw PhotoPipelineError.decodeFailed
            }
            try Task.checkCancellation()

            let previewOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(maximumDimension, 2_048),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let previewImage = CGImageSourceCreateThumbnailAtIndex(source, 0, previewOptions as CFDictionary) else {
                throw PhotoPipelineError.decodeFailed
            }
            try Task.checkCancellation()
            return LoadedPhoto(image: image, preview: UIImage(cgImage: previewImage))
        }
    }

    nonisolated private static func encodeCrop(image: CGImage, cropRect: CGRect) throws -> URL {
        try autoreleasepool {
            try Task.checkCancellation()
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            guard cropRect.origin.x.isFinite, cropRect.origin.y.isFinite,
                  cropRect.width.isFinite, cropRect.height.isFinite,
                  cropRect.width >= 1, cropRect.height >= 1,
                  cropRect == cropRect.integral,
                  bounds.contains(cropRect),
                  let cropped = image.cropping(to: cropRect),
                  cropped.width == Int(cropRect.width),
                  cropped.height == Int(cropRect.height) else {
                throw PhotoPipelineError.invalidCrop
            }

            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Crppr-\(UUID().uuidString).png")
            var finished = false
            defer {
                if !finished { try? FileManager.default.removeItem(at: fileURL) }
            }
            guard let destination = CGImageDestinationCreateWithURL(
                fileURL as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else {
                throw PhotoPipelineError.imageEncodingFailed
            }
            CGImageDestinationAddImage(destination, cropped, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw PhotoPipelineError.imageEncodingFailed
            }
            try Task.checkCancellation()
            finished = true
            return fileURL
        }
    }
}
