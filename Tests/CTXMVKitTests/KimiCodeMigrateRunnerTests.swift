@testable import CTXMVKit
import Foundation
import Testing

struct KimiCodeMigrateRunnerTests {
    private struct StubReader: SessionReader {
        let source: AgentSource
        let conversation: UnifiedConversation
        func listSessions() async throws -> [SessionSummary] {
            []
        }

        func loadSession(id: String, storagePath: String?, limit: Int?) async throws -> UnifiedConversation? {
            id == conversation.id ? conversation : nil
        }
    }

    @Test("MigrateRunner --to kimi-code selects the kimi migrator and writes a session")
    func runnerMigratesToKimi() async throws {
        let mockFS = MockFileManager()
        mockFS.homeDirectoryForCurrentUser = URL(fileURLWithPath: "/Users/tester")
        let convo = TestFixtures.makeConversation(id: "run-1", source: .claudeCode, projectPath: "/proj")
        let runner = MigrateRunner(
            sessionID: "run-1",
            target: .kimiCode,
            source: .claudeCode,
            readers: [StubReader(source: .claudeCode, conversation: convo)],
            fileSystem: mockFS
        )
        try await runner.run()

        #expect(mockFS.files.keys.contains { $0.contains("/.kimi-code/sessions/") && $0.hasSuffix("wire.jsonl") })
    }
}
