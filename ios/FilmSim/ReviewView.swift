import FilmSimCore
import Photos
import SwiftUI
import UIKit

/// The photos taken with this app (#57), opened from the camera's thumbnail. Newest first; swipe
/// sideways between them, swipe down to go back to the camera. Each shows the recipe and focal
/// length it was taken with. Share and delete; editing is left to Photos, which the person opens
/// themselves (there is no public way to open Photos on one photo).
/// The screen says 写真 for the HEIC and RAW for the DNG, the word Photos also marks it with.
/// A shot whose RAW is still in the library gets a 写真 / RAW switch; showing the RAW offers
/// re-developing it (a development tool).
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
    /// Shots whose RAW (DNG) is still in the library.
    @State private var withRaw: Set<UUID> = []
    /// Set while asking whether to delete the RAW too.
    @State private var confirmingDelete: ShotRecord?
    /// Showing the RAW instead of the photo. Only for shots that have one.
    @State private var showsRaw = false

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
            Button {
                dismiss()
            } label: {
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
                    if abs(value.translation.height) > abs(value.translation.width) {
                        dragDown = value.translation.height
                    }
                }
                .onEnded { value in
                    if dragDown > 120 { dismiss() } else { withAnimation { dragDown = 0 } }
                }
        )
        .task { await load() }
        .sheet(item: $sharing) { ActivityView(items: [$0.url]) }
        .fullScreenCover(item: $developing) { DevelopView(rawData: $0.data, source: $0.source) }
        // A re-develop saved from the develop screen joins the log; show it first.
        .onChange(of: shots.log.shots.count) { old, new in
            guard access == .allowed else { return }
            refresh(showNewest: new > old)
        }
        // In the library the photo and its RAW are two items, so Photos would say "2 photos".
        // Ask first, in words that match what the screen shows.
        .confirmationDialog(
            "この写真には RAW（元データ）も保存されています",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { shot in
            Button("写真と RAW を削除（2 枚）", role: .destructive) { Task { await delete(shot, includingRaw: true) } }
            Button("写真だけ削除", role: .destructive) { Task { await delete(shot, includingRaw: false) } }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("写真だけを消すと、RAW は写真アプリに残ります。このあと iOS の確認が出ます。")
        }
    }

    private var pages: some View {
        TabView(selection: $current) {
            ForEach(available) { shot in
                ShotPage(shot: shot, raw: showsRaw && withRaw.contains(shot.id)).tag(Optional(shot.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: current) { _, _ in showsRaw = false }
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
            if let shot = currentShot, withRaw.contains(shot.id) {
                Picker("表示", selection: $showsRaw) {
                    Text("写真").tag(false)
                    Text("RAW").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            HStack(spacing: 36) {
                barButton("共有", systemImage: "square.and.arrow.up") { Task { await share() } }
                if let shot = currentShot, showsRaw, withRaw.contains(shot.id) {
                    barButton("現像し直す", systemImage: "slider.horizontal.3") { Task { await redevelop(shot) } }
                }
                barButton("削除", systemImage: "trash", role: .destructive) {
                    guard let shot = currentShot else { return }
                    if withRaw.contains(shot.id) {
                        confirmingDelete = shot
                    } else {
                        Task { await delete(shot, includingRaw: false) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6))
    }

    private func barButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void)
        -> some View
    {
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
        refresh(showNewest: true)
        access = .allowed
    }

    /// Re-reads which shots still have their HEIC and RAW in the library.
    private func refresh(showNewest: Bool) {
        available = shots.log.newestFirst.filter { $0.heicAssetID.map(Self.exists) == true }
        withRaw = Set(available.filter { $0.dngAssetID.map(Self.exists) == true }.map(\.id))
        if showNewest || !available.contains(where: { $0.id == current }) {
            current = available.first?.id
        }
    }

    private static func exists(_ id: String) -> Bool {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count > 0
    }

    /// Shares the HEIC file as saved, not a re-encoded copy.
    /// Shares what is shown: the HEIC, or the DNG while the RAW is shown, as the saved files.
    private func share() async {
        guard let shot = currentShot else { return }
        let raw = showsRaw && withRaw.contains(shot.id)
        do {
            // Both read the asset's original file (`PHAssetResourceManager`), not a re-rendered image.
            guard let id = raw ? shot.dngAssetID : shot.heicAssetID else { return }
            let data = try await LibraryRaw.load(assetID: id)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Irocam-\(shot.id.uuidString.prefix(8)).\(raw ? "dng" : "heic")")
            try data.write(to: url, options: .atomic)
            sharing = ShareItem(url: url)
        } catch {
            message = "共有できません：\(error.localizedDescription)"
        }
    }

    private func redevelop(_ shot: ShotRecord) async {
        guard let id = shot.dngAssetID else { return }
        do {
            developing = DevelopItem(data: try await LibraryRaw.load(assetID: id), source: shot)
        } catch {
            message = error.localizedDescription
        }
    }

    /// Deletes the HEIC and, with `includingRaw`, the DNG. Photos asks for confirmation and keeps
    /// them in Recently Deleted. The shot leaves the review screen either way.
    private func delete(_ shot: ShotRecord, includingRaw: Bool) async {
        let ids = [shot.heicAssetID, includingRaw ? shot.dngAssetID : nil].compactMap { $0 }
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
        // Re-developed shots share their RAW, so deleting it changes what the others show too.
        refresh(showNewest: false)
        current = available.isEmpty ? nil : available[min(index, available.count - 1)].id
    }

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct DevelopItem: Identifiable {
        let id = UUID()
        let data: Data
        let source: ShotRecord
    }
}

/// One photo, loaded at screen size when its page comes up.
private struct ShotPage: View {
    let shot: ShotRecord
    /// Shows the DNG as Photos renders it, without this app's look.
    let raw: Bool
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if !raw, let thumb = ShotStore.shared.thumbnail(for: shot) {
                    Image(uiImage: thumb).resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: "\(shot.id) \(raw)") {
                image = nil
                image = await load(size: geo.size)
            }
        }
        .accessibilityLabel(
            raw
                ? "\(shot.recipeName)、\(shot.focalLength.displayName)の RAW"
                : "\(shot.recipeName)、\(shot.focalLength.displayName)の写真")
    }

    private func load(size: CGSize) async -> UIImage? {
        guard let id = raw ? shot.dngAssetID : shot.heicAssetID,
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        else { return nil }
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
