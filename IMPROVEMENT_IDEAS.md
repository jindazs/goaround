# GoAround Improvement Ideas

## Priority Fixes

1. Add an explicit completion action to the initial settings screen so first launch can move into the browser view.
2. Use a single `WebSiteSetting` data model for URL and in-app/external-link behavior instead of parallel arrays.
3. Register `WKWebView` notification observers through the coordinator and remove them on deinit.
4. Make page down notifications work for the active web view.
5. Reload or replace a `WKWebView` when its configured URL changes.

## Follow-Up Improvements

1. Create only the current web view and its nearby neighbors to reduce memory and network load.
2. Separate reload, back, and page-down actions so gestures do exactly one predictable thing.
3. Add URL normalization and validation, including automatic `https://` completion.
4. Add first-run gesture hints for tap, double tap, swipe, and long press actions.
5. Add per-site modes such as timeline, comic full-screen, and normal browsing.
6. Persist per-site scroll position when useful, especially for web comics.
7. Replace placeholder tests with coverage for settings migration, URL ordering, and web-view refresh behavior.
8. Commit the Xcode project and test targets so a fresh clone can build without local-only files.
