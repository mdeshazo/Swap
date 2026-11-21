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

## Turn on Google sign in
1. Google Cloud Console, APIs and Services, OAuth consent screen: set it up (app name, support email).
2. Credentials, Create OAuth client ID, type **Web application**. Under Authorized redirect URIs add
   `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`. Copy the client ID and secret.
3. Supabase, Authentication, Providers, Google: switch it on and paste the client ID and secret.
4. Supabase, Authentication, URL Configuration, Redirect URLs: add `swap://auth-callback`.
5. Run the app. "Continue with Google" appears on the sign in screen in backend mode.

Email and password keeps working beside it. If someone signs up with email and later uses Google
with the same address, Supabase links them to one account by default.

## Before App Store submission
- Apple rule 4.8: because the app offers Google login, it must also offer Sign in with Apple (or an
  equivalent privacy first login). Add Sign in with Apple before you submit.
- Replace the placeholder Google button icon with Google's official "G" logo and follow their
  branding rules.
- Add a Terms of Use and Privacy Policy, link them in the app and in App Store Connect.
- Someone has to review the `reports` table (Supabase dashboard, Table editor) and act on it.
- Chat checks for new messages every 4 seconds. Swap to Supabase Realtime later if you want instant delivery.
- Listings have a city name only. Distance search needs coordinates, which is a later step.
- Add a bundle ID you own, signing team, and app icon.
