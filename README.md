# Travel Desk

Private quoting assistant for a travel agency owner. Flutter, Android.

## Get the free APK (no installs on your side)
1. Create a free GitHub account and a **private** repository.
2. Upload this whole folder (including the hidden `.github` folder) to the `main` branch.
3. Open the **Actions** tab, then **Build APK**, then **Run workflow**.
4. After about 6 minutes, open the finished run and download **travel-desk-apk**. Unzip it and copy `app-release.apk` to the phone.
5. On the phone, allow installing from your file manager when asked.

## First use
- Create your username and password. There is no recovery, so keep them safe.
- Rates tab: add destinations, then transport routes. "Load sample data" adds clearly labelled SAMPLE rates.
- Quote tab: fill in the enquiry, tap Create plan, then Copy or WhatsApp.

## How it works
- Offline planner: every number comes from your own rates. Checks dates, routes, rooms, peak season, children, markup and tax.
- Online extras (optional): live weather (Open-Meteo) and currency (Frankfurter). Only the destination name or currency code is sent. No credentials or client details are ever sent.

## Security
- Password stored as a salted PBKDF2-SHA256 hash (120,000 rounds) in Android Keystore encrypted storage.
- Lockout after 5 wrong attempts, growing delays.
- Auto-lock after 3 minutes in background. Screenshots and recent-apps preview are blocked.
- Cloud backup is disabled. No analytics and no accounts on any server.

## Known limits
- The APK is signed with a debug key (fine for private installs, not for Play Store).
- No on-device LLM yet. Wording uses the rules engine and templates.
- Live flight and hotel prices are not included; those APIs need paid keys.
