import Foundation
import Testing
@testable import CantoCore

struct LanguagePackTests {
    @Test func bundledLanguagesLoad() throws {
        #expect(LanguagePack.bundled.map(\.code) == ["ru", "en", "he"])
        for pack in LanguagePack.bundled {
            #expect(!pack.phantomSentences.isEmpty)
            #expect(!pack.punctuation.isEmpty)
        }
        #expect(TextCleanup.spokenCommands.count == 23)
    }

    /// A phantom sentence is compared after `normalized`, so one stored any other way never matches.
    @Test func phantomSentencesAreNormalized() {
        for pack in LanguagePack.bundled {
            for sentence in pack.phantomSentences {
                #expect(TextCleanup.normalized(sentence) == sentence, "\(pack.code): \(sentence)")
            }
            #expect(Set(pack.phantomSentences).count == pack.phantomSentences.count, "\(pack.code) has duplicates")
        }
        // Words people really dictate on their own stay out of the list.
        for word in ["thank you", "thanks", "so", "okay", "ok", "bye", "yes", "no"] {
            #expect(!TextCleanup.phantomSentences.contains(word), "\(word)")
        }
    }

    @Test(arguments: [
        ("שלום פסיק מה שלומך סימן שאלה", "שלום, מה שלומך?"),
        ("זה עובד סימן קריאה", "זה עובד!"),
        ("סיימתי נקודה מחר נמשיך", "סיימתי. מחר נמשיך"),
        ("זו נקודה חשובה", "זו נקודה חשובה"),
        ("יש לי נקודה טובה", "יש לי נקודה טובה"),
        ("שורה ראשונה שורה חדשה שורה שנייה", "שורה ראשונה\nשורה שנייה"),
    ])
    func hebrewPunctuation(input: String, expected: String) {
        #expect(TextCleanup.normalizeSpacing(TextCleanup.applySpokenPunctuation(input)) == expected)
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
