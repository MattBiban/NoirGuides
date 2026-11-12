# Releasing Noir Guides

Every version tag pushed to GitHub publishes the addon by itself: a GitHub release with the zip, and the same file uploaded to CurseForge. This page covers the one-time setup and the routine.

## One-time setup

1. **Create the CurseForge project** (World of Warcraft → Addons), using the texts in `docs/CURSEFORGE.md`. CurseForge reviews new projects before they go live.
2. **Note the project ID.** It is shown on the project's page on CurseForge, in the "About project" box.
3. **Create an API token** on CurseForge: account settings → API tokens → generate one named "GitHub".
4. **Give the token and the ID to GitHub** from a terminal in this repository. `gh secret set` asks for the token and never shows or stores it anywhere else:

   ```
   gh secret set CF_API_KEY
   gh variable set CF_PROJECT_ID --body <project id>
   ```

5. **Pick the game version.** List what CurseForge accepts and find WoW Forever's entry:

   ```
   $env:CF_API_KEY = "<token>"      # PowerShell; only for this terminal
   node tools/cf_versions.js
   ```

   Then set its ID (several IDs can be given, comma-separated):

   ```
   gh variable set CF_GAME_VERSIONS --body <id>
   ```

6. Optional: `gh variable set CF_RELEASE_TYPE --body release` once the addon leaves beta. The default is `beta`.

Until steps 4 and 5 are done, a tag still makes the GitHub release; the CurseForge step says it skipped the upload.

## Each release

1. Run the checks locally (they need `tools/data/`, which is not in the repository):

   ```
   cd tools
   npm test
   npm run test:lua
   npm run sim
   ```

2. Bump `## Version:` in `NoirGuides/NoirGuides.toc` and add the matching `## <version>` entry at the top of `CHANGELOG.md` (the tests check that the two agree).
3. Commit, tag and push:

   ```
   git commit -am "Noir Guides 0.2.2"
   git tag v0.2.2
   git push origin main --tags
   ```

4. Watch the **Actions** tab on GitHub. The `Release` workflow refuses a tag that does not match the toc version, then builds, releases and uploads. The CurseForge changelog is the version's entry from `CHANGELOG.md`.
