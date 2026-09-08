# Lumen app agent instructions

## Android release rule

Every requested Android release must handle both distribution channels:

1. Build, verify, and submit the signed `com.talhaashraf.lumen` Android App
   Bundle (`.aab`) to the Google Play closed-testing track.
2. Build and verify the separately signed
   `com.talhaashraf.lumen.community` APK, publish it as
   `Lumen-Android.apk` on the rolling GitHub `latest` release, keep Downloader
   code `4560142` pointing to it, and post the short Discord notice.

Do not call the release complete until package ID, signing, version code, and
download resolution have been checked for both channels. If Play review,
signing, or account access is pending, report the Play channel as pending.

Never commit keystores, `key.properties`, passwords, service-account JSON,
provider credentials, or webhook URLs. CI copies belong only in encrypted
repository secrets. See `docs/android-release-process.md` for the checklist.
