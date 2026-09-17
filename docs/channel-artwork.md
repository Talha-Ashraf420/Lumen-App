# Channel artwork resolution

Lumen does not ship channel logos. Providers supply `stream_icon` (Xtream) or
`tvg-logo` (M3U). The artwork is metadata, not part of the video stream.

## Source order

1. Keep a usable, channel-specific provider logo. Resolve a relative M3U
   `tvg-logo` against the playlist URL.
2. Use a cached XMLTV `<channel><icon>` by exact `tvg-id`/channel ID, then an
   unambiguous normalized channel name. A provider image remains primary unless
   it is identified as a shared placeholder; XMLTV can serve as its failure
   fallback.
3. In a background enrichment pass, use IPTV-org's channel and logo manifests
   by exact channel ID or unambiguous name/country match. Only raster formats
   supported by the app are selected. The manifests are cached for seven days;
   there is no per-channel provider request.
4. If no reliable match exists, show Lumen's neutral live-TV icon. Do not assign
   a guessed broadcaster logo to an unrelated channel.

Some providers reuse one country flag or generic service badge as the artwork
for an entire region. Lumen treats an identical provider URL shared by at least
four distinct channel brands as a placeholder and seeks a channel-specific
XMLTV/public match. Variants of one brand can still share their logo. This is a
conservative URL-based heuristic, not image recognition; different URLs serving
the same flag cannot be identified without fetching and comparing those images.

The public catalog is incomplete. If a provider has no channel-specific logo
and there is no exact guide/public match, the neutral icon is expected. A future
per-channel manual override could address those remaining cases without fuzzy
automatic matches.

## Open-source references

- [Kodi IPTV Simple channel-logo settings](https://github.com/kodi-pvr/pvr.iptvsimple#channel-logos): provider/M3U and XMLTV logo preferences, plus local/remote paths.
- [Kodi IPTV Simple M3U/XMLTV mapping](https://github.com/kodi-pvr/pvr.iptvsimple#supported-m3u-and-xmltv-elements): `tvg-id`, `tvg-name`, `tvg-logo`, XMLTV channel IDs and icons.
- [IPTV-org API](https://github.com/iptv-org/api#logos): channel IDs, alternate names, countries, and logo URLs/format metadata.
