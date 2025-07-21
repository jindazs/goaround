## Plan to Address Codebase Issues

1. **Web Site Limit Hardcoding**
   - Problem: `SettingsView` initializes arrays with `Array(repeating: "", count: 20)`.
   - Fix: Extract this limit to a shared constant (e.g., `MaxWebSites`) in a new file `Constants.swift`. Replace the hard-coded `20` in `SettingsView` and `ContentView` with the constant.
   - Benefit: A single source of truth allows easier future changes.

2. **Unused Properties and Functions in `ContentView`**
   - Problem: `lastTranslation`, `goToNext()`, `goToPrevious()`, and possibly other helpers are never used.
   - Fix: Remove unused variables and functions after verifying no side effects. If navigation helpers are needed, refactor existing code to call them; otherwise delete them.
   - Benefit: Cleaner codebase and smaller surface for bugs.

3. **Unobserved Notification `pageDownInWebView`**
   - Problem: `ContentView` posts `pageDownInWebView` but no view listens for it.
   - Fix: Either implement an observer in `WebViewContainer` to scroll the current page down, or remove the notification and related code if the feature isn't required.
   - Benefit: Avoids dead code and clarifies behavior.

4. **Unused `CustomSwipeGestureModifier`**
   - Problem: Declared but never applied.
   - Fix: Decide whether the custom gesture is necessary. If so, apply `.customSwipeGesture()` to the appropriate views. If not needed, delete the entire modifier file.
   - Benefit: Eliminates unnecessary code or adds the missing gesture feature.

5. **Duplicate Web View Implementations**
   - Problem: Both `WebView` and `WebViewContainer` implement a `UIViewRepresentable` web view, but only the latter is used.
   - Fix: Remove the unused `WebView.swift` file or consolidate any unique logic into `WebViewContainer` if required.
   - Benefit: Reduces confusion and maintenance burden.

6. **Notification Observer Cleanup**
   - Problem: `WebViewContainer` adds an observer but never removes it, which can cause duplicates on view recreation.
   - Fix: Implement `deinit` in `WebViewContainer.Coordinator` or use `onDisappear` in the SwiftUI view to remove the observer.
   - Benefit: Prevents memory leaks and duplicated events.

7. **Missing Xcode Project for Tests**
   - Problem: Repository includes `goaround.xctestplan` but lacks `goaround.xcodeproj`.
   - Fix: Commit the project file or remove the test plan. Alternatively migrate to Swift Package Manager to run tests via `swift test`.
   - Benefit: Ensures testing instructions are consistent with repository contents.

