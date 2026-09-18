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

    @Test(arguments: [
        ("один точка пять", "1.5"),
        ("один точка ноль пять", "1.05"),
        ("версия два точка ноль точка один", "версия 2.0.1"),
        ("один точка пять миллиона", "1.5 миллиона"),
        ("два запятая пять процента", "2,5 процента"),
        ("один запятая два запятая три", "1, 2, 3"),
        ("их было пять точка Один из них ушёл", "их было 5. Один из них ушёл"),
        ("one point five", "1.5"),
        ("1 точка 5", "1.5"),
        ("одна целая пять десятых", "1,5"),
        ("две целых двадцать пять сотых", "2,25"),
    ])
    func decimals(input: String, expected: String) {
        #expect(SpokenNumbers.toDigits(TextCleanup.applySpokenPunctuation(input)) == expected)
    }

    @Test(arguments: [
        ("одна пятая", "1/5"),
        ("одну пятую часть", "1/5 часть"),
        ("две третьих", "2/3"),
        ("три четверти часа", "3/4 часа"),
        ("2 трети", "2/3"),
        ("two thirds of users", "2/3 of users"),
        ("двадцать пятая годовщина", "двадцать пятая годовщина"),
        ("one second please", "one second please"),
    ])
    func fractions(input: String, expected: String) {
        #expect(SpokenNumbers.toDigits(input) == expected)
    }

    @Test(arguments: [
        ("один и пять", "1 и 5"),
        ("один или два раза", "1 или 2 раза"),
        ("один, два, три", "1, 2, 3"),
        ("один и тот же", "один и тот же"),
        ("один из них", "один из них"),
    ])
    func oneNextToAnotherNumberIsADigit(input: String, expected: String) {
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
        let store = SkillStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-\(UUID())"))
        let processed = await TextPipeline(chat: nil, skills: store)
            .process("пятьдесят долларов и двадцать евро", settings: settings, fallbackLanguage: "ru")
        #expect(processed.text == "$50 и 20\u{00A0}€")
    }

    @Test func legacySettingsKeepWordsMode() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"numbersAsWords":true}"#.utf8))
        #expect(settings.numberFormat == .words)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).numberFormat == .asHeard)
    }
}
