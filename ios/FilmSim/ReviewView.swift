import FilmSimCore
import Photos
import SwiftUI
import UIKit

/// The photos taken with this app (#57), opened from the camera's thumbnail. Newest first; swipe
/// sideways between them, swipe down to go back to the camera. Each shows the recipe and focal
/// length it was taken with. Share, delete, open in Photos; editing is left to Photos.
/// A shot whose DNG is still in the library can be re-developed (a development tool).
struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shots = ShotStore.shared
    @State private var access: Access = .checking
    /// Shots whose HEIC is still in the library.
    @State private var available: [ShotRecord] = []
    @State private var current: UUID?
    @State private var dragDown: CGFloat = 0
    @State private var sharing: ShareItem?
    @State private var developing: DevelopItem?
    @State private var message: String?

    private enum Access { case checking, allowed, denied }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch access {
            case .checking:
                ProgressView().tint(.white)
            case .denied:
                denied
            case .allowed:
                if available.isEmpty {
                    ContentUnavailableView("まだ写真がありません", systemImage: "photo", description: Text("このアプリで撮った写真がここに並びます"))
                        .foregroundStyle(.white)
                } else {
                    pages
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("閉じる")
            .padding(12)
        }
        .offset(y: max(0, dragDown))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Only a mostly vertical drag; sideways drags page through the photos.
                    if abs(value.translation.height) > abs(value.translation.width) { dragDown = value.translation.height }
                }
                .onEnded { value in
                    if dragDown > 120 { dismiss() } else { withAnimation { dragDown = 0 } }
                }
        )
        .task { await load() }
        .sheet(item: $sharing) { ActivityView(items: [$0.url]) }
        .fullScreenCover(item: $developing) { DevelopView(rawData: $0.data) }
    }

    private var pages: some View {
        TabView(selection: $current) {
            ForEach(available) { shot in
                ShotPage(shot: shot).tag(Optional(shot.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var currentShot: ShotRecord? {
        available.first { $0.id == current } ?? available.first
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let shot = currentShot {
                Text("\(shot.recipeName)・\(shot.focalLength.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(shot.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.yellow)
            }
            HStack(spacing: 36) {
                barButton("共有", systemImage: "square.and.arrow.up") { Task { await share() } }
                barButton("写真アプリ", systemImage: "photo.on.rectangle") { openPhotos() }
                if let shot = currentShot, shot.dngAssetID.map(Self.exists) == true {
                    barButton("現像し直す", systemImage: "slider.horizontal.3") { Task { await redevelop(shot) } }
                }
                barButton("削除", systemImage: "trash", role: .destructive) { Task { await delete() } }
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6))
    }

    private func barButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .tint(role == .destructive ? .red : .white)
    }

    private var denied: some View {
        VStack(spacing: 16) {
            Text("撮った写真を見るには、写真へのアクセスを許可してください")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        .padding()
    }

    private func load() async {
        guard await LibraryRaw.canRead() else { access = .denied; return }
        available = shots.log.newestFirst.filter { $0.heicAssetID.map(Self.exists) == true }
        current = available.first?.id
        access = .allowed
    }

    private static func exists(_ id: String) -> Bool {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count > 0
    }

    /// Shares the HEIC file as saved, not a re-encoded copy.
    private func share() async {
        guard let shot = currentShot, let id = shot.heicAssetID,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
        do {
            let data = try await Self.imageData(asset)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Irocam-\(shot.id.uuidString.prefix(8)).heic")
            try data.write(to: url, options: .atomic)
            sharing = ShareItem(url: url)
        } catch {
            message = "共有できません：\(error.localizedDescription)"
        }
    }

    private func openPhotos() {
        // Photos has no documented link to one photo; this opens the app.
        if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
    }

    private func redevelop(_ shot: ShotRecord) async {
        guard let id = shot.dngAssetID else { return }
        do {
            developing = DevelopItem(data: try await LibraryRaw.load(assetID: id))
        } catch {
            message = error.localizedDescription
        }
    }

    /// Deletes the HEIC and, if saved, the DNG. Photos asks for confirmation and keeps them in
    /// Recently Deleted.
    private func delete() async {
        guard let shot = currentShot else { return }
        let ids = [shot.heicAssetID, shot.dngAssetID].compactMap { $0 }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            // Cancelling the system dialog lands here too.
            return
        }
        let index = available.firstIndex { $0.id == shot.id } ?? 0
        shots.remove(shot)
        available.removeAll { $0.id == shot.id }
        current = available.isEmpty ? nil : available[min(index, available.count - 1)].id
    }

    private static func imageData(_ asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    let error = info?[PHImageErrorKey] as? Error ?? LibraryRaw.LoadError.noData
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct DevelopItem: Identifiable {
        let id = UUID()
        let data: Data
    }
}

/// One photo, loaded at screen size when its page comes up.
private struct ShotPage: View {
    let shot: ShotRecord
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if let thumb = ShotStore.shared.thumbnail(for: shot) {
                    Image(uiImage: thumb).resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: shot.id) { image = await load(size: geo.size) }
        }
        .accessibilityLabel("\(shot.recipeName)、\(shot.focalLength.displayName)の写真")
    }

    private func load(size: CGSize) async -> UIImage? {
        guard let id = shot.heicAssetID,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let scale = UIScreen.main.scale
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: size.width * scale, height: size.height * scale),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// The system share sheet.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
