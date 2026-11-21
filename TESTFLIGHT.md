# Put Swap on your iPhone with TestFlight (no Mac needed)

GitHub builds and uploads the app. You do the Apple and GitHub setup once, from any browser.

## 1. Apple (about 20 minutes, plus Apple's approval time)
1. Join the Apple Developer Program at developer.apple.com/programs ($99 a year). Individuals are usually
   approved within a day or two. A company account needs a D-U-N-S number and can take longer.
2. Find your **Team ID**: developer.apple.com/account, Membership details.
3. Pick a **bundle ID** you own, in reverse domain style, for example `com.yourcompany.swap`.
4. App Store Connect (appstoreconnect.apple.com), Apps, New App: iOS, name it, choose that bundle ID
   (register it first under Certificates, Identifiers & Profiles, Identifiers, if it isn't listed).
5. App Store Connect, Users and Access, Integrations, App Store Connect API, create a key with the **Admin**
   role. Write down the **Issuer ID** and **Key ID**, and download the `.p8` file. Apple only lets you
   download it once.

## 2. GitHub (5 minutes)
Repo, Settings, Secrets and variables, Actions.

Secrets:
- `ASC_KEY_ID`: the Key ID
- `ASC_ISSUER_ID`: the Issuer ID
- `ASC_KEY_P8`: open the `.p8` file in a text editor and paste everything, including the BEGIN and END lines

Variables:
- `APPLE_TEAM_ID`: your Team ID
- `BUNDLE_ID`: your bundle ID

## 3. Build and install
1. Actions tab, TestFlight, Run workflow. It takes about 10 minutes.
2. App Store Connect, your app, TestFlight: add yourself as an internal tester (your Apple ID must be a
   user on the account).
3. Install the TestFlight app on your iPhone, sign in, and install Swap.

Every run uploads a new build and bumps the build number automatically.

## Notes
- The first run can fail on provisioning if the API key role is too low. Use Admin.
- Internal testers (up to 100 people on your App Store Connect team) need no Apple review.
- Before a public App Store release you still need Sign in with Apple (the app offers Google login), a privacy
  policy, terms, and review of reported content.
