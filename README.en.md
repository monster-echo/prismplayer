# PrismPlayer

**Turn your own NAS, cloud drive and local files into a private cinema on HarmonyOS.**

PrismPlayer is a native video player for HarmonyOS. Connect your own WebDAV, SMB, Plex, Emby, AList or S3 sources, get an automatic poster wall, and play 4K HDR files directly. No bundled content, and your media and credentials are never uploaded.

---

## What it does

- **Your own sources, directly**: WebDAV, SMB (SMB2/3), Plex, Emby, AList, S3 (AWS / Cloudflare R2 / MinIO), IPTV / M3U, local videos, and public video links (Bilibili, Douyin).
- **Smooth 4K HDR playback**: hardware decoding first, with automatic FFmpeg fallback for codecs the device cannot decode — including 10-bit HEVC.
- **Subtitles that look right**: ASS / SSA effects, bilingual subtitles, subtitle search (SubDL / OpenSubtitles), automatic external and embedded track matching, precise delay adjustment.
- **Poster wall and episode management**: TMDB metadata for posters, synopses and seasons; movies and series grouped automatically; progress remembered per episode.
- **Built for binge-watching**: skip intro / outro, playback speed, audio track switching, aspect ratio, gesture controls.
- **Consistent on all three form factors**: phone, tablet and HarmonyOS PC (2in1); keyboard and mouse shortcuts plus multi-window on PC, and Handoff between phone and tablet.
- **Private by default**: hide selected folders behind a pattern lock.

## Supported sources

| Type | Notes |
|---|---|
| WebDAV | Synology, fnOS, QNAP, Nextcloud and more |
| SMB | LAN shares, SMB2 / SMB3 |
| Plex / Emby | Use your existing libraries |
| AList / OpenList | Aliyun Drive, Quark, 115 and others |
| S3 | AWS S3, Cloudflare R2, MinIO and other object storage |
| IPTV / M3U | Live channel playback |
| Local video | Files on the device |
| Online links | Paste a public video link and play |

## Getting started

1. **Add a source**: Settings → Sources → Add source, enter the address and credentials, then browse.
2. **Scrape posters (optional)**: Settings → TMDB metadata, enter your own TMDB API key and scan; playback works without it.
3. **Play**: open a title from the library, or resume from Recently Watched.

> Credentials are encrypted with the system keystore (HUKS) and stay on device. The app has no backend server and never forwards your credentials to a third party.

## PrismPlayer Pro

The free version includes **one source**. Pro unlocks unlimited sources and all features.

| Plan | Price | Details |
|---|---|---|
| Personal Lifetime | ¥48 | One-time purchase, shared across phone / tablet / HarmonyOS PC under the same Huawei ID |
| Family Lifetime | ¥68 | Adds Huawei Family Group sharing (up to 5 people) |

- One-time purchase via Huawei In-App Purchase — **not a subscription**, no auto-renewal;
- After switching or reinstalling, restore with the same Huawei ID: Settings → PrismPlayer Pro → Restore purchases;
- Refunds follow Huawei AppGallery policy.

## Privacy and legal

- Your media, credentials and watch history stay on your device;
- No advertising, analytics or crash-reporting SDK is included;
- Full details: [Privacy Policy](https://auth.zhongbei.tech/legal/privacy?app=prismplayer) and [Terms of Service](https://auth.zhongbei.tech/legal/terms?app=prismplayer), also available in-app under Settings.

## Feedback

- Official community (Feishu): Settings → Contact & Share → Official community, scan the QR code;
- Email: hello@zhongbei.tech
- For playback issues, please include the codec details (e.g. 4K HEVC 10-bit) and your device model.

## Requirements

- HarmonyOS NEXT, on phone, tablet and HarmonyOS PC (2in1);
- Network sources must be reachable from your device (same LAN, or public access);
- Metadata and subtitle search require internet access and depend on third-party services.

---

中文版：[README.md](README.md)
