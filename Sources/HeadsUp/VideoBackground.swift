import AVFoundation
import SwiftUI

/// Looping, muted, aspect-filled video — for user-chosen alert backdrops.
struct VideoBackground: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingPlayerView {
        LoopingPlayerView(url: url)
    }

    func updateNSView(_ nsView: LoopingPlayerView, context: Context) {}
}

final class LoopingPlayerView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true

        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)

        player.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        player.pause()
    }
}
