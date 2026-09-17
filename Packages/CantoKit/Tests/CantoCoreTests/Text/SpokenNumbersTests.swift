import Foundation
import Testing
@testable import CantoCore

struct SpokenNumbersTests {
    @Test(arguments: [
        ("Пять, шесть, семь, восемь.", "5, 6, 7, 8."),
        ("двадцать пять человек", "25 человек"),
        ("сто двадцать три", "123"),
        ("две тысячи двадцать шесть", "2026"),
        ("twenty five people", "25 people"),
        ("one hundred and three", "103"),
        ("three thousand four hundred", "3400"),
        ("одна из причин", "одна из причин"),
        ("раз, два, три", "раз, 2, 3"),
        ("ноль проблем", "0 проблем"),
    ])
    func wordsBecomeDigits(input: String, expected: String) {
        #expect(SpokenNumbers.toDigits(input) == expected)
    }

    @Test func keepsTextItDoesNotUnderstand() {
        #expect(SpokenNumbers.toDigits("Мы пишем на Next.js и деплоим в AWS") == "Мы пишем на Next.js и деплоим в AWS")
        #expect(SpokenNumbers.toDigits("") == "")
    }

    @Test(arguments: [
        ("Это стоит 50 долларов", "Это стоит $50"),
        ("заплатил 50 баксов вчера", "заплатил $50 вчера"),
        ("50 евро за ночь", "50\u{00A0}€ за ночь"),
        ("1000 рублей", "1000\u{00A0}₽"),
        ("it costs 20 dollars", "it costs $20"),
        ("30 pounds", "£30"),
        ("50 долларовых купюр", "50 долларовых купюр"),
    ])
    func amountsBecomeSymbols(input: String, expected: String) {
        #expect(SpokenNumbers.currencySymbols(input) == expected)
    }

    @Test func pipelineConvertsNumbersThenCurrency() async {
        var settings = AppSettings()
        settings.textProcessingMode = .original
        settings.numberFormat = .digits
        let store = StyleStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-\(UUID())"))
        let processed = await TextPipeline(chat: nil, styles: store)
            .process("пятьдесят долларов и двадцать евро", settings: settings, fallbackLanguage: "ru")
        #expect(processed.text == "$50 и 20\u{00A0}€")
    }

    @Test func legacySettingsKeepWordsMode() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"numbersAsWords":true}"#.utf8))
        #expect(settings.numberFormat == .words)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).numberFormat == .asHeard)
    }
}
