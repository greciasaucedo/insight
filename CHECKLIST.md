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

---

## Phase 4 — Authentication & Profile Backend

## Task 4.1 — AuthUser model ✅
**File:** `InsightApp/Models/AuthUser.swift`
`Codable` struct: `id`, `firstName`, `lastName`, `phone`, `displayName`. Persisted to UserDefaults.

## Task 4.2 — AuthService ✅
**File:** `InsightApp/Views/Services/AuthService.swift`
GoTrue REST via URLSession. Virtual email `{digits}@insight.app` lets users auth with phone+password.
- `signUp(firstName:lastName:phone:password:)` → creates Supabase auth.users entry
- `signIn(phone:password:)` → returns JWT session
- `signOut()` → revokes server token, clears local session
- `updateInfo(firstName:lastName:)` → updates user_metadata
- `changePassword(newPassword:)` → updates password
- Session persisted across app restarts via UserDefaults.
- Typed `AuthError` with Spanish messages for all GoTrue error codes.
> **Action required (Supabase dashboard):**
> Authentication → Configuration → **Disable "Confirm email"**

## Task 4.3 — SignUpView calls AuthService ✅
**File:** `InsightApp/Views/Onboarding/Sign up & Login Screens/SignUpView.swift`
Button shows ProgressView while loading. On success → navigates to PersonalizationView (continues onboarding). On failure → shows red `authError` message in Spanish.

## Task 4.4 — LoginView calls AuthService ✅
**File:** `InsightApp/Views/Onboarding/Sign up & Login Screens/LoginView.swift`
On success → sets `didFinishOnboarding = true` (bypasses re-onboarding, goes straight to map). On failure → shows error. Removed wrong navigation to PersonalizationView.

## Task 4.5 — ProfileView shows real user data ✅
**File:** `InsightApp/ProfileView.swift`
Header shows `AuthUser.displayName` and phone number from `AuthService.shared.currentUser` (falls back to accessibility profile name if unauthenticated).
- **Editar información**: sheet with firstName/lastName fields → calls `AuthService.updateInfo`
- **Cambiar contraseña**: sheet with new+confirm password → validates match + ≥8 chars → calls `AuthService.changePassword`
- **Cerrar sesión**: calls `AuthService.signOut()` + `PersistenceService.clearAll()` + resets onboarding flag

## Task 4.6 — Auth token used in all Supabase requests ✅
**Files:** `InsightApp/Views/Services/TileAPIService.swift`, `InsightApp/Views/Services/SupabaseService.swift`
`makeRequest` uses `AuthService.shared.accessToken` as Bearer when authenticated; falls back to anon key.
`TileSavePayload` includes `user_id` from `AuthService.shared.currentUser?.id`.
`ProfilePayload` includes `user_id`, `first_name`, `last_name`, `phone`.

## Task 4.7 — Supabase SQL migration ⚠️ MANUAL STEP
Run in Supabase SQL editor:
```sql
-- Extend user_profiles to store real user data
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS user_id    uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name  text,
  ADD COLUMN IF NOT EXISTS phone      text;

-- Prevent duplicate profiles per user (skip if constraint already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'user_profiles_user_id_key'
  ) THEN
    ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_user_id_key UNIQUE (user_id);
  END IF;
END $$;

-- Link tiles to authenticated users
ALTER TABLE accessibility_tiles
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id);
```

## Task 4.9 — Profile card redesign ✅
**File:** `InsightApp/ProfileView.swift`
New header card (same size/material as before):
- **Avatar circle (88 pt)**: shows photo from Supabase Storage (`AsyncImage`) or local `UIImage` after pick, falls back to `person.circle.fill` placeholder. Shows `ProgressView` overlay while uploading.
- **Camera button** (bottom-right badge): `PhotosPicker` — selects from Photos library, compresses to JPEG 75%, uploads to `storage/avatars/{userId}/avatar.jpg` (upsert), updates `user_metadata.avatar_url`.
- **Long-press context menu** on avatar: "Eliminar foto" → deletes from Storage + clears URL.
- **Info rows**: `person.fill` + displayName, `phone.fill` + phone number, accessibility profile icon + profile name.

## Task 4.10 — Supabase Storage bucket ⚠️ MANUAL SQL
Run Query 3 from the session to create the `avatars` bucket with 5 MB limit, JPEG/PNG/WebP allow-list, and four RLS policies (public read, owner insert/update/delete).

## Task 4.11 — Supabase RLS enabled ⚠️ MANUAL SQL
Run Queries 1 & 2 to enable RLS on `user_profiles` and `accessibility_tiles` with per-user policies. Prevents cross-user data access.

## Task 4.12 — Console noise (simulator only) ℹ️ NOT A BUG
Lines beginning with `PerfPowerTelemetry`, `CAMetalLayer`, `default.csv`, `PPSClientDonation`,
`RBSServiceErrorDomain`, `elapsedCPUTimeForFrontBoard` are **simulator sandbox restrictions** — they
never appear on a physical device and require no code changes.
