# Публикация DiskCheck в Mac App Store

## Что уже настроено в проекте

- **App Sandbox** — `DiskCheck/DiskCheck.entitlements`
- **Hardened Runtime** — включён в Release
- **Privacy Manifest** — `DiskCheck/PrivacyInfo.xcprivacy`
- **Info.plist** — категория Utilities, описания доступа, `ITSAppUsesNonExemptEncryption = false`
- **Иконка** — `DiskCheck/Assets.xcassets/AppIcon.appiconset` (генерируется скриптом)
- **ExportOptions** — `Config/ExportOptions.plist` для `app-store-connect`
- **Скрипт сборки** — `Scripts/archive_appstore.sh`

## Перед первой отправкой

### 1. Apple Developer Program

Нужна активная подписка [Apple Developer Program](https://developer.apple.com/programs/) (99 USD/год).

### 2. Bundle ID и подпись

1. [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → создайте App ID: `com.lomostudios.diskcheck`
2. Включите capabilities: **App Sandbox**, **Hardened Runtime**
3. В Xcode откройте `DiskCheck.xcodeproj` → target **DiskCheck** → **Signing & Capabilities**
4. Выберите **Team** (ваш Apple Developer Team)
5. Убедитесь, что **Automatically manage signing** включён

Или задайте Team ID в `Config/Release.xcconfig`:

```
DEVELOPMENT_TEAM = ABCDE12345
```

### 3. Иконка (опционально заменить)

Сгенерировать placeholder-иконку:

```bash
swift Scripts/generate_app_icon.swift DiskCheck/Assets.xcassets/AppIcon.appiconset
```

Для App Store Connect нужен **1024×1024** (`icon_1024.png`). Замените на финальный дизайн перед релизом.

### 4. Скриншоты

Подготовьте в App Store Connect (минимум для macOS):

| Размер | Назначение |
|--------|------------|
| 1280 × 800 | Основной скриншот |
| 1440 × 900 | Retina (рекомендуется) |

Сделайте 3–5 скринов: sunburst, дерево, категории, ИИ, панель тома.

### 5. Метаданные (черновик)

**Название:** DiskCheck  
**Подзаголовок:** Анализ диска в стиле DaisyDisk  
**Описание:**

> DiskCheck показывает, что занимает место на Mac: интерактивная sunburst-диаграмма, дерево папок, категории (кэши, node_modules, .nosync, Xcode) и ИИ-советы по очистке.
>
> • Визуализация диска по уровням  
> • Категории типового «мусора»  
> • Корзина с отложенным удалением  
> • iCloud / .nosync, снапшоты Time Machine, SMART  
> • Apple Intelligence и Ollama (опционально)

**Ключевые слова:** диск, очистка, анализ, место, daisydisk, кэш, icloud  
**Категория:** Utilities  
**URL поддержки:** (укажите сайт или email)  
**Политика конфиденциальности:** (обязательна — можно страницу «данные не покидают устройство»)

### 6. Заметки для ревью (Review Notes)

```
DiskCheck — утилита анализа дискового пространства.

• Для полного сканирования системных папок пользователь должен выдать «Полный доступ к диску» в Системных настройках → Конфиденциальность. Без этого сканируются доступные папки и выбранные пользователем каталоги.

• ИИ: используется Apple Intelligence (на macOS 26+) или локальный Ollama на 127.0.0.1 — опционально, без отправки данных на наши серверы.

• Удаление файлов — только по явному действию пользователя через встроенную корзину.

• diskutil/tmutil вызываются только для чтения SMART и списка локальных снапшотов Time Machine.
```

## Сборка и загрузка

### Вариант A — скрипт

```bash
chmod +x Scripts/archive_appstore.sh
./Scripts/archive_appstore.sh
```

Требуется настроенная подпись в Xcode Keychain.

### Вариант B — Xcode

1. Scheme: **DiskCheck** → **Any Mac (Apple Silicon)** или **My Mac**
2. **Product → Archive**
3. **Distribute App → App Store Connect → Upload**

### App Store Connect

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **My Apps** → **+** → New App
2. Platform: macOS, Bundle ID: `com.lomostudios.diskcheck`
3. Заполните версию **1.0.0**, загрузите билд, скриншоты, описание
4. **App Privacy** → Data Not Collected (приложение не собирает данные на сервер)
5. **Export Compliance** → No (уже в Info.plist)

## Ограничения Sandbox (важно)

| Функция | Поведение в App Store |
|---------|------------------------|
| Скан тома целиком | Нужен **Full Disk Access** от пользователя |
| Выбор папки | Работает через security-scoped bookmark |
| diskutil / tmutil | Может быть ограничен sandbox — SMART/TM показываются, если система разрешает |
| Ollama | Локальная сеть (127.0.0.1), описано в Info.plist |
| Удаление в корзину | Только для доступных пользователю путей |

## Чеклист перед Submit

- [ ] Team ID настроен, архив подписывается без ошибок
- [ ] Тест Release-сборки на чистом Mac (без FDA и с FDA)
- [ ] Иконка 1024×1024 финальная
- [ ] Скриншоты загружены
- [ ] Privacy Policy URL указан
- [ ] Support URL указан
- [ ] Версия `1.0.0 (1)` в App Store Connect совпадает с билдом
- [ ] Прогнаны unit-тесты: `xcodebuild test -scheme DiskCheck`

## Версионирование

Меняйте в `Config/Base.xcconfig`:

```
MARKETING_VERSION = 1.0.0   # отображаемая версия
CURRENT_PROJECT_VERSION = 1 # build number
```

После правок: `xcodegen generate`
