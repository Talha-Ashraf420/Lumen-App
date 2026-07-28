# Lumen — Play Console answer sheet

Use this sheet for the first Play Console submission. Recheck every answer
against the exact bundle being uploaded; Google treats inaccurate declarations
as a policy issue.

## App setup

- App name: `Lumen`
- Default language: `English (United States)`
- App or game: `App`
- Free or paid: `Free`
- Category: `Video Players & Editors`
- Package name: `com.talhaashraf.lumen`
- Contact email: `talhaashraf81@gmail.com`
- Privacy policy:
  `https://lumen-launch.vercel.app/privacy`

## Store listing

- Short description:
  `Private media player for your own authorized playlists and services.`
- Full description: copy
  `fastlane/metadata/android/en-US/full_description.txt`.
- Do not add provider names, premium-service brands, sports leagues, claims of
  included content, or unlicensed media artwork to the listing.

## App content declarations

### Ads

- Contains ads: `No`
- Recheck if an advertising or attribution SDK is ever added.

### App access

- Select: `All or some functionality is restricted`.
- Paste the final private reviewer instructions derived from
  `docs/reviewer-access-template.md`.
- The reviewer source must remain active, require no OTP or location bypass,
  work from Google's review network, and contain only content you own or are
  authorized to distribute.

### Target audience

- Recommended initial selection: `18 and over`.
- Do not target children.
- Keep the icon, screenshots, descriptions, and demo source suitable for a
  general store audience even though the declared audience is adult.

### Content rating

- Complete the IARC questionnaire truthfully.
- Lumen is a media player, not a content provider.
- Answer content questions based on everything a reviewer can reach through
  the submitted demo source and on the app's user-generated-content
  capabilities. Do not infer a rating from the app category.

### News, health, finance, government, and social features

- Select `No` for declarations that ask whether Lumen is a news, health,
  finance, government, social, dating, gambling, or real-money app.
- Re-evaluate if functionality changes.

### Account creation and deletion

- Lumen does not create a Lumen account.
- Users supply credentials for an independent service or a playlist URL.
- Do not claim that provider credentials create an account with Lumen.
- A user can remove a saved source profile, clear watch history and downloads,
  clear Android app storage, or uninstall Lumen. Provider-side account
  deletion must be requested from that provider.

## Data Safety — conservative first-release draft

Select `Yes` when asked whether the app collects or shares any required user
data. In Play terminology, data can count as collected when the app transmits
it off the device even when Lumen does not operate the destination server.

Declare the closest current Play Console data types for:

- User IDs or account identifiers: a provider username is sent to the
  user-configured provider to authenticate and load the library. It is required
  for account-based sources and used for app functionality.
- App activity, search terms, or other user-generated content: media requests
  and searches may be sent to the configured provider. Optional title searches
  may be sent to TMDB or OpenSubtitles to return metadata or subtitles.

Handling and purposes:

- Purpose: `App functionality`.
- Advertising or marketing: `No`.
- Analytics: `No`.
- Sold: `No`.
- Used for account management by Lumen: `No`.
- Processing may be optional for metadata and subtitle searches, but provider
  authentication and playback requests are required to use an account source.
- Data is encrypted in transit on Android because release builds accept HTTPS
  sources only.
- Provider credentials, profiles, favorites, history, preferences, and
  download state are stored locally. Sensitive Android state uses encrypted
  platform storage.
- Lumen does not operate a developer backend that receives or retains provider
  credentials.

For the `shared` question, use the conservative answer `Yes` unless the exact
Play Console wording clearly places a transfer under a user-initiated or
service-provider exception. The configured provider receives credentials and
media requests, while optional metadata/subtitle services receive title search
details. Never choose an exception merely to produce a more attractive label.

### Security practices

- Data encrypted in transit: `Yes`, for the Android release.
- Users can request deletion: explain the local deletion controls above and
  that provider-side data is controlled by the provider.
- Independent security review: `No`, unless a qualifying review is completed.

## Android TV

- Opt in at `Setup > Advanced settings > Form factors > Android TV`.
- Upload the same AAB unless a dedicated TV track is deliberately used.
- Mention Android TV in the full description.
- Add at least one accurate 16:9 Android TV screenshot and the 320 × 180 TV
  banner.
- Test the exact release with only D-pad, center/select, Back, and the TV
  keyboard before rollout.

## Release

- Enroll in Google Play App Signing.
- Upload the newly signed `.aab`, never an APK and never the bundle produced
  with the retired key.
- Keep the Play-generated app signing key and the local upload key conceptually
  separate: Google protects the app signing key; the local key only authorizes
  future uploads.
- Start with internal testing, then run the closed test required for new
  personal accounts before applying for production access.
