# Contributing to ParkAlong

Thanks for helping make Melbourne parking information easier to use.

## Before you start

- Search existing issues before opening a duplicate.
- Open an issue before a large user-facing or architectural change.
- Keep normal app flows backed by real reusable sources. Deterministic fixtures belong only in tests.
- Do not commit raw parking archives, credentials, signing files, or local build products.

## Development setup

```bash
brew install xcodegen
xcodegen generate
open ParkingAvailability.xcodeproj
```

ParkAlong targets iOS 17 and later. Simulator work does not need a paid signing account.

## Checks

Run these before submitting a pull request:

```bash
xcodebuild test \
  -project ParkingAvailability.xcodeproj \
  -scheme ParkingAvailability \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO

python3 -m unittest discover -s Scripts/tests -v
```

Network smoke checks are deliberately separate from deterministic tests:

```bash
python3 Scripts/smoke_live_api.py
```

## Pull requests

A good pull request:

- explains the user problem and the chosen behavior;
- keeps files focused along the existing service and engine boundaries;
- adds or updates deterministic tests;
- includes screenshots for visual changes;
- preserves City of Melbourne attribution;
- documents any new external source, provider link, or data limitation.

By contributing, you agree that your contribution is licensed under the repository's MIT License. City of Melbourne data retains its separate CC BY 4.0 terms.
