# App Store submission — privacy & health checklist

Everything you need to answer Apple's forms for enhale, plus the health-data
gotchas. Work top to bottom.

---

## 0. Before you touch App Store Connect
- [ ] **Apple Developer Program** active ($99/yr).
- [ ] **Backend is live on Railway** and `https://<your-app>.up.railway.app/health`
      returns `{"status":"ok"}`.
- [ ] **App defaults to the Railway URL** (so a fresh install works for the
      reviewer — they won't type a backend URL).
- [ ] **Privacy Policy URL works:** `https://<your-app>.up.railway.app/privacy`
      loads in a browser.

---

## 1. Privacy Policy URL
App Store Connect → your app → **App Information** → **Privacy Policy URL**:

```
https://<your-app>.up.railway.app/privacy
```

(Served by the backend — see `enhale_backend/legal/router.py`. Edit the copy or
contact email there and redeploy to change it.)

---

## 2. App Privacy "nutrition label" (App Store Connect → **App Privacy**)
This is a guided questionnaire. Answer **"Yes, we collect data"**, then declare
each type below. For **every** type: Purpose = **App Functionality** only;
Linked to the user = **Yes**; Used for tracking = **No**.

| Apple data type | Maps to (in enhale) |
|---|---|
| **Health & Fitness** → Health / Fitness | Apple Health: workouts, sleep, activity, vitals; blood-work biomarkers |
| **Contact Info** → Email Address | Your account login email |
| **User Content** → Other User Content | Meal text/voice transcripts, uploaded lab report files |
| **Identifiers** → User ID | The account ID tying your data together |
| **Health** (sensitive) | Lab reports & symptom/medication profile |

For each of the above, the toggles are:
- **Used to track you?** → No (do not add to any tracking bucket)
- **Linked to your identity?** → Yes
- **Purposes** → check **App Functionality** only (NOT Analytics, NOT
  Advertising, NOT Product Personalization for third parties)

> If you later add crash reporting or analytics, you must revisit this.

---

## 3. HealthKit-specific review requirements
Apps using HealthKit get extra scrutiny. Make sure:
- [ ] **Privacy Policy URL is set** (required for HealthKit — done in §1).
- [ ] Health data is **not** used for advertising and **not** sold — stated in
      the policy, and reflected in §2.
- [ ] **Usage strings** present in `Info.plist` (already in `project.yml`):
      `NSHealthShareUsageDescription`.
- [ ] The app has a clear reason to read each Health type (the pre-permission
      "Connect Apple Health" screen covers this).
- [ ] HealthKit entitlement enabled (already in `project.yml` →
      `com.apple.developer.healthkit`).

---

## 4. App Review Information (the notes reviewers read)
App Store Connect → your app version → **App Review Information**:
- [ ] **Provide a demo account.** Create a real account against the live Railway
      backend and put the credentials here:
      - Email: `reviewer@enhale.app` (or any real account you make)
      - Password: `<the password you set>`
- [ ] **Notes:** e.g. *"Voice/text meal logging with LLM nutrition parsing,
      Apple Health correlation, and lab-report insights. Sign in with the demo
      account above. Health features need a physical device; core logging and
      insights work in Simulator."*
- [ ] Confirm the backend will stay up during review (Railway, not your Mac).

---

## 5. Store listing metadata
- [ ] **Category:** Health & Fitness.
- [ ] **Age rating:** complete the questionnaire (likely 12+ due to health/medical
      references — answer honestly).
- [ ] **Screenshots** for required device sizes (6.7" iPhone at minimum).
- [ ] **Description, keywords, support URL, marketing name.**
- [ ] **Support URL** — can reuse the privacy page host or a mailto page.

---

## 6. Build & submit
1. Xcode → set the project's **Team** to your paid Developer account.
2. `xcodegen generate` (picks up new files), open `Enhale.xcodeproj`.
3. **Product → Archive** → **Distribute App → App Store Connect → Upload**.
4. Build appears in **TestFlight** — install on your phone to dogfood (no 7-day
   expiry).
5. Attach the build to a version, fill §1–§5, **Submit for Review**.
6. First review is typically 1–3 days; fix-and-resubmit if they flag anything.

---

## Most likely rejection reasons for enhale (and the fix)
- **Backend unreachable during review** → keep Railway up; give a working demo
  account pointed at it.
- **Privacy label doesn't match behavior** → the §2 table matches what the app
  actually does; keep it honest if you add SDKs.
- **Missing/weak Health justification** → the pre-permission screen + usage
  strings + policy cover this.
