# Lumen — reviewer access template

Do not commit real reviewer credentials to Git. Copy this template into Play
Console and replace the bracketed values only in the private App access form.

## Suggested Play Console text

Lumen is a media player and supplies no content. Core functionality requires a
user-provided authorized HTTPS source. Use the dedicated legal review source
below. It contains only media that we own or are authorized to distribute and
will remain active for the full review period.

Source type: `[Xtream-compatible account / HTTPS M3U playlist]`

### If using an account source

- Server URL: `[https://review.example.com]`
- Username: `[review username]`
- Password: `[review password]`

Steps:

1. Launch Lumen and accept the legal notice.
2. Select the account-source sign-in option.
3. Enter the server URL, username, and password above.
4. Select **Connect**.
5. Browse only the sections provided by the review source.
6. Open an item to test playback, search, favorites, history, and remote
   navigation.

### If using an M3U source

- Playlist URL: `[https://review.example.com/lumen-review.m3u]`
- Optional EPG URL: `[https://review.example.com/lumen-review.xml]`

Steps:

1. Launch Lumen and accept the legal notice.
2. Select the M3U playlist option.
3. Enter the playlist and optional EPG URLs above.
4. Select **Open playlist**.
5. Browse the available Live section and test playback, search, favorites, and
   remote navigation.

## Reviewer notes

- No OTP, VPN, location spoofing, purchase, or separate registration is
  required.
- The source works over HTTPS from outside the developer's local network.
- Lumen does not provide or sell this source and has no affiliation with an
  IPTV reseller or content provider.
- If Google reports an access problem, replace the private Play Console
  credentials immediately and confirm the source from an external network.
