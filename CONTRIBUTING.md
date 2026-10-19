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
in `docs/guide.md`. Regenerate the README logo and preview with
`./scripts/render-readme.sh`; it uses the app icon source and renders the actual
AppKit components with a non-personal example, without reading or changing the
user's drafts. Keep generated images in `docs/assets/` and scratch
build tools under the ignored `build/` directory.
