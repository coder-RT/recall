import Foundation

/// One camera frame at arrival, for the Mac's Verifier: the photo, the LiDAR depth (unsigned 16-bit millimetres, row
/// by row) and where the camera was (ARKit camera-to-world, column-major, in the saved room map's world).
public struct ArrivalFrame: Sendable, Equatable {
    public let jpeg: Data
    public let depthMM: Data
    public let depthSize: (width: Int, height: Int)
    public let imageSize: (width: Int, height: Int)
    public let intrinsics: (fx: Double, fy: Double, cx: Double, cy: Double)
    public let pose: [Double]

    public init(jpeg: Data, depthMM: Data, depthSize: (width: Int, height: Int), imageSize: (width: Int, height: Int),
                intrinsics: (fx: Double, fy: Double, cx: Double, cy: Double), pose: [Double]) {
        self.jpeg = jpeg; self.depthMM = depthMM; self.depthSize = depthSize; self.imageSize = imageSize
        self.intrinsics = intrinsics; self.pose = pose
    }

    public static func == (a: ArrivalFrame, b: ArrivalFrame) -> Bool {
        a.jpeg == b.jpeg && a.depthMM == b.depthMM && a.pose == b.pose
    }

    /// The pose part of the request (VerificationRequest.yaml).
    public var poseJSON: Data {
        let body: [String: Any] = [
            "pose": pose,
            "intrinsics": ["fx": intrinsics.fx, "fy": intrinsics.fy, "cx": intrinsics.cx, "cy": intrinsics.cy],
            "image_size": [imageSize.width, imageSize.height],
            "depth_size": [depthSize.width, depthSize.height],
        ]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }
}

/// The Verifier's answer: whether the thing is really there, and what to say.
public struct ArrivalCheck: Sendable, Equatable {
    public enum Outcome: String, Sendable { case confirmed, foundNearby = "found_nearby", uncertain, notHere = "not_here" }

    public let outcome: Outcome
    public let say: String

    public init(outcome: Outcome, say: String) { self.outcome = outcome; self.say = say }

    /// Found (where remembered or close by): a success haptic; otherwise a warning.
    public var found: Bool { outcome == .confirmed || outcome == .foundNearby }
}
