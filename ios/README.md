# Atlas — iOS app

SwiftUI + SwiftData. iOS 17+. Single-user, local-first. The data lives in a
SQLite file inside the app's container; SwiftData manages the schema.

## First run (on your Mac)

```bash
cd ios
./bootstrap.sh
open Atlas.xcodeproj
```

`bootstrap.sh` installs [XcodeGen](https://github.com/yonaskolb/XcodeGen)
via Homebrew if you don't have it, then materializes `Atlas.xcodeproj`
from `project.yml`. Run it again any time you add or rename files.

### In Xcode
1. **Select your iPhone** (or a simulator) from the device dropdown at the top.
2. Click the project root (`Atlas`) in the sidebar, then **Signing & Capabilities**.
3. Set **Team** to your paid Apple Developer account.
4. **Cmd + R**.

On first launch the app seeds itself with the four chapters from the spec
(Varanasi, Ireland MBA, Stratyfix seed, Health) plus todos, decisions,
journal entries, and inter-chapter links.

## Layout

```
ios/
├── project.yml              XcodeGen spec (sources, target settings, deployment target)
├── bootstrap.sh             One-shot xcodegen runner
└── Atlas/
    ├── Info.plist
    ├── App/                 @main entry + RootView (tab nav, capture FAB)
    ├── Models/              SwiftData @Model classes + Enums
    ├── Data/                AppContainer + Seed
    ├── Theme/               Colors / fonts / formatters / Hairline + Card modifiers
    ├── Views/
    │   ├── Today/           TodayView
    │   ├── Chapters/        ChaptersListView, ChapterCard, NewChapterSheet
    │   ├── ChapterDetail/   ChapterDetailView + Header + four tabs + sheets
    │   ├── Capture/         CaptureSheet (single textarea, three save targets)
    │   ├── Settings/        SettingsView + connector cards
    │   └── Components/      Chip, MetaLabel, SectionHeader
    └── Resources/
        └── Assets.xcassets  ColorPaper, ColorInk, ColorMoss, ColorEmber, etc.
```

## Design

- System `.serif` design (New York) for titles, default sans for body,
  `.monospaced` for metadata. Custom fonts (Instrument Serif, Manrope,
  JetBrains Mono) can be added later by bundling `.ttf` files in
  `Resources/Fonts/` and listing them under `UIAppFonts` in `Info.plist`.
- All colors live in the asset catalog as named colors — change once,
  applies everywhere.
- Light mode only for now (the warm paper palette is built for it).

## Resetting data

Delete the app from your phone, reinstall — first launch reseeds.

## Adding new files later

Drop them in the right `Atlas/...` folder, then run `./bootstrap.sh` again
to regenerate the project. XcodeGen reads everything under `Atlas/` based
on `project.yml`.
