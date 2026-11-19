import { MediaSource, RemoteFileEntry } from './Types';

export interface ArtworkPalette {
  top: string;
  bottom: string;
  accent: string;
}

const PALETTES: ArtworkPalette[] = [
  { top: '#1E2D52', bottom: '#0D1322', accent: '#60A5FA' },
  { top: '#2E1F47', bottom: '#110E1E', accent: '#A78BFA' },
  { top: '#13373A', bottom: '#09181B', accent: '#2DD4BF' },
  { top: '#3B1E28', bottom: '#160B11', accent: '#FB7185' },
  { top: '#3A2816', bottom: '#161009', accent: '#FBBF24' },
  { top: '#1B2E40', bottom: '#0B131C', accent: '#38BDF8' }
];

export class MediaArtwork {
  static resolve(url: string): ResourceStr {
    if (url === 'local://poster_bbb') return $r('app.media.poster_bbb');
    if (url === 'local://poster_sintel') return $r('app.media.poster_sintel');
    if (url === 'local://poster_scifi') return $r('app.media.poster_scifi');
    if (url === 'local://backdrop_bbb') return $r('app.media.backdrop_bbb');
    if (url === 'local://backdrop_sintel') return $r('app.media.backdrop_sintel');
    return url;
  }

  /** Returns a deterministic film-grade dark palette derived from title for artwork-free NAS items. */
  static paletteFor(title: string): ArtworkPalette {
    let hash = 0;
    for (let i = 0; i < title.length; i++) {
      hash = ((hash * 31) + title.charCodeAt(i)) >>> 0;
    }
    return PALETTES[hash % PALETTES.length];
  }

  /** Resolves bespoke vector SVG icon for NAS / cloud presets and saved sources. */
  static sourceIcon(src: MediaSource): Resource {
    if (src.type === 'alist') return $r('app.media.ic_cloud_alist');
    if (src.type === 'smb') return $r('app.media.ic_protocol_smb');
    if (src.type === 'plex') return $r('app.media.ic_protocol_plex');
    if (src.type === 's3') return $r('app.media.ic_protocol_s3');
    if (src.type === 'youtube') return $r('app.media.ic_protocol_youtube');
    if (src.type === 'douyin') return $r('app.media.ic_protocol_douyin');
    if (src.type === 'emby') return $r('app.media.ic_protocol_emby');
    if (src.type === 'iptv') return $r('app.media.ic_protocol_iptv');
    const lower = src.name.toLowerCase();
    if (lower.includes('synology') || lower.includes('群晖')) return $r('app.media.ic_nas_synology');
    if (lower.includes('fnos') || lower.includes('飞牛')) return $r('app.media.ic_nas_fnos');
    if (lower.includes('qnap') || lower.includes('威联通')) return $r('app.media.ic_nas_qnap');
    return $r('app.media.ic_protocol_webdav');
  }

  static sourceBadgeLabel(src: MediaSource): string {
    if (src.type === 'alist') return 'ALIST 302';
    if (src.type === 'smb') return 'SMB2/3';
    if (src.type === 's3') return 'S3 对象存储';
    if (src.type === 'youtube') return 'YOUTUBE';
    if (src.type === 'douyin') return '抖音视频';
    if (src.type === 'emby') return 'EMBY';
    if (src.type === 'iptv') return 'IPTV / 流';
    return src.type.toUpperCase();
  }

  static presetIcon(label: string): Resource {
    const lower = label.toLowerCase();
    if (lower.includes('s3') || lower.includes('r2') || lower.includes('minio') || lower.includes('oss')) {
      return $r('app.media.ic_protocol_s3');
    }
    if (lower.includes('youtube')) return $r('app.media.ic_protocol_youtube');
    if (lower.includes('douyin') || lower.includes('抖音')) return $r('app.media.ic_protocol_douyin');
    if (lower.includes('emby') || lower.includes('jellyfin')) return $r('app.media.ic_protocol_emby');
    if (lower.includes('iptv') || lower.includes('m3u')) return $r('app.media.ic_protocol_iptv');
    if (lower.includes('plex')) return $r('app.media.ic_protocol_plex');
    if (lower.includes('smb') || lower.includes('samba')) return $r('app.media.ic_protocol_smb');
    if (lower.includes('alist')) return $r('app.media.ic_cloud_alist');
    if (lower.includes('synology') || lower.includes('群晖')) return $r('app.media.ic_nas_synology');
    if (lower.includes('fnos') || lower.includes('飞牛')) return $r('app.media.ic_nas_fnos');
    if (lower.includes('qnap') || lower.includes('威联通')) return $r('app.media.ic_nas_qnap');
    return $r('app.media.ic_protocol_webdav');
  }

  static fileEntryIcon(entry: RemoteFileEntry): Resource {
    if (entry.isDirectory) return $r('app.media.ic_file_folder');
    if (entry.isVideo) return $r('app.media.ic_file_video');
    if (entry.isSubtitle) return $r('app.media.ic_file_subtitle');
    if (entry.name.toLowerCase().endsWith('.nfo')) return $r('app.media.ic_file_nfo');
    return $r('app.media.ic_file_doc');
  }
}
