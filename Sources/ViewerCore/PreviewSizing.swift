import Foundation

public enum PreviewSizing {
    public static func pixelLimit(viewport: CGSize, backingScale: CGFloat, fitToWindow: Bool) -> Int {
        guard fitToWindow else { return 6000 }
        let pixels = max(viewport.width, viewport.height) * max(1, backingScale)
        guard pixels.isFinite else { return 2048 }
        return Int(min(6000, max(1024, (pixels / 256).rounded(.up) * 256)))
    }
}
