/// How the portrait-locked camera screen turns its controls so they read upright however the
/// phone is held (#43). The interface itself never rotates.
public enum HoldingOrientation {
    /// Degrees to turn the controls, clockwise positive, from the back camera's horizon-level
    /// capture angle (`AVCaptureDevice.RotationCoordinator`): 90 when held upright, 0 with the
    /// top of the phone to the left, 180 with it to the right, 270 upside down.
    /// Returns 0, 90 or -90. Upside down keeps the upright layout: turned 180°, the controls'
    /// top edge would land on the shutter at the bottom of the screen.
    public static func controlRotation(captureAngle: Double) -> Double {
        var r = (90 - captureAngle).truncatingRemainder(dividingBy: 360)
        if r <= -180 { r += 360 }
        if r > 180 { r -= 360 }
        return abs(abs(r) - 180) < 1 ? 0 : r
    }

    /// True when the controls are turned sideways, so the holder's width is the screen's height.
    public static func isSideways(_ rotation: Double) -> Bool {
        abs(abs(rotation) - 90) < 1
    }
}
