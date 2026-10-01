/// Tells when focus has settled, from the lens position alone. On the iPhone 15 Pro Max,
/// `AVCaptureDevice.isAdjustingFocus` stays false through continuous autofocus, while
/// `lensPosition` (0...1) moves to the new distance and stops.
///
/// The lens arrives in big steps, then creeps the last 0.01 in steps of 1/255 for about 0.1 s,
/// when the picture already looks sharp. Steps under `creepStep` therefore don't count as moving:
/// focus counts as settled `settleDelay` after the last bigger step, if the lens travelled at least
/// `minimumTravel` from where it rested. Wobble while resting travels less and never counts.
public struct FocusSettling: Sendable {
    /// Lens travel that counts as refocusing, in `lensPosition` units.
    public static let minimumTravel: Float = 0.02
    /// Steps this small are the lens creeping in or wobbling, not still moving to a new distance.
    public static let creepStep: Float = 0.006
    /// How long after the last bigger step focus counts as settled. Reports come about every 37 ms.
    public static let settleDelay: Duration = .milliseconds(100)

    /// Where the lens last came to rest. Nil until the first report.
    private var restingPosition: Float?
    private var latestPosition: Float?
    private var travelled = false

    public init() {}

    /// Each reported lens position. True when this was a bigger step, so the wait starts again.
    public mutating func lensMoved(to position: Float) -> Bool {
        defer { latestPosition = position }
        guard let resting = restingPosition, let latest = latestPosition else {
            restingPosition = position
            return false
        }
        if abs(position - resting) >= Self.minimumTravel { travelled = true }
        return abs(position - latest) >= Self.creepStep
    }

    /// When `settleDelay` has passed. True when the lens travelled since it last rested.
    public mutating func lensStopped() -> Bool {
        defer {
            restingPosition = latestPosition
            travelled = false
        }
        return travelled
    }
}
