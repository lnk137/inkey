# Contributing to Inkey

Use small, focused commits after completing and checking each feature.
All commit subjects and bodies must be written in English.

Format: `<emoji> <type>: <description>`

| Type | Emoji | Purpose |
| --- | --- | --- |
| init | 🎉 | Initialize a project |
| feat | ✨ | Add functionality |
| fix | 🐛 | Fix a defect |
| docs | 📚 | Update documentation |
| style | 🎨 | Change formatting only |
| refactor | ♻ | Restructure without changing behavior |
| perf | ⚡ | Improve performance |
| test | ✅ | Add or update tests |
| chore | 🔧 | Maintain tooling or configuration |
| ci | 👷 | Change CI |
| build | 🏗 | Change the build system |
| revert | ⏪ | Revert a change |
| security | 🔒 | Improve security |
| release | 🚀 | Publish a version |
| delete | 🔥 | Remove code or files |
| upgrade | ⬆ | Upgrade dependencies |

Run `swift build` and relevant tests before committing. Keep README instructions
consistent with behavior. Do not commit generated app bundles, caches, local
preferences, or temporary screenshots. This repository has no external dependencies.

Configure the repository commit template with:

```sh
git config commit.template .gitmessage
```

## Documentation

Keep the English and Simplified Chinese overviews concise. Put detailed behavior
in `docs/guide.md`. Regenerate the README logo, previews and demonstration animations with
`./scripts/render-readme.sh`; it uses the app icon source and renders the actual
AppKit components with synthetic examples, without reading or changing the
user's drafts. Keep generated images in `docs/assets/` and scratch
build tools under the ignored `build/` directory.

## Interface localization

Interface strings live in `Sources/Inkey/Resources/<language>.lproj/Localizable.strings`.
Use stable `ui.*` keys in Swift and provide each key in every language. Use
positional `%1$@`, `%2$@`, and so on for dynamic values, allowing translators to
reorder them; pass their string values through `localized(_:arguments:)`.

To add a language, add its `.lproj` directory with a complete translation, add
its code and native display name to `InterfaceLanguage`, and declare the code
in `Resources/Info.plist` under `CFBundleLocalizations`. The settings picker
uses `InterfaceLanguage.allCases`. The selected language takes effect after the
app is restarted. AppKit system dialogs may follow macOS language settings.
Run `swift test --filter LocalizationTests` to check resource coverage and
format placeholders, and verify the packaged app in the new language.
