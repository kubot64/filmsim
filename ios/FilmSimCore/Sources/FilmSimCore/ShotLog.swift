import Foundation

/// One photo taken with the camera screen (#54), for the review screen: which library assets it
/// became and the recipe it was developed with. The recipe is copied, not referenced, so editing
/// or deleting the saved recipe later does not change what the shot says.
public struct ShotRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    /// `PHAsset.localIdentifier` of the HEIC. Nil when only the DNG was saved.
    public var heicAssetID: String?
    /// `PHAsset.localIdentifier` of the DNG, when it was saved too.
    public var dngAssetID: String?
    public var recipeName: String
    public var recipe: Recipe
    public var focalLength: FocalLength

    public init(
        id: UUID = UUID(), date: Date, heicAssetID: String?, dngAssetID: String?,
        recipeName: String, recipe: Recipe, focalLength: FocalLength
    ) {
        self.id = id
        self.date = date
        self.heicAssetID = heicAssetID
        self.dngAssetID = dngAssetID
        self.recipeName = recipeName
        self.recipe = recipe
        self.focalLength = focalLength
    }
}

/// Every shot, oldest first. Kept as one JSON file (Application Support/Shots.json): a record is
/// a few hundred bytes, so even thousands of shots rewrite in well under a megabyte.
public struct ShotLog: Codable, Equatable, Sendable {
    public private(set) var shots: [ShotRecord]

    public init(shots: [ShotRecord] = []) {
        self.shots = shots
    }

    /// The log in `data`, or an empty one when there is none or it no longer decodes.
    public static func decoded(from data: Data) -> ShotLog {
        (try? decoder.decode(ShotLog.self, from: data)) ?? ShotLog()
    }

    public var encoded: Data {
        (try? Self.encoder.encode(self)) ?? Data()
    }

    public mutating func append(_ shot: ShotRecord) {
        shots.append(shot)
    }

    /// Newest first, as the review screen shows them.
    public var newestFirst: [ShotRecord] { shots.reversed() }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
