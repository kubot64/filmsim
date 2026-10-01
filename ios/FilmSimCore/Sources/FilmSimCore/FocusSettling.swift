/// Tells when focus has settled, from the lens position alone. On the iPhone 15 Pro Max,
/// `AVCaptureDevice.isAdjustingFocus` stays false through continuous autofocus, while
/// `lensPosition` (0...1) moves to the new distance and stops. The camera reports every move;
/// once moves stop for `settleDelay`, `lensStopped` says whether the lens really travelled.
/// Steps of 1/255 seen while resting are below `minimumTravel` and do not count.
public struct FocusSettling: Sendable {
    /// Lens travel that counts as refocusing, in `lensPosition` units.
    public static let minimumTravel: Float = 0.02
    /// How long the lens must stay still before focus counts as settled.
    public static let settleDelay: Duration = .milliseconds(200)

    /// Where the lens last came to rest. Nil until the first report.
    private var restingPosition: Float?
    private var travelled = false

    public init() {}

    /// Each reported lens position.
    public mutating func lensMoved(to position: Float) {
        guard let resting = restingPosition else {
            restingPosition = position
            return
        }
        if abs(position - resting) >= Self.minimumTravel { travelled = true }
    }

    /// After `settleDelay` without a report. True when the lens travelled since it last rested.
    public mutating func lensStopped(at position: Float) -> Bool {
        defer {
            restingPosition = position
            travelled = false
        }
        return travelled
    }
}
