import Foundation
import Testing
@testable import CantoCore

struct ReleaseCheckerTests {
    @Test func readsTheLatestRelease() throws {
        let json = #"{"tag_name": "v1.0.7", "html_url": "https://github.com/jehkinen/canto/releases/tag/v1.0.7", "name": "Canto 1.0.7"}"#
        let release = try ReleaseChecker.parse(Data(json.utf8))
        #expect(release == AppRelease(version: "1.0.7", pageURL: URL(string: "https://github.com/jehkinen/canto/releases/tag/v1.0.7")!))
    }

    @Test(arguments: [
        ("1.0.7", "1.0.6", true),
        ("1.0.10", "1.0.9", true),
        ("1.1", "1.0.9", true),
        ("1.0.6", "1.0.6", false),
        ("1.0.5", "1.0.6", false),
        ("1.0", "1.0.0", false),
    ])
    func comparesVersionsNumberByNumber(candidate: String, current: String, newer: Bool) {
        #expect(ReleaseChecker.isNewer(candidate, than: current) == newer)
    }
}
