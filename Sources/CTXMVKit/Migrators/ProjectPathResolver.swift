import Foundation

/// Picks a workspace directory for `claude --resume` hints when stored `projectPath` may be wrong.
///
/// Claude Code stores sessions under `.claude/projects/<encoded>/` where `encoded` is the absolute
/// project path with every non-alphanumeric character replaced by `-` (see
/// ``MigratorUtils/encodedClaudeProjectPath(_:)``). That map is heavily non-injective: `/`, `-`, `_`,
/// and `.` all collapse to `-`, so the encoded name cannot be decoded by string surgery — a single
/// `-` may be a path separator *or* any of several literal characters inside one directory name.
/// This resolver uses the **authoritative** `encoded` directory name (from the written JSONL path)
/// and walks the real filesystem, re-encoding each existing directory it visits, to recover the
/// actual path(s) on disk.
package enum ProjectPathResolver {
    /// Same encoding as ``ClaudeCodeMigrator/encodedProjectPath(for:)``.
    package static func encodedClaudeProjectPath(_ absolutePath: String) -> String {
        MigratorUtils.encodedClaudeProjectPath(absolutePath)
    }

    /// Returns the best `cd` target directory for a Claude Code resume hint.
    ///
    /// Prefers the stored project path when it re-encodes to the same bucket as the
    /// written JSONL file; otherwise enumerates all matching candidates on disk.
    package static func cdPath(
        forStoredProjectPath stored: String?,
        writtenJSONLPath: String,
        fileSystem: any FileSystemProtocol
    ) -> String? {
        let encoded = URL(filePath: writtenJSONLPath).deletingLastPathComponent().lastPathComponent
        guard !encoded.isEmpty else { return stored }

        // Fast path: metadata path exists and matches the same bucket as the written file.
        if let stored, !stored.isEmpty {
            let normalized = URL(filePath: stored).standardizedFileURL.path
            var isDirectory = ObjCBool(false)
            if fileSystem.fileExists(atPath: normalized, isDirectory: &isDirectory), isDirectory.boolValue,
               encodedClaudeProjectPath(normalized) == encoded
            {
                return normalized
            }
        }

        let existing = existingDirectoryCandidates(encoded: encoded, fileSystem: fileSystem)
        if existing.isEmpty {
            return stored
        }
        if existing.count == 1, let only = existing.first {
            return only
        }

        // Multiple filesystem paths collide under the same encoding (hyphenated segment vs extra nested dirs).
        if let stored, !stored.isEmpty {
            let normalized = URL(filePath: stored).standardizedFileURL.path
            if existing.contains(normalized) {
                return normalized
            }
        }
        return existing.min(by: compareCandidatePaths)
    }

    /// Resolves a project path that may not exist on disk due to Claude Code's lossy `-` encoding.
    /// Returns the original path if it exists, otherwise searches for the real directory.
    package static func resolveProjectPath(
        _ projectPath: String?,
        fileSystem: any FileSystemProtocol
    ) -> String? {
        guard let projectPath, !projectPath.isEmpty else { return nil }
        var isDirectory = ObjCBool(false)
        if fileSystem.fileExists(atPath: projectPath, isDirectory: &isDirectory), isDirectory.boolValue {
            return projectPath
        }
        let encoded = encodedClaudeProjectPath(projectPath)
        let candidates = existingDirectoryCandidates(encoded: encoded, fileSystem: fileSystem)
        return candidates.first ?? projectPath
    }

    /// Existing directories `D` with `encodedClaudeProjectPath(D) == encoded`, found by walking the
    /// real filesystem rather than by decoding the (lossy) `encoded` string.
    package static func existingDirectoryCandidates(
        encoded: String,
        fileSystem: any FileSystemProtocol
    ) -> [String] {
        guard encoded.hasPrefix("-") else { return [] }
        var results: [String] = []
        walkForCandidates(parentPath: "/", remainingEncoded: encoded, fileSystem: fileSystem, results: &results)
        return Array(Set(results)).sorted(by: compareCandidatePaths)
    }

    private static func walkForCandidates(
        parentPath: String,
        remainingEncoded: String,
        fileSystem: any FileSystemProtocol,
        results: inout [String]
    ) {
        guard remainingEncoded.hasPrefix("-") else { return }
        let afterSeparator = String(remainingEncoded.dropFirst())
        guard !afterSeparator.isEmpty else { return }

        let entries = (try? fileSystem.contentsOfDirectory(atPath: parentPath)) ?? []
        for name in entries {
            let childPath = parentPath == "/" ? "/" + name : parentPath + "/" + name
            var isDirectory = ObjCBool(false)
            guard fileSystem.fileExists(atPath: childPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let encodedName = encodedClaudeProjectPath(name)
            guard afterSeparator.hasPrefix(encodedName) else { continue }
            let rest = String(afterSeparator.dropFirst(encodedName.count))

            if rest.isEmpty {
                results.append(childPath)
            } else if rest.hasPrefix("-") {
                walkForCandidates(
                    parentPath: childPath,
                    remainingEncoded: rest,
                    fileSystem: fileSystem,
                    results: &results
                )
            }
        }
    }

    /// Prefer shallower paths, then lexicographic (stable, deterministic).
    private static func compareCandidatePaths(_ lhs: String, _ rhs: String) -> Bool {
        let lhsDepth = URL(filePath: lhs).pathComponents.count { $0 != "/" }
        let rhsDepth = URL(filePath: rhs).pathComponents.count { $0 != "/" }
        if lhsDepth != rhsDepth {
            return lhsDepth < rhsDepth
        }
        return lhs < rhs
    }
}
