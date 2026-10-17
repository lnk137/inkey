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
