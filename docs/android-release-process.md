# Android release process

Every Android release has two separate distribution variants.

## Google Play closed testing

- Package: `com.talhaashraf.lumen`
- Artifact: signed Android App Bundle (`.aab`)
- Signing: dedicated Google Play upload key; Google Play App Signing owns the
  distribution key.
- Delivery: upload the verified bundle to the Alpha closed-testing track and
  submit the release for review/rollout.

The CI artifact is named `Lumen-Google-Play-aab`. It must not be attached to the
public GitHub release. Automated Play submission additionally requires a
dedicated Play Console service account; until that is configured, the final
Console upload remains an authenticated release step.

The local upload key lives at `android/app/lumen-play-upload.p12`, its public
certificate at `android/app/lumen-play-upload-certificate.pem`, and its local
Gradle configuration at `android/key.properties`. All three paths are ignored
by Git. CI receives the same signing material only through encrypted repository
secrets.

## Downloader and Discord

- Package: `com.talhaashraf.lumen.community`
- Artifact: signed APK named `Lumen-Android.apk`
- Delivery: rolling GitHub release tagged `latest`
- Downloader code: `4560142`
- Downloader URL: <https://aftv.news/4560142>
- Announcement: short plain-text Discord webhook message after the GitHub
  release is updated.

The Downloader URL permanently points at the stable GitHub `latest` APK URL, so
publishing a new `Lumen-Android.apk` updates what the same code downloads.

## Completion checklist

1. Tests and static analysis pass.
2. Play AAB and Community APK both build with their correct package identities.
3. Both artifacts pass signing verification.
4. The Community APK replaces the GitHub `latest` asset and its direct URL
   resolves successfully.
5. Downloader code `4560142` downloads that current APK.
6. The simple Discord notice is posted.
7. The Play AAB is submitted to closed testing and the Console shows it in
   review or serving testers.

Never commit keystores, passwords, `key.properties`, service-account JSON, or
Discord webhook URLs.
