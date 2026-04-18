# Insight — Phase 1 Critical Fixes Checklist

## Task 1.1 — AllowsView: permissions flow ✅
**File:** `InsightApp/Views/Onboarding/Allow Screen/AllowsView.swift`
"Permitir acceso" calls `requestAllPermissions()` which triggers CLLocationManager, AVCaptureDevice, and CMMotionActivityManager before setting `didFinishOnboarding = true`.

## Task 1.2 — ProfileView: remove hardcoded PII ✅
**File:** `InsightApp/ProfileView.swift`
Removed hardcoded name "Grecia Saucedo" and phone "+52 81 1234 5678". Header now shows `selectedProfile.icon` + `selectedProfile.displayName`.

## Task 1.3 — Apple Privacy Manifest ✅
**File:** `InsightApp/PrivacyInfo.xcprivacy`
Created with `NSPrivacyTracking: false`, UserDefaults access reason `CA92.1`, and Location + Camera as non-tracked app-functionality data types.
> **Action required:** Drag `PrivacyInfo.xcprivacy` into the Xcode project navigator and confirm target membership checkbox is checked.

## Task 1.4 — Form validation ✅
**Files:**
- `InsightApp/Views/Onboarding/Sign up & Login Screens/SignUpView.swift`
- `InsightApp/Views/Onboarding/Sign up & Login Screens/LoginView.swift`

Both views now gate navigation behind `isFormValid`. On invalid submit, `showErrors = true` reveals red error labels below each failing field. Submit button renders at 50% opacity when the form is invalid.

**SignUp rules:** firstName non-empty, lastName non-empty, phoneNumber ≥ 10 digits, password ≥ 8 chars.
**Login rules:** phoneNumber non-empty, password ≥ 8 chars.

## Task 1.5 — Logout clears UserDefaults ✅
**File:** `InsightApp/ProfileView.swift` (logout button ~line 199)
Logout now calls `PersistenceService.shared.clearAll()` before `didFinishOnboarding = false`, clearing scannedTiles, lastDestination, and accessibilityProfile keys.

## Task 1.6 — Rename folder: "Sing up" → "Sign up" ✅
**Path:** `InsightApp/Views/Onboarding/Sign up & Login Screens/`
Folder renamed on disk. `project.pbxproj` uses UUIDs so no path patch needed.
> **Action required:** In Xcode's project navigator, right-click the group still showing "Sing up & Login Screens" → Rename → "Sign up & Login Screens" to sync the display name.
