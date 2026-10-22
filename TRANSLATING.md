<div align="center">

# Translating SpaceMap

<a href="#english"><img src="docs/buttons/english.svg" width="200" alt="English"></a>
&nbsp;&nbsp;
<a href="#%D1%80%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9"><img src="docs/buttons/russian.svg" width="200" alt="Русский"></a>

</div>

## English

All interface text lives in [`Resources/Translations`](Resources/Translations), one folder per
language. [`en.lproj`](Resources/Translations/en.lproj) is the original that translations start
from. Each folder holds three files:

- `Localizable.strings` with the interface text, one line per phrase: `"menu.up" = "Go Up";`
- `Localizable.stringsdict` with the words that change with a number, like "1 file" and "5 files"
- `InfoPlist.strings` with what macOS shows on the app's behalf: privacy prompts and the Get Info
  window

### Try your translation without building the app

1. Get the English folder. Download
   [`Resources/Translations/en.lproj`](Resources/Translations/en.lproj) from this repository, or in
   Finder right-click `SpaceMap.app`, choose Show Package Contents and open `Contents/Resources`.
2. Copy `en.lproj` and name the copy after your language code: `de.lproj` for German, `fr.lproj`
   for French, `pt-BR.lproj` for Brazilian Portuguese.
3. In `Localizable.strings`, translate the text to the right of each `=`. Leave the keys on the
   left alone. Keep the placeholders exactly as they are written (`%@`, `%1$@`, `%2$@`, `%%`); you
   can move them around in the sentence. `%@` is a value SpaceMap puts in, such as a file name or a
   size, and `%1$@`, `%2$@` are the first and second values.
4. Translate the words in `Localizable.stringsdict` (see [plural forms](#plural-forms)) and the
   texts in `InfoPlist.strings`.
5. In SpaceMap choose SpaceMap → Language → Open Translations Folder and put your folder there.
   It is `~/Library/Application Support/SpaceMap/Translations`.
6. Switch back to SpaceMap. Your language is now in SpaceMap → Language. If you edit a file that
   SpaceMap has already loaded, quit and reopen the app to see the change.

Phrases you have not translated yet show up in English, so you can work in parts. A folder in the
translations folder also takes priority over the built-in one with the same name, which lets you
fix a built-in translation in place.

macOS reads `InfoPlist.strings` only from inside the app, so those texts appear once your
translation is part of a release.

### Plural forms

Each entry in `Localizable.stringsdict` looks like this:

```xml
<key>NSStringLocalizedFormatKey</key>
<string>%2$@ %1$#@files@</string>
<key>files</key>
<dict>
    ...
    <key>one</key>
    <string>file</string>
    <key>other</key>
    <string>files</string>
</dict>
```

`%2$@` is the number and `%1$#@files@` is where the word goes. Translate the words under `one`
and `other`, and change the line in `NSStringLocalizedFormatKey` if your language puts the number
somewhere else. Languages differ in how many forms they have: English has `one` and `other`,
Russian has `one`, `few`, `many` and `other`. Add or remove keys to match the
[CLDR plural rules](https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html)
for your language. The possible keys are `zero`, `one`, `two`, `few`, `many` and `other`, and
`other` is always required. SpaceMap uses the system's plural rules, so it picks the right form on
its own.

### Send your translation

1. Fork the repository and put your folder into `Resources/Translations`.
2. Run `swift test` on a Mac if you can. It checks that the files parse, that every English key is
   translated and that the placeholders match. GitHub runs the same check on your pull request, so
   you can also skip this step and read the result there.
3. Open a pull request. You don't need to change any code: the build adds every folder in
   `Resources/Translations` to the app and to its list of languages.

If you don't use git, open an [issue](https://github.com/renkagod/spacemap/issues) and attach your
folder as a zip.

When the English file gets new phrases, they show up in English in other languages until someone
translates them, and `swift test` lists the missing keys.

## Русский

<a href="#english"><img src="docs/buttons/english-dim.svg" width="200" alt="English"></a>
<a href="#%D1%80%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9"><img src="docs/buttons/russian.svg" width="200" alt="Русский"></a>

Тексты интерфейса лежат в [`Resources/Translations`](Resources/Translations), по папке на язык.
Оригинал, с которого делают переводы, это [`en.lproj`](Resources/Translations/en.lproj). В каждой
папке три файла:

- `Localizable.strings`: тексты интерфейса, по строке на фразу: `"menu.up" = "Go Up";`
- `Localizable.stringsdict`: слова, которые меняются вместе с числом («1 файл», «5 файлов»)
- `InfoPlist.strings`: то, что macOS показывает за приложение, то есть запросы доступа и окно
  «Свойства»

### Проверить перевод без сборки

1. Возьми английскую папку: скачай
   [`Resources/Translations/en.lproj`](Resources/Translations/en.lproj) из репозитория или открой
   в Finder `SpaceMap.app` через «Показать содержимое пакета» и зайди в `Contents/Resources`.
2. Скопируй `en.lproj` и назови копию кодом своего языка: `de.lproj` для немецкого, `uk.lproj`
   для украинского, `pt-BR.lproj` для бразильского португальского.
3. В `Localizable.strings` переведи текст справа от каждого `=`. Ключи слева не трогай.
   Подстановки (`%@`, `%1$@`, `%2$@`, `%%`) оставь ровно такими, как они написаны, переставлять
   внутри фразы их можно. `%@` это значение, которое подставит SpaceMap (имя файла, размер),
   `%1$@` и `%2$@` это первое и второе значения.
4. Переведи слова в `Localizable.stringsdict` (про формы слов ниже) и тексты в `InfoPlist.strings`.
5. В SpaceMap выбери SpaceMap → Язык → Открыть папку переводов и положи туда свою папку.
   Это `~/Library/Application Support/SpaceMap/Translations`.
6. Вернись в SpaceMap: твой язык появится в меню SpaceMap → Язык. Если правишь файл, который
   SpaceMap уже загрузил, перезапусти приложение.

Непереведённые фразы показываются по-английски, так что переводить можно по частям. Папка из папки
переводов важнее встроенной с тем же именем, так можно поправить и встроенный перевод.

`InfoPlist.strings` macOS читает только изнутри приложения, эти тексты появятся, когда перевод
войдёт в релиз.

### Формы слов

В `Localizable.stringsdict` строка `%2$@ %1$#@files@` значит: `%2$@` это число, на место
`%1$#@files@` встанет слово. Слова лежат под ключами форм. В английском формы `one` и `other`, в
русском `one`, `few`, `many` и `other`. Оставь те, что есть в твоём языке, по
[правилам CLDR](https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html).
Всего бывают `zero`, `one`, `two`, `few`, `many` и `other`, а `other` нужен всегда. Нужную форму
SpaceMap выбирает сам по правилам системы.

### Прислать перевод

1. Сделай форк и положи свою папку в `Resources/Translations`.
2. Если есть Mac, запусти `swift test`: он проверит, что файлы читаются, все английские ключи
   переведены и подстановки совпадают. GitHub запустит ту же проверку на пулл-реквесте, так что
   можно посмотреть результат там.
3. Открой пулл-реквест. Код менять не нужно: сборка сама добавит в приложение каждую папку из
   `Resources/Translations`.

Если git не нужен, открой [issue](https://github.com/renkagod/spacemap/issues) и приложи папку
архивом.

Когда в английском файле появляются новые фразы, в других языках они показываются по-английски,
пока их не переведут, а `swift test` перечислит недостающие ключи.
