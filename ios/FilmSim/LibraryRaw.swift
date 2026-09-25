import Foundation
import Photos
import PhotosUI

/// Loads the original DNG off a PhotosPicker item. `Data` transferable is often a JPEG.
enum LibraryRaw {
    enum LoadError: LocalizedError {
        case denied
        case noAsset
        case noData

        var errorDescription: String? {
            switch self {
            case .denied: return "写真ライブラリへのアクセスが拒否されました"
            case .noAsset: return "写真を特定できません"
            case .noData: return "画像データを読めませんでした"
            }
        }
    }

    static func load(from item: PhotosPickerItem) async throws -> Data {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let status = current == .notDetermined
            ? await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            : current
        guard status == .authorized || status == .limited else { throw LoadError.denied }

        guard let id = item.itemIdentifier else {
            if let data = try await item.loadTransferable(type: Data.self) { return data }
            throw LoadError.noAsset
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { throw LoadError.noAsset }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { isRaw($0) }) ?? resources.first(where: { $0.type == .photo }) else {
            throw LoadError.noData
        }
        let data = try await requestData(resource)
        guard !data.isEmpty else { throw LoadError.noData }
        return data
    }

    private static func isRaw(_ resource: PHAssetResource) -> Bool {
        if resource.type == .alternatePhoto { return true }
        let name = resource.originalFilename.lowercased()
        if name.hasSuffix(".dng") || name.hasSuffix(".raf") || name.hasSuffix(".raw") { return true }
        let uti = resource.uniformTypeIdentifier.lowercased()
        return uti.contains("raw") || uti.contains("dng")
    }

    private static func requestData(_ resource: PHAssetResource) async throws -> Data {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let box = DataBox()
        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                box.append(chunk)
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: box.data)
                }
            }
        }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        func append(_ chunk: Data) {
            lock.lock()
            storage.append(chunk)
            lock.unlock()
        }
        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
