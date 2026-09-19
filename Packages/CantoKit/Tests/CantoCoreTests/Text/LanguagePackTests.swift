import Foundation
import Testing
@testable import CantoCore

struct LanguagePackTests {
    @Test func bundledLanguagesLoad() throws {
        #expect(LanguagePack.bundled.map(\.code) == ["ru", "en"])
        for pack in LanguagePack.bundled {
            #expect(!pack.phantomSentences.isEmpty)
            #expect(!pack.punctuation.isEmpty)
        }
        #expect(TextCleanup.spokenCommands.count == 16)
    }

    @Test func wordSetsExpand() throws {
        let pack = try JSONDecoder().decode(LanguagePack.self, from: Data(#"""
            {"code": "xx", "wordSets": {"pointers": ["эта", "та"]},
             "punctuation": [{"words": "запятая", "symbol": ",", "notAfter": ["@pointers", "моя"]}]}
            """#.utf8))
        #expect(pack.expand(pack.punctuation[0].notAfter) == ["эта", "та", "моя"])
        #expect(pack.phantomSentences.isEmpty)
    }
}
