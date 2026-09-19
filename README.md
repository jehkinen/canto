<p align="center">
  <img src="docs/images/logo.png" width="128" alt="Canto icon">
</p>

<h1 align="center">Canto</h1>

<p align="center">
  <b>Dictate into any app on your Mac.</b><br>
  Hold a key, speak, and the text appears where your cursor is.
</p>

<p align="center">
  <a href="https://github.com/jehkinen/canto/releases/latest"><img src="https://img.shields.io/github/v/release/jehkinen/canto?label=download" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
</p>

<p align="center">
  On Windows or Linux? Try <a href="https://github.com/WtekSupport/veyro"><b>Veyro</b></a>, a cross-platform dictation app made by my friend.
</p>

<p align="center">
  <a href="#русский">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot-en.png" alt="Canto: settings window, menu bar panel and the recording overlay">
</p>

Canto lives in the menu bar. Hold a shortcut, speak, and it types what you said into whatever you are working in:
chats, email, notes, code editors, the terminal.

## Features

- **Works everywhere.** A global shortcut, or Caps Lock, in any app. Hold to talk, or press to start and stop
  and let pauses split your speech into phrases.
- **Private by default.** Speech is recognized on your Mac with Whisper Large v3 Turbo on Metal or Parakeet v3 on
  the Neural Engine. Nothing leaves your Mac unless you choose OpenAI.
- **OpenAI when you want it.** GPT-4o Transcribe or Whisper in the cloud, with a fallback to a downloaded local
  model when the network does not answer.
- **Fewer invented words.** Silero VAD cuts silence and noise before recognition, and known Whisper hallucinations
  ("Thanks for watching", subtitle credits, loops of the same phrase) are removed.
- **Clean text.** Keep the transcript as is or tidy it up. Optional AI skills, Markdown files you can edit or add:
  remove filler words, fix technical terms, translate, drop profanity. Turn on several at once; they run in one
  request on OpenAI or a local model (Ollama, LM Studio).
- **Vocabulary.** Terms like OpenAI, Node.js or AWS are spelled the way you write them.
- **Small touches.** Spoken punctuation, numbers as digits or words (including decimals, fractions and Russian
  cases), currency symbols ("fifty bucks" → $50), a phrase that presses Return, a recording overlay, history,
  English, Russian and Hebrew interface.

## Install

1. Download **Canto.dmg** from the [latest release](https://github.com/jehkinen/canto/releases/latest) and drag
   Canto to Applications.
2. Open Canto. It is not notarized by Apple yet, so macOS blocks the first launch: open **System Settings →
   Privacy & Security** and click **Open Anyway**.
3. Canto guides you through the rest: microphone and Accessibility access, and a speech model to download
   (or an OpenAI API key).

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

## Privacy

Audio and text stay on your Mac with on-device recognition. With OpenAI recognition or an AI skill on OpenAI, the
audio or the text is sent to OpenAI; skills on a local model keep the text on your Mac. Your API key is kept in the
macOS Keychain.

## License

MIT. Canto is built on [whisper.cpp](https://github.com/ggml-org/whisper.cpp),
[FluidAudio](https://github.com/FluidInference/FluidAudio), [Silero VAD](https://github.com/snakers4/silero-vad) and
[libfvad](https://github.com/dpirch/libfvad). The English list of Whisper hallucinations comes from
[DSP-AGH/ICASSP2025_Whisper_Hallucination](https://github.com/DSP-AGH/ICASSP2025_Whisper_Hallucination)
(MIT, see `Packages/CantoKit/Sources/CantoCore/Languages/LICENSE-whisper-hallucinations.txt`).

---

<a id="русский"></a>

## Русский

<p align="center">
  <img src="docs/images/screenshot-ru.png" alt="Canto: окно настроек, панель в меню-баре и индикатор записи">
</p>

**Canto** живёт в меню-баре. Удерживайте клавишу, говорите, и текст появится там, где стоит курсор: в мессенджере,
почте, заметках, редакторе кода или терминале.

### Возможности

- **Работает в любом приложении.** Глобальное сочетание клавиш или Caps Lock. Можно удерживать, а можно нажать
  один раз и говорить: паузы сами делят речь на фразы.
- **Приватно по умолчанию.** Речь распознаётся на вашем Mac моделью Whisper Large v3 Turbo на Metal или Parakeet v3
  на Neural Engine и никуда не отправляется, если вы не выбрали OpenAI.
- **OpenAI по желанию.** GPT-4o Transcribe или Whisper в облаке. Если сеть не отвечает, Canto распознаёт скачанной
  локальной моделью.
- **Меньше выдуманных слов.** Silero VAD отсекает тишину и шум ещё до распознавания, а известные галлюцинации
  Whisper («Спасибо за просмотр», титры субтитров, повторы одной фразы) убираются.
- **Чистый текст.** Оставить расшифровку как есть или аккуратно почистить. По желанию ИИ-скиллы, Markdown-файлы,
  которые можно править и добавлять: убрать слова-паразиты, поправить технические термины, перевести, убрать мат.
  Можно включить несколько сразу, они работают одним запросом через OpenAI или локальную модель (Ollama, LM Studio).
- **Словарь.** Термины вроде OpenAI, Node.js или AWS пишутся так, как вы их задали.
- **Мелочи.** Произносимая пунктуация, числа цифрами или прописью (с десятичными, дробями и падежами: «до пяти» →
  «до 5»), знаки валют («пятьдесят евро» → 50 €), фраза для нажатия Return, индикатор записи, история, интерфейс
  на русском, английском и иврите.

### Установка

1. Скачайте **Canto.dmg** из [последнего релиза](https://github.com/jehkinen/canto/releases/latest) и перетащите
   Canto в «Программы».
2. Откройте Canto. Приложение пока не нотаризовано Apple, поэтому macOS заблокирует первый запуск: откройте
   **Системные настройки → Конфиденциальность и безопасность** и нажмите **«Всё равно открыть»**.
3. Дальше Canto подскажет сам: доступ к микрофону и Универсальный доступ, загрузка модели распознавания
   (или ключ OpenAI).

Нужна macOS 14 Sonoma или новее, на Apple silicon или Intel.

### Приватность

При локальном распознавании звук и текст остаются на вашем Mac. При распознавании через OpenAI или со скиллом
через OpenAI звук или текст отправляются в OpenAI; скиллы на локальной модели оставляют текст на Mac. Ключ API
хранится в Связке ключей macOS.
