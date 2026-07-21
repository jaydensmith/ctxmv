@testable import CTXMVKit
import Foundation
import Testing

struct KimiCodeWorkspaceTests {
    @Test("workspaceId matches kimi-code's wd_<basename>_<sha256[:12]> scheme")
    func workspaceIdMatchesReal() {
        // Verified against a real ~/.kimi-code/workspaces.json install.
        #expect(KimiCodeWorkspace.workspaceId(forRoot: "/Users/jayden") == "wd_jayden_154602f87fd0")
        #expect(
            KimiCodeWorkspace.workspaceId(forRoot: "/Users/jayden/public_html/optimogo-expo")
                == "wd_optimogo-expo_f5d65b8a66aa"
        )
    }

    @Test("upsertWorkspaces preserves version, existing workspaces, and deleted_workspace_ids")
    func upsertPreservesExisting() throws {
        // swiftlint:disable line_length
        let existingJSON = """
        {"version":1,"workspaces":{"wd_other_aaaaaaaaaaaa":{"root":"/other","name":"other","created_at":"t0","last_opened_at":"t0"}},"deleted_workspace_ids":["wd_gone_bbbbbbbbbbbb"]}
        """
        // swiftlint:enable line_length
        let updated = try KimiCodeWorkspace.upsertWorkspaces(
            existing: Data(existingJSON.utf8),
            workspaceId: "wd_new_cccccccccccc",
            root: "/new",
            name: "new",
            timestamp: "t1"
        )
        let object = try #require((try? JSONSerialization.jsonObject(with: updated)) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect((object["deleted_workspace_ids"] as? [String]) == ["wd_gone_bbbbbbbbbbbb"])
        let workspaces = try #require(object["workspaces"] as? [String: Any])
        #expect(workspaces["wd_other_aaaaaaaaaaaa"] != nil)
        let newEntry = try #require(workspaces["wd_new_cccccccccccc"] as? [String: Any])
        #expect(newEntry["root"] as? String == "/new")
        #expect(newEntry["last_opened_at"] as? String == "t1")
    }

    @Test("upsertWorkspaces fails closed on unparseable existing JSON")
    func upsertFailsClosedOnCorrupt() {
        #expect(throws: MigrationError.self) {
            _ = try KimiCodeWorkspace.upsertWorkspaces(
                existing: Data("{not json".utf8),
                workspaceId: "wd_x_000000000000",
                root: "/x",
                name: "x",
                timestamp: "t1"
            )
        }
    }
}
