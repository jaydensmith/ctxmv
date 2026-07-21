#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif
import Foundation

/// Helpers for kimi-code's workspace directory naming.
enum KimiCodeWorkspace {
    private enum Constants {
        static let workspacePrefix = "wd_"
        static let hashPrefixLength = 12
    }

    /// kimi-code names each workspace `wd_<basename>_<sha256(absolute-root)[:12]>`.
    static func workspaceId(forRoot root: String) -> String {
        let basename = URL(fileURLWithPath: root).lastPathComponent
        let digest = SHA256.hash(data: Data(root.utf8))
        let hex = MigratorUtils.hexString(Data(digest))
        return "\(Constants.workspacePrefix)\(basename)_\(hex.prefix(Constants.hashPrefixLength))"
    }
}

extension KimiCodeWorkspace {
    /// Shared by `indexLine` (encode) and the migrator's dedup scan (decode) so the two can't drift.
    struct IndexEntry: Codable {
        let sessionId: String
        let sessionDir: String
        let workDir: String
    }

    static func indexLine(sessionId: String, sessionDir: String, workDir: String) -> String? {
        MigratorUtils.encodeLine(IndexEntry(sessionId: sessionId, sessionDir: sessionDir, workDir: workDir))
    }

    /// Upserts the `wd_…` entry into `workspaces.json`, preserving `version`/existing workspaces/
    /// `deleted_workspace_ids`. Throws `MigrationError.writeFailed` on unparseable input (fail closed).
    static func upsertWorkspaces(
        existing: Data?,
        workspaceId: String,
        root: String,
        name: String,
        timestamp: String
    ) throws -> Data {
        var object: [String: Any]
        if let existing {
            guard let parsed = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else {
                throw MigrationError.writeFailed("workspaces.json is not valid JSON; refusing to overwrite")
            }
            object = parsed
        } else {
            object = ["version": 1, "workspaces": [String: Any](), "deleted_workspace_ids": [String]()]
        }

        var workspaces = object["workspaces"] as? [String: Any] ?? [:]
        if var entry = workspaces[workspaceId] as? [String: Any] {
            entry["last_opened_at"] = timestamp
            workspaces[workspaceId] = entry
        } else {
            workspaces[workspaceId] = [
                "root": root,
                "name": name,
                "created_at": timestamp,
                "last_opened_at": timestamp,
            ]
        }
        object["workspaces"] = workspaces

        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
