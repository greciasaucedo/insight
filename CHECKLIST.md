# Insight — Development Checklist

---

## Phase 1 — Critical Fixes

## Task 1.1 — AllowsView: permissions flow ✅
**File:** `InsightApp/Views/Onboarding/Allow Screen/AllowsView.swift`
"Permitir acceso" calls `requestAllPermissions()` which triggers CLLocationManager, AVCaptureDevice, and CMMotionActivityManager before setting `didFinishOnboarding = true`.

## Task 1.2 — ProfileView: remove hardcoded PII ✅
**File:** `InsightApp/ProfileView.swift`
Removed hardcoded name "Grecia Saucedo" and phone "+52 81 1234 5678". Header now shows active profile icon + displayName.

## Task 1.3 — Apple Privacy Manifest ✅
**File:** `InsightApp/PrivacyInfo.xcprivacy`
Created with `NSPrivacyTracking: false`, UserDefaults access reason `CA92.1`, and Location + Camera as non-tracked app-functionality data types.
> **Action required:** Drag `PrivacyInfo.xcprivacy` into the Xcode project navigator and confirm target membership checkbox is checked.

## Task 1.4 — Form validation ✅
**Files:**
- `InsightApp/Views/Onboarding/Sign up & Login Screens/SignUpView.swift`
- `InsightApp/Views/Onboarding/Sign up & Login Screens/LoginView.swift`

Both views gate navigation behind `isFormValid`. On invalid submit, `showErrors = true` reveals red error labels. Submit button renders at 50% opacity when invalid.

**SignUp rules:** firstName non-empty, lastName non-empty, phoneNumber ≥ 10 digits, password ≥ 8 chars.
**Login rules:** phoneNumber non-empty, password ≥ 8 chars.

## Task 1.5 — Logout clears UserDefaults ✅
**File:** `InsightApp/ProfileView.swift`
Logout calls `PersistenceService.shared.clearAll()` before `didFinishOnboarding = false`.

## Task 1.6 — Rename folder: "Sing up" → "Sign up" ✅
**Path:** `InsightApp/Views/Onboarding/Sign up & Login Screens/`
Folder renamed on disk. `project.pbxproj` uses UUIDs so no path patch needed.
> **Action required:** In Xcode's project navigator, right-click the group still showing "Sing up & Login Screens" → Rename → "Sign up & Login Screens".

---

## Phase 2 — Accessibility Profile System

## Task 2.1 — PenaltyWeights model ✅
**File:** `InsightApp/Models/AccessibilityProfile.swift`
Added `PenaltyWeights` struct (stairs, obstacle, slope, limited as Double) and `penaltyWeights` computed var on `AccessibilityProfile` with per-profile multipliers.

## Task 2.2 — PersistenceService typed profile ✅
**File:** `InsightApp/Views/Services/Persistenceservice.swift`
`saveProfile(_ profile: AccessibilityProfile)` and `loadProfile() -> AccessibilityProfile` (defaults to `.standard`).

## Task 2.3 — ProfileService as ObservableObject ✅
**File:** `InsightApp/Views/Services/ProfileService.swift`
Singleton converted to `ObservableObject` with `@Published private(set) var currentProfile`. `setProfile(_:)` saves and publishes. Injected as `@EnvironmentObject` from app root.

## Task 2.4 — adjustedPenalty scoring ✅
**File:** `InsightApp/Views/Services/AccessibilityScoringService.swift`
Added `adjustedPenalty(for tile:profile:) -> Double` using `PenaltyWeights` multipliers. User-scanned tiles +40%, low-confidence tiles −40%.

## Task 2.5 — RouteEngine uses adjustedPenalty ✅
**File:** `InsightApp/Views/Route/RouteEngine.swift`
`penaltyFor(tile:profile:)` now delegates to `AccessibilityScoringService.adjustedPenalty`. Removed old inline hardcoded adjustments.

## Task 2.6 — RouteViewModel reacts to profile changes ✅
**File:** `InsightApp/Views/Route/RouteViewModel.swift`
Added `subscribeToProfileChanges()` — subscribes to `ProfileService.shared.$currentProfile`, updates `activeProfile`, and auto-calls `reevaluateWithCurrentTiles()` on change.

## Task 2.7 — Profile badge in RouteView ✅
**File:** `InsightApp/Views/Route/RouteView.swift`
Profile badge pill already renders `vm.activeProfile.displayName` (was present from Phase 1). Now reactive via the ViewModel subscription.

## Task 2.8 — Profile picker in ProfileView ✅
**File:** `InsightApp/ProfileView.swift`
Picker uses `@ObservedObject private var profileService = ProfileService.shared`. Tap calls `profileService.setProfile(profile)`. Header and picker reflect live `currentProfile`.

## Task 2.9 — Profile-aware route explanation strings ✅
**Files:** `InsightApp/Views/Services/AccessibilityScoringService.swift`, `InsightApp/Views/Route/RouteEngine.swift`
`explanationMessage(for:profile:)` returns per-profile Spanish strings injected into `RouteEvaluation.explanations`.

---

## Phase 3 — Supabase Backend Integration

## Task 3.1 — SupabaseConfig: git-ignored credentials ✅
**Files:** `InsightApp/Views/Services/SupabaseConfig.swift` (git-ignored, real keys), `InsightApp/Config/SupabaseConfig.example.swift` (committed template, commented-out stub)
`.gitignore` covers both `InsightApp/Views/Services/SupabaseConfig.swift` and `InsightApp/Config/SupabaseConfig.swift`.
> **Action required:** Do NOT add `SupabaseConfig.example.swift` to the Xcode target.

## Task 3.2 — Supabase Swift SDK ✅ (not needed)
**Note:** `SupabaseService` uses `URLSession` directly — no SPM package required. All Supabase REST API calls are handled natively.

## Task 3.3 — SupabaseService.swift SQL schema ✅
**File:** `InsightApp/Views/Services/TileAPIService.swift`
SQL `CREATE TABLE accessibility_tiles` schema with indexes documented as comment block.

## Task 3.4 — RemoteTile.swift public model ✅
**File:** `InsightApp/Models/RemoteTile.swift`
`Decodable` struct with snake_case field names matching Supabase columns.
`toAccessibilityTile()` conversion method. Replaces the former private struct inside `SupabaseService`.

## Task 3.5 — TileAPIService.swift ✅
**File:** `InsightApp/Views/Services/TileAPIService.swift`
`saveTile(_ tile:, isSimulated:) async throws` — inserts to Supabase, logs + rethrows on HTTP ≥ 400.
`fetchNearbyTiles(lat:lng:radiusKm:) async throws -> [RemoteTile]` — bounding box `lat±(km/111)`, `lng±(km/111)`, `is_simulated=false`.

## Task 3.6 — HeatmapStore.loadRemoteTiles ✅
**File:** `InsightApp/Views/Map/MapView.swift`
`loadRemoteTiles(near:)` fetches via `TileAPIService`, converts via `toAccessibilityTile()`, deduplicates at <5 m proximity (0.000045°), appends to `baseTiles`.
Called from `MapView.body` via `.task { await store.loadRemoteTiles(near: vm.region.center) }`.

## Task 3.7 — ScanView wired to TileAPIService ✅
**File:** `InsightApp/Views/Detecta/ScanView.swift`
After local `addTile`, background `Task` calls `TileAPIService.shared.saveTile(lastTile, isSimulated: demo)`. `isUsingDemo` captured before Task to survive `reset()`. Error caught and discarded — UX never blocked.
