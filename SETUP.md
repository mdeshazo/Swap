# Swap setup

## Run in demo mode (no backend)
1. `brew install xcodegen`
2. `xcodegen` in this folder, then open `Swap.xcodeproj` and Run.

Demo mode keeps everything on the phone and fakes seller replies.

## Turn on the real backend (Supabase)
1. Create a Supabase project (supabase.com).
2. SQL Editor: paste all of `supabase/schema.sql` and run it once.
3. Authentication, Providers, Email: decide whether to require email confirmation.
   If it's on, new users confirm by email before they can sign in.
4. Project Settings, API: copy the Project URL and the `anon` public key.
5. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and fill it in.
   Use the anon key only. Never put the `service_role` key in the app.
6. `xcodegen`, then Run. The app now uses real accounts, shared listings, photo storage, and chat.

## Before App Store submission
- Add a Terms of Use and Privacy Policy, link them in the app and in App Store Connect.
- Someone has to review the `reports` table (Supabase dashboard, Table editor) and act on it.
- Chat checks for new messages every 4 seconds. Swap to Supabase Realtime later if you want instant delivery.
- Listings have a city name only. Distance search needs coordinates, which is a later step.
- Add a bundle ID you own, signing team, and app icon.
