# Publishing MediaKeep

## Language policy

Publish all GitHub-facing content in English, including README files, user guides, release notes, announcements, commit messages, issues, pull requests, workflow descriptions, and sponsorship text. Keep app localization resources multilingual and preserve third-party license texts as supplied.

## Describe the product clearly

Lead with three practical benefits:

1. Save directly into the folder the user chooses, with up to nine named folder shortcuts for easy organization.
2. Save the whole video or just a chosen start/end range, including adjusted subtitle timestamps.
3. Automatically choose the best available quality up to the selected limit, and request source-provided subtitles/prefer dubbed audio using the chosen app language.

Always qualify quality and language availability. The default quality ceiling is 4K, not unlimited resolution. The app does not upscale, generate translations, or synthesize voice dubbing. If matching subtitles or dubbed audio are absent, describe the fallback accurately. A custom range limits the saved file, not necessarily the network data downloaded.

## Release checklist

- Update the native bundle version, desktop version, package names, workflow package filters, and download links consistently.
- Build and test the real target-platform executables.
- Review actual screenshots, glyph coverage, source archive contents, and English documentation.
- Create the intended numeric Git tag explicitly, for example `v1.0.1`, on the verified source commit.
- Create a draft release with that exact tag. Add concise English highlights, platform requirements, install instructions, limitations, test evidence, and any migration notes.
- Upload all platform packages, source archive, optional screenshot archive, and `SHA256SUMS.txt` before publishing.
- Check that package names match the app updater's platform suffixes.
- Publish the release with its explicit numeric tag and mark it latest when appropriate.
- Verify the unauthenticated latest-release response, all download URLs, checksums, and README image links.
- Keep documentation-only changes distinct from new application functionality. Do not imply an executable was rebuilt when only GitHub text changed.

## Sponsorship

The supported account is https://github.com/sponsors/Choikuidong. The funding file enables the repository's Sponsor entry. Explain that support is optional and that MediaKeep remains free regardless of sponsorship. Check the public sponsor page and repository funding link, but do not make a payment to test them.
