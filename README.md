# Telegramus

Неофициальный клиент Telegram с открытым кодом на **Flutter + TDLib**.
Одна кодовая база для Windows, macOS, Linux, Android и iOS.

> Telegramus не связан с Telegram FZ-LLC и не является официальным клиентом.

## Что уже есть

- **TDLib через FFI** (`lib/src/tdlib/`): JSON-интерфейс `td_json_client`,
  один фоновый isolate с `td_receive` обслуживает все аккаунты сразу.
- **Мультиаккаунт** (`lib/src/accounts/`): у каждого аккаунта свой экземпляр
  TDLib и своя папка данных `<app support>/accounts/<id>/` (база, файлы).
  Все аккаунты работают одновременно, поэтому переключение мгновенное,
  а счётчики непрочитанного обновляются у всех.
- **Вход по номеру**: телефон → код → облачный пароль (2FA) → регистрация.
- **Список чатов** с аватарками, последним сообщением, непрочитанными,
  закреплёнными чатами и подгрузкой при прокрутке.
- **Переключатель аккаунтов**: колонка аватаров слева на широком экране,
  боковое меню на телефоне, `Ctrl/Cmd + 1…9` на десктопе. Экран каждого
  аккаунта строится заново при переключении, так что данные одного аккаунта
  никогда не показываются в другом.
- Состояние на **Riverpod 3**.

Дальше по плану: экран переписки, отправка сообщений, медиа, уведомления,
шифрование локальной базы.

## Структура

```
lib/
  main.dart
  src/
    app.dart                      # MaterialApp, проверка конфига и TDLib
    config/app_config.dart        # api_id / api_hash из --dart-define
    tdlib/
      td_json_bindings.dart       # FFI + поиск libtdjson на каждой платформе
      tdlib.dart                  # загрузка TDLib, receive-isolate, клиенты
      td_client.dart              # запросы с @extra, поток обновлений
    accounts/
      account.dart                # модель аккаунта
      account_repository.dart     # accounts.json + папки данных
      account_session.dart        # TDLib-клиент + состояние одного аккаунта
      accounts_controller.dart    # менеджер аккаунтов и Riverpod-провайдеры
      auth_state.dart
    features/
      auth/        accounts/       chats/       common/
native/<platform>/                # сюда кладутся собранные библиотеки TDLib
config/telegram.example.json      # шаблон ключей
```

## 1. Ключи Telegram API

1. Войдите на <https://my.telegram.org> → **API development tools** и создайте
   приложение. Получите `api_id` и `api_hash`.
2. Скопируйте шаблон и впишите ключи:

   ```bash
   cp config/telegram.example.json config/telegram.json
   ```

   `config/telegram.json` в `.gitignore` и **никогда не коммитится**.
3. Запускайте с этим файлом:

   ```bash
   flutter run --dart-define-from-file=config/telegram.json
   ```

   Для тестового сервера Telegram поставьте `"TELEGRAM_USE_TEST_DC": "true"`.

Ключи вшиваются в собранное приложение, это нормально для клиентов Telegram.
Главное, чтобы они не попадали в репозиторий.

## 2. Сборка TDLib

TDLib нужно собрать один раз под каждую платформу. Самый надёжный способ
получить команды под вашу систему: генератор инструкций
<https://tdlib.github.io/td/build.html> (выберите язык «Other» / JSON).
Сборка требует несколько ГБ памяти и занимает 10–40 минут.

```bash
git clone https://github.com/tdlib/td.git
cd td
```

### Linux

```bash
sudo apt-get install make git zlib1g-dev libssl-dev gperf php-cli cmake g++
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=../tdlib ..
cmake --build . --target install -j4
```

Скопируйте `td/tdlib/lib/libtdjson.so.<версия>` в
`native/linux/libtdjson.so`. При `flutter build linux` файл попадёт в
`bundle/lib/`.

### Windows

Нужны Visual Studio (C++), CMake, Git и [vcpkg](https://github.com/microsoft/vcpkg):

```powershell
.\vcpkg.exe install gperf:x64-windows openssl:x64-windows zlib:x64-windows
cd <путь к td>; mkdir build; cd build
cmake -A x64 -DCMAKE_INSTALL_PREFIX:PATH=../tdlib `
  -DCMAKE_TOOLCHAIN_FILE:FILEPATH=<vcpkg>/scripts/buildsystems/vcpkg.cmake ..
cmake --build . --target install --config Release
```

Скопируйте из `td/tdlib/bin` в `native/windows/` файл `tdjson.dll` и DLL
зависимостей (`libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `zlib1.dll`).
Они будут положены рядом с `.exe`.

### macOS

```bash
brew install gperf cmake openssl
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DOPENSSL_ROOT_DIR=$(brew --prefix openssl) \
  -DCMAKE_INSTALL_PREFIX:PATH=../tdlib ..
cmake --build . --target install -j4
```

Положите `libtdjson.dylib` в `native/macos/`, затем в Xcode
(`macos/Runner.xcworkspace`) → Runner → Build Phases → **Copy Files**
(Destination: Frameworks) добавьте этот файл. Для быстрой разработки можно
не встраивать библиотеку, а указать путь:
`TDJSON_PATH=/path/libtdjson.dylib flutter run -d macos ...`.

### Android

В репозитории TDLib есть готовые скрипты в `example/android`
(см. `example/android/README.md`): они скачивают NDK, собирают OpenSSL и
`libtdjson.so` под все ABI. Разложите результат так:

```
android/app/src/main/jniLibs/arm64-v8a/libtdjson.so
android/app/src/main/jniLibs/armeabi-v7a/libtdjson.so
android/app/src/main/jniLibs/x86_64/libtdjson.so
```

### iOS

Скрипты в `example/ios` собирают TDLib как статическую библиотеку /
xcframework. Добавьте её в таргет Runner и не дайте линкеру выкинуть
символы (`-force_load` или `-Wl,-u,_td_create_client_id` и т.д.). Код ищет
символы в самом процессе (`DynamicLibrary.process()`). Сборка под iOS в
каркасе пока не проверялась.

### Свой путь к библиотеке

На любой десктопной платформе можно указать файл явно:
`TDJSON_PATH=/abs/path/to/libtdjson.so flutter run ...`

## 3. Запуск

```bash
flutter pub get
flutter run -d linux   --dart-define-from-file=config/telegram.json
flutter run -d windows --dart-define-from-file=config/telegram.json
flutter run -d macos   --dart-define-from-file=config/telegram.json
flutter run            --dart-define-from-file=config/telegram.json  # Android/iOS
```

## Тесты

```bash
flutter analyze
flutter test
# с настоящей TDLib (два аккаунта доходят до шага ввода номера):
TDJSON_PATH=/path/to/libtdjson.so flutter test test/tdlib_integration_test.dart
```

## Условия Telegram API

Перед публикацией сборок прочитайте
[Telegram API Terms of Service](https://core.telegram.org/api/terms). Коротко:

- используйте **свои** `api_id`/`api_hash`;
- **не используйте название «Telegram» и логотип Telegram** как название или
  иконку приложения и явно указывайте, что клиент неофициальный;
- не злоупотребляйте API (спам, массовые действия, обход ограничений):
  за это банят и ключи, и аккаунты;
- бережно относитесь к безопасности и приватности данных пользователей.

## Лицензия

Код проекта под [MIT](LICENSE). TDLib распространяется под Boost Software
License 1.0.
