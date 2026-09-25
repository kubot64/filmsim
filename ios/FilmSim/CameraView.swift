import SwiftUI

/// Plain preview (no film simulation live), shutter, RAW capture.
/// ROADMAP step 1: confirm 48MP Bayer RAW works on this device before anything else.
struct CameraView: View {
    @StateObject private var camera = CameraController()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: camera.session)
                .aspectRatio(3.0 / 2.0, contentMode: .fit) // 3:2 framing guide
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Text(camera.status).font(.footnote).foregroundStyle(.white)
                Button {
                    camera.capture()
                } label: {
                    Circle().fill(.white).frame(width: 72, height: 72)
                }
                .disabled(!camera.isReady)
            }
            .padding(.bottom, 24)
        }
        .background(Color.black)
        .task { await camera.start() }
    }
}
