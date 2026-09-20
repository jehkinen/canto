import Foundation
import Testing
@testable import CantoCore

struct LargeNumbersTests {
    @Test(arguments: [
        ("девятьсот миллионов", "900 млн"),
        ("восемьсот девять миллионов параметров", "809 млн параметров"),
        ("полтора миллиарда", "1,5 млрд"),
        ("два с половиной миллиона", "2,5 млн"),
        ("миллион рублей", "1 млн рублей"),
        ("три триллиона", "3 трлн"),
        ("nine hundred million", "900 million"),
        ("two and a half billion dollars", "2.5 billion dollars"),
        ("1.5 billion", "1.5 billion"),
        // The multiplier does not end the number, or is not a number at all.
        ("миллион двести тысяч", "миллион двести тысяч"),
        ("миллионы людей", "миллионы людей"),
        ("пять тысяч рублей", "пять тысяч рублей"),
        ("миллионный пользователь", "миллионный пользователь"),
        ("", ""),
    ])
    func spokenMillionsBecomeShort(input: String, expected: String) {
        #expect(LargeNumbers.abbreviate(input) == expected)
    }

    @Test(arguments: [
        ("девятьсот миллионов", "900 млн"),
        ("бюджет два с половиной миллиона долларов", "Бюджет 2,5 млн долларов"),
        ("пять тысяч рублей", "5000\u{00A0}₽"),
        ("девятьсот миллионов рублей", "900 млн рублей"),
        ("900000000", "900000000"),
        ("в две тысячи двадцать шестом году", "В две тысячи двадцать шестом году"),
    ])
    func digitsModeKeepsTheRest(input: String, expected: String) async {
        var settings = AppSettings()
        settings.numberFormat = .digits
        let store = SkillStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-large-numbers"))
        let processed = await TextPipeline(chat: nil, skills: store).process(input, settings: settings, fallbackLanguage: "ru")
        #expect(processed.text == expected)
    }
}
