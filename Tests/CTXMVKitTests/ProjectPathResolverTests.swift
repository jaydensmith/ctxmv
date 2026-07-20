@testable import CTXMVKit
import Foundation
import Testing

@Suite
struct ProjectPathResolverTests {
    private func registerDirectoryTree(_ path: String, in fileSystem: MockFileManager) {
        let components = URL(filePath: path).standardizedFileURL.pathComponents.filter { $0 != "/" }
        var current = "/"
        for component in components {
            let child = current == "/" ? "/" + component : current + "/" + component
            var siblings = fileSystem.directories[current] ?? []
            let childURL = URL(filePath: child)
            if !siblings.contains(childURL) { siblings.append(childURL) }
            fileSystem.directories[current] = siblings
            fileSystem.directories[child] = fileSystem.directories[child] ?? []
            current = child
        }
    }

    // MARK: - Encoding

    @Test("encodes every non-alphanumeric character to a hyphen, matching Claude Code")
    func encodesAllSeparatorsToHyphen() {
        #expect(
            ProjectPathResolver.encodedClaudeProjectPath("/Users/example/web_root/my-app")
                == "-Users-example-web-root-my-app"
        )
        #expect(
            ProjectPathResolver.encodedClaudeProjectPath("/Users/example/site.example.com")
                == "-Users-example-site-example-com"
        )
        #expect(
            ProjectPathResolver.encodedClaudeProjectPath("/home/a/.claude/worktrees")
                == "-home-a--claude-worktrees"
        )
    }

    @Test("encodedClaudeProjectPath matches ClaudeCodeMigrator-style collision")
    func encodingCollisionExample() {
        let hyphenated = "/Users/example/acme/foo-bar-baz"
        let nested = "/Users/example/acme/foo/bar/baz"
        let encH = ProjectPathResolver.encodedClaudeProjectPath(hyphenated)
        let encN = ProjectPathResolver.encodedClaudeProjectPath(nested)
        #expect(encH == encN)
        #expect(encH == "-Users-example-acme-foo-bar-baz")
    }

    // MARK: - existingDirectoryCandidates (filesystem-guided inverse)

    @Test("finds every real directory that re-encodes to the bucket, including `_` spellings")
    func findsUnderscoreAndHyphenCollisions() {
        let fileSystem = MockFileManager()
        let underscore = "/Users/example/acme/web_root"
        let hyphen = "/Users/example/acme/web-root"
        registerDirectoryTree(underscore, in: fileSystem)
        registerDirectoryTree(hyphen, in: fileSystem)

        let candidates = ProjectPathResolver.existingDirectoryCandidates(
            encoded: "-Users-example-acme-web-root",
            fileSystem: fileSystem
        )
        #expect(Set(candidates) == [underscore, hyphen])
        #expect(candidates.allSatisfy {
            ProjectPathResolver.encodedClaudeProjectPath($0) == "-Users-example-acme-web-root"
        })
    }

    @Test("returns nothing when no real directory re-encodes to the bucket")
    func findsNoCandidatesWhenTreeAbsent() {
        let fileSystem = MockFileManager()
        let candidates = ProjectPathResolver.existingDirectoryCandidates(
            encoded: "-Users-example-acme-web-root",
            fileSystem: fileSystem
        )
        #expect(candidates.isEmpty)
    }

    // MARK: - cdPath (JSONL-path-based resolution)

    @Test("prefers existing directory among colliding spellings")
    func picksExistingDirectory() {
        let fileSystem = MockFileManager()
        let hyphenated = "/Users/example/acme/foo-bar-baz"
        let wrongNested = "/Users/example/acme/foo/bar/baz"
        registerDirectoryTree(hyphenated, in: fileSystem)

        let jsonl = "/mock/home/.claude/projects/-Users-example-acme-foo-bar-baz/sess.jsonl"
        let resolved = ProjectPathResolver.cdPath(
            forStoredProjectPath: wrongNested,
            writtenJSONLPath: jsonl,
            fileSystem: fileSystem
        )
        #expect(resolved == URL(filePath: hyphenated).standardizedFileURL.path)
    }

    @Test("resolves an underscore project path from the written bucket when the stored path is wrong")
    func picksUnderscoreDirectoryFromBucket() {
        let fileSystem = MockFileManager()
        let real = "/Users/example/web_root/my-app"
        let wrongDecode = "/Users/example/web/root/my/app"
        registerDirectoryTree(real, in: fileSystem)

        let jsonl = "/mock/home/.claude/projects/-Users-example-web-root-my-app/sess.jsonl"
        let resolved = ProjectPathResolver.cdPath(
            forStoredProjectPath: wrongDecode,
            writtenJSONLPath: jsonl,
            fileSystem: fileSystem
        )
        #expect(resolved == real)
    }

    @Test("returns stored path when it exists and matches the written bucket")
    func prefersStoredWhenValid() {
        let fileSystem = MockFileManager()
        let path = "/tmp/resume-hint-target-dir"
        fileSystem.directories[path] = []
        let enc = ProjectPathResolver.encodedClaudeProjectPath(path)
        let jsonl = "/mock/.claude/projects/\(enc)/x.jsonl"
        let resolved = ProjectPathResolver.cdPath(
            forStoredProjectPath: path,
            writtenJSONLPath: jsonl,
            fileSystem: fileSystem
        )
        #expect(resolved == URL(filePath: path).standardizedFileURL.path)
    }

    @Test("falls back to stored string when no candidate directory exists")
    func fallsBackToStoredWhenNothingExists() {
        let fileSystem = MockFileManager()
        let wrongNested = "/Users/example/acme/foo/bar/baz"
        let jsonl = "/mock/home/.claude/projects/-Users-example-acme-foo-bar-baz/sess.jsonl"
        let resolved = ProjectPathResolver.cdPath(
            forStoredProjectPath: wrongNested,
            writtenJSONLPath: jsonl,
            fileSystem: fileSystem
        )
        #expect(resolved == wrongNested)
    }

    // MARK: - resolveProjectPath (standalone resolution without JSONL path)

    @Test("resolveProjectPath returns path as-is when it exists on disk")
    func resolveReturnsExistingPath() {
        let fileSystem = MockFileManager()
        let path = "/Users/example/workspace/my-project"
        fileSystem.directories[path] = []
        let resolved = ProjectPathResolver.resolveProjectPath(path, fileSystem: fileSystem)
        #expect(resolved == path)
    }

    @Test("resolveProjectPath finds real directory when stored path is wrong due to lossy encoding")
    func resolveFindsCorrectHyphenatedPath() {
        let fileSystem = MockFileManager()
        let wrongNested = "/Users/example/acme/foo/bar/baz"
        let realHyphenated = "/Users/example/acme/foo-bar-baz"
        registerDirectoryTree(realHyphenated, in: fileSystem)

        let resolved = ProjectPathResolver.resolveProjectPath(wrongNested, fileSystem: fileSystem)
        #expect(resolved == URL(filePath: realHyphenated).standardizedFileURL.path)
    }

    @Test("resolveProjectPath returns original path when no candidate exists")
    func resolveFallsBackToOriginal() {
        let fileSystem = MockFileManager()
        let nonexistent = "/Users/example/acme/foo/bar/baz"
        let resolved = ProjectPathResolver.resolveProjectPath(nonexistent, fileSystem: fileSystem)
        #expect(resolved == nonexistent)
    }

    @Test("resolveProjectPath returns nil for nil or empty input", arguments: [nil, ""] as [String?])
    func resolveReturnsNilForNilOrEmpty(input: String?) {
        let fileSystem = MockFileManager()
        let resolved = ProjectPathResolver.resolveProjectPath(input, fileSystem: fileSystem)
        #expect(resolved == nil)
    }
}
