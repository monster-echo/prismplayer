import { relationalStore, preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../common/Constants';
import {
  AppSettings,
  HiddenFolderRule,
  MediaItem,
  MediaSource,
  MediaSourceType,
  ProTier,
  SubtitleLanguageMode,
  SubtitleTrackOption,
  ThemeMode,
  VaultEntry,
  VaultEntryKind,
  WatchHistoryRecord
} from '../common/Types';
import { CryptoVault } from './CryptoVault';

export class MediaDatabase {
  private rdb: relationalStore.RdbStore | null = null;
  private prefs: preferences.Preferences | null = null;

  async init(context: common.Context): Promise<void> {
    if (!this.prefs) {
      this.prefs = await preferences.getPreferences(context, AppConstants.PREFS_NAME);
    }
    if (!this.rdb) {
      const config: relationalStore.StoreConfig = {
        name: AppConstants.DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      this.rdb = await relationalStore.getRdbStore(context, config);
      await this.createTables();
    }
  }

  private async createTables(): Promise<void> {
    if (!this.rdb) return;
    await this.rdb.executeSql(`
      CREATE TABLE IF NOT EXISTS media_sources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        base_url TEXT NOT NULL,
        root_path TEXT NOT NULL,
        username TEXT NOT NULL,
        password_enc TEXT NOT NULL,
        allow_insecure_tls INTEGER NOT NULL DEFAULT 0,
        cache_alist_302 INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_scanned_at INTEGER NOT NULL DEFAULT 0,
        extra_json TEXT NOT NULL DEFAULT '{}'
      )
    `);
    try {
      await this.rdb.executeSql(`ALTER TABLE media_sources ADD COLUMN extra_json TEXT NOT NULL DEFAULT '{}'`);
    } catch (_e) {
      // Column already exists
    }
    await this.rdb.executeSql(`
      CREATE TABLE IF NOT EXISTS media_items (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        source_type TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        stream_url TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        media_type TEXT NOT NULL,
        series_key TEXT NOT NULL,
        series_title TEXT NOT NULL,
        season_no INTEGER NOT NULL DEFAULT 1,
        episode_no INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL,
        original_title TEXT NOT NULL DEFAULT '',
        year INTEGER NOT NULL DEFAULT 0,
        overview TEXT NOT NULL DEFAULT '',
        poster_url TEXT NOT NULL DEFAULT '',
        backdrop_url TEXT NOT NULL DEFAULT '',
        rating REAL NOT NULL DEFAULT 0,
        quality_tag TEXT NOT NULL DEFAULT '',
        tmdb_id INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        subtitle_url TEXT NOT NULL DEFAULT '',
        subtitle_tracks_json TEXT NOT NULL DEFAULT '[]',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL
      )
    `);
    try {
      await this.rdb.executeSql(`ALTER TABLE media_items ADD COLUMN subtitle_tracks_json TEXT NOT NULL DEFAULT '[]'`);
    } catch (_e) {
      // Column already exists
    }
    try {
      await this.rdb.executeSql(`ALTER TABLE media_items ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0`);
    } catch (_e) {
      // Column already exists
    }
    await this.rdb.executeSql(`
      CREATE TABLE IF NOT EXISTS watch_history (
        item_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subtitle_label TEXT NOT NULL DEFAULT '',
        poster_url TEXT NOT NULL DEFAULT '',
        stream_url TEXT NOT NULL,
        source_id TEXT NOT NULL,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        audio_track_index INTEGER NOT NULL DEFAULT -1,
        subtitle_track_index INTEGER NOT NULL DEFAULT -1,
        subtitle_delay_ms INTEGER NOT NULL DEFAULT 0,
        playback_rate REAL NOT NULL DEFAULT 1.0,
        mask_enabled INTEGER NOT NULL DEFAULT -1,
        mask_ytop REAL NOT NULL DEFAULT -1,
        mask_ybottom REAL NOT NULL DEFAULT -1,
        updated_at INTEGER NOT NULL,
        finished INTEGER NOT NULL DEFAULT 0
      )
    `);
    try {
      await this.rdb.executeSql(`ALTER TABLE watch_history ADD COLUMN mask_enabled INTEGER NOT NULL DEFAULT -1`);
      await this.rdb.executeSql(`ALTER TABLE watch_history ADD COLUMN mask_ytop REAL NOT NULL DEFAULT -1`);
      await this.rdb.executeSql(`ALTER TABLE watch_history ADD COLUMN mask_ybottom REAL NOT NULL DEFAULT -1`);
    } catch (_e) {
      // Columns already exist
    }
    await this.rdb.executeSql(`
      CREATE TABLE IF NOT EXISTS hidden_folders (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        folder_path TEXT NOT NULL,
        folder_name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    `);
    await this.rdb.executeSql(`
      CREATE TABLE IF NOT EXISTS vault_entries (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        target_key TEXT NOT NULL,
        title TEXT NOT NULL,
        poster_url TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    `);
  }

  async loadSettings(): Promise<AppSettings> {
    const defaults: AppSettings = {
      themeMode: 'system',
      cacheBudgetMb: AppConstants.DEFAULT_CACHE_MB,
      preferHardwareDecode: true,
      hardwareSupportedFormats: AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS,
      tmdbApiKey: '',
      tmdbApiHost: AppConstants.DEFAULT_TMDB_HOST,
      tmdbImageBase: AppConstants.DEFAULT_TMDB_IMAGE_BASE,
      autoSkipIntroSec: 0,
      autoSkipOutroSec: 0,
      subtitleFontSizeFp: 20,
      subtitleLanguageMode: 'all',
      subtitleBgEnabled: true,
      subtitleBgOpacityPercent: 35,
      subtitleVerticalOffsetVp: 0,
      burnSubMaskDefault: false,
      subdlApiKey: '',
      proTier: 'free',
      privacyAccepted: false,
      vaultPinCipher: ''
    };
    if (!this.prefs) return defaults;
    const rawHwFormats = await this.prefs.get('hardwareSupportedFormats', '') as string;
    let hwFormats: string[] = AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS;
    if (rawHwFormats && rawHwFormats.trim().length > 0) {
      hwFormats = rawHwFormats.split(',').map(s => s.trim().toLowerCase()).filter(s => s.length > 0);
    }
    return {
      themeMode: (await this.prefs.get('themeMode', defaults.themeMode) as string) as ThemeMode,
      cacheBudgetMb: await this.prefs.get('cacheBudgetMb', defaults.cacheBudgetMb) as number,
      preferHardwareDecode: await this.prefs.get('preferHardwareDecode', defaults.preferHardwareDecode) as boolean,
      hardwareSupportedFormats: hwFormats,
      tmdbApiKey: await this.prefs.get('tmdbApiKey', defaults.tmdbApiKey) as string,
      tmdbApiHost: await this.prefs.get('tmdbApiHost', defaults.tmdbApiHost) as string,
      tmdbImageBase: await this.prefs.get('tmdbImageBase', defaults.tmdbImageBase) as string,
      autoSkipIntroSec: await this.prefs.get('autoSkipIntroSec', defaults.autoSkipIntroSec) as number,
      autoSkipOutroSec: await this.prefs.get('autoSkipOutroSec', defaults.autoSkipOutroSec) as number,
      subtitleFontSizeFp: await this.prefs.get('subtitleFontSizeFp', defaults.subtitleFontSizeFp) as number,
      subtitleLanguageMode: (await this.prefs.get('subtitleLanguageMode', defaults.subtitleLanguageMode) as string) as SubtitleLanguageMode,
      subtitleBgEnabled: await this.prefs.get('subtitleBgEnabled', defaults.subtitleBgEnabled) as boolean,
      subtitleBgOpacityPercent: await this.prefs.get('subtitleBgOpacityPercent', defaults.subtitleBgOpacityPercent) as number,
      subtitleVerticalOffsetVp: await this.prefs.get('subtitleVerticalOffsetVp', defaults.subtitleVerticalOffsetVp) as number,
      subdlApiKey: await this.prefs.get('subdlApiKey', defaults.subdlApiKey) as string,
      burnSubMaskDefault: await this.prefs.get('burnSubMaskDefault', defaults.burnSubMaskDefault) as boolean,
      proTier: (await this.prefs.get('proTier', defaults.proTier) as string) as ProTier,
      privacyAccepted: await this.prefs.get('privacyAccepted', defaults.privacyAccepted) as boolean,
      vaultPinCipher: await this.prefs.get('vaultPinCipher', '') as string
    };
  }

  async saveSettings(settings: AppSettings): Promise<void> {
    if (!this.prefs) return;
    await this.prefs.put('themeMode', settings.themeMode);
    await this.prefs.put('cacheBudgetMb', settings.cacheBudgetMb);
    await this.prefs.put('preferHardwareDecode', settings.preferHardwareDecode);
    const hwList = settings.hardwareSupportedFormats && settings.hardwareSupportedFormats.length > 0
      ? settings.hardwareSupportedFormats.join(',')
      : AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS.join(',');
    await this.prefs.put('hardwareSupportedFormats', hwList);
    await this.prefs.put('tmdbApiKey', settings.tmdbApiKey);
    await this.prefs.put('tmdbApiHost', settings.tmdbApiHost);
    await this.prefs.put('tmdbImageBase', settings.tmdbImageBase);
    await this.prefs.put('autoSkipIntroSec', settings.autoSkipIntroSec);
    await this.prefs.put('autoSkipOutroSec', settings.autoSkipOutroSec);
    await this.prefs.put('subtitleFontSizeFp', settings.subtitleFontSizeFp);
    await this.prefs.put('subtitleLanguageMode', settings.subtitleLanguageMode);
    await this.prefs.put('subtitleBgEnabled', settings.subtitleBgEnabled);
    await this.prefs.put('subtitleBgOpacityPercent', settings.subtitleBgOpacityPercent);
    await this.prefs.put('subtitleVerticalOffsetVp', settings.subtitleVerticalOffsetVp);
    await this.prefs.put('subdlApiKey', settings.subdlApiKey);
    await this.prefs.put('burnSubMaskDefault', settings.burnSubMaskDefault);
    await this.prefs.put('proTier', settings.proTier);
    await this.prefs.put('privacyAccepted', settings.privacyAccepted);
    await this.prefs.put('vaultPinCipher', settings.vaultPinCipher || '');
    await this.prefs.flush();
  }

  /** 播放时惰性补探测的字幕关联：只更新单个条目的字幕字段。 */
  async updateMediaItemSubtitles(itemId: string, subtitleUrl: string, tracks: SubtitleTrackOption[]): Promise<void> {
    if (!this.rdb) return;
    const predicates = new relationalStore.RdbPredicates('media_items');
    predicates.equalTo('id', itemId);
    const bucket: relationalStore.ValuesBucket = {
      'subtitle_url': subtitleUrl,
      'subtitle_tracks_json': JSON.stringify(tracks || [])
    };
    await this.rdb.update(bucket, predicates);
  }

  async getFlag(key: string): Promise<boolean> {
    if (!this.prefs) return false;
    return await this.prefs.get(key, false) as boolean;
  }

  async setFlag(key: string, value: boolean): Promise<void> {
    if (!this.prefs) return;
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }

  async getNumberPref(key: string, def: number): Promise<number> {
    if (!this.prefs) return def;
    const v: preferences.ValueType = await this.prefs.get(key, def);
    return typeof v === 'number' ? v : def;
  }

  async setNumberPref(key: string, value: number): Promise<void> {
    if (!this.prefs) return;
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }

  async getStringPref(key: string, def: string): Promise<string> {
    if (!this.prefs) return def;
    const v: preferences.ValueType = await this.prefs.get(key, def);
    return typeof v === 'string' ? v : def;
  }

  async setStringPref(key: string, value: string): Promise<void> {
    if (!this.prefs) return;
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }

  async listSources(): Promise<MediaSource[]> {
    if (!this.rdb) return [];
    const predicates = new relationalStore.RdbPredicates('media_sources');
    predicates.orderByDesc('created_at');
    const rs = await this.rdb.query(predicates);
    const out: MediaSource[] = [];
    try {
      while (rs.goToNextRow()) {
        const encPwd = rs.getString(rs.getColumnIndex('password_enc'));
        const plainPwd = await CryptoVault.decrypt(encPwd);
        const extraIdx = rs.getColumnIndex('extra_json');
        out.push({
          id: rs.getString(rs.getColumnIndex('id')),
          name: rs.getString(rs.getColumnIndex('name')),
          type: rs.getString(rs.getColumnIndex('type')) as MediaSourceType,
          baseUrl: rs.getString(rs.getColumnIndex('base_url')),
          rootPath: rs.getString(rs.getColumnIndex('root_path')),
          username: rs.getString(rs.getColumnIndex('username')),
          password: plainPwd,
          allowInsecureTls: rs.getLong(rs.getColumnIndex('allow_insecure_tls')) === 1,
          cacheAlist302: rs.getLong(rs.getColumnIndex('cache_alist_302')) === 1,
          createdAt: rs.getLong(rs.getColumnIndex('created_at')),
          lastScannedAt: rs.getLong(rs.getColumnIndex('last_scanned_at')),
          extraConfig: extraIdx >= 0 ? (rs.getString(extraIdx) || '{}') : '{}'
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async upsertSource(src: MediaSource): Promise<void> {
    if (!this.rdb) return;
    const encPwd = await CryptoVault.encrypt(src.password);
    const bucket: relationalStore.ValuesBucket = {
      id: src.id,
      name: src.name,
      type: src.type,
      base_url: src.baseUrl,
      root_path: src.rootPath,
      username: src.username,
      password_enc: encPwd,
      allow_insecure_tls: src.allowInsecureTls ? 1 : 0,
      cache_alist_302: src.cacheAlist302 ? 1 : 0,
      created_at: src.createdAt,
      last_scanned_at: src.lastScannedAt,
      extra_json: src.extraConfig || '{}'
    };
    await this.rdb.insert('media_sources', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async clearSourceMediaItems(sourceId: string): Promise<void> {
    if (!this.rdb) return;
    const itemPred = new relationalStore.RdbPredicates('media_items');
    itemPred.equalTo('source_id', sourceId);
    await this.rdb.delete(itemPred);
  }

  async deleteSource(sourceId: string): Promise<void> {
    if (!this.rdb) return;
    const srcPred = new relationalStore.RdbPredicates('media_sources');
    srcPred.equalTo('id', sourceId);
    await this.rdb.delete(srcPred);

    const itemPred = new relationalStore.RdbPredicates('media_items');
    itemPred.equalTo('source_id', sourceId);
    await this.rdb.delete(itemPred);

    const histPred = new relationalStore.RdbPredicates('watch_history');
    histPred.equalTo('source_id', sourceId);
    await this.rdb.delete(histPred);
  }

  async listMediaItems(): Promise<MediaItem[]> {
    if (!this.rdb) return [];
    const predicates = new relationalStore.RdbPredicates('media_items');
    predicates.orderByDesc('added_at');
    const rs = await this.rdb.query(predicates);
    const out: MediaItem[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          id: rs.getString(rs.getColumnIndex('id')),
          sourceId: rs.getString(rs.getColumnIndex('source_id')),
          sourceType: rs.getString(rs.getColumnIndex('source_type')) as MediaSourceType,
          remotePath: rs.getString(rs.getColumnIndex('remote_path')),
          streamUrl: rs.getString(rs.getColumnIndex('stream_url')),
          fileName: rs.getString(rs.getColumnIndex('file_name')),
          fileSize: rs.getLong(rs.getColumnIndex('file_size')),
          mediaType: rs.getString(rs.getColumnIndex('media_type')) === 'episode' ? 'episode' : 'movie',
          seriesKey: rs.getString(rs.getColumnIndex('series_key')),
          seriesTitle: rs.getString(rs.getColumnIndex('series_title')),
          seasonNo: rs.getLong(rs.getColumnIndex('season_no')),
          episodeNo: rs.getLong(rs.getColumnIndex('episode_no')),
          title: rs.getString(rs.getColumnIndex('title')),
          originalTitle: rs.getString(rs.getColumnIndex('original_title')),
          year: rs.getLong(rs.getColumnIndex('year')),
          overview: rs.getString(rs.getColumnIndex('overview')),
          posterUrl: rs.getString(rs.getColumnIndex('poster_url')),
          backdropUrl: rs.getString(rs.getColumnIndex('backdrop_url')),
          rating: rs.getDouble(rs.getColumnIndex('rating')),
          qualityTag: rs.getString(rs.getColumnIndex('quality_tag')),
          tmdbId: rs.getLong(rs.getColumnIndex('tmdb_id')),
          durationMs: rs.getLong(rs.getColumnIndex('duration_ms')),
          subtitleUrl: rs.getString(rs.getColumnIndex('subtitle_url')),
          subtitleTracks: this.parseSubTracks(rs.getString(rs.getColumnIndex('subtitle_tracks_json'))),
          isFavorite: rs.getLong(rs.getColumnIndex('is_favorite')) === 1,
          addedAt: rs.getLong(rs.getColumnIndex('added_at'))
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  private parseSubTracks(raw: string): SubtitleTrackOption[] {
    if (!raw || raw === '[]') return [];
    try {
      const parsed = JSON.parse(raw) as SubtitleTrackOption[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (_e) {
      return [];
    }
  }

  async upsertMediaItems(items: MediaItem[]): Promise<void> {
    if (!this.rdb || items.length === 0) return;
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      const bucket: relationalStore.ValuesBucket = {
        id: it.id,
        source_id: it.sourceId,
        source_type: it.sourceType,
        remote_path: it.remotePath,
        stream_url: it.streamUrl,
        file_name: it.fileName,
        file_size: it.fileSize,
        media_type: it.mediaType,
        series_key: it.seriesKey,
        series_title: it.seriesTitle,
        season_no: it.seasonNo,
        episode_no: it.episodeNo,
        title: it.title,
        original_title: it.originalTitle,
        year: it.year,
        overview: it.overview,
        poster_url: it.posterUrl,
        backdrop_url: it.backdropUrl,
        rating: it.rating,
        quality_tag: it.qualityTag,
        tmdb_id: it.tmdbId,
        duration_ms: it.durationMs,
        subtitle_url: it.subtitleUrl,
        subtitle_tracks_json: JSON.stringify(it.subtitleTracks || []),
        is_favorite: it.isFavorite ? 1 : 0,
        added_at: it.addedAt
      };
      await this.rdb.insert('media_items', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  async listWatchHistory(): Promise<WatchHistoryRecord[]> {
    if (!this.rdb) return [];
    const predicates = new relationalStore.RdbPredicates('watch_history');
    predicates.orderByDesc('updated_at');
    const rs = await this.rdb.query(predicates);
    const out: WatchHistoryRecord[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          itemId: rs.getString(rs.getColumnIndex('item_id')),
          title: rs.getString(rs.getColumnIndex('title')),
          subtitleLabel: rs.getString(rs.getColumnIndex('subtitle_label')),
          posterUrl: rs.getString(rs.getColumnIndex('poster_url')),
          streamUrl: rs.getString(rs.getColumnIndex('stream_url')),
          sourceId: rs.getString(rs.getColumnIndex('source_id')),
          positionMs: rs.getLong(rs.getColumnIndex('position_ms')),
          durationMs: rs.getLong(rs.getColumnIndex('duration_ms')),
          audioTrackIndex: rs.getLong(rs.getColumnIndex('audio_track_index')),
          subtitleTrackIndex: rs.getLong(rs.getColumnIndex('subtitle_track_index')),
          subtitleDelayMs: rs.getLong(rs.getColumnIndex('subtitle_delay_ms')),
          playbackRate: rs.getDouble(rs.getColumnIndex('playback_rate')),
          maskEnabled: rs.getLong(rs.getColumnIndex('mask_enabled')),
          maskYTop: rs.getDouble(rs.getColumnIndex('mask_ytop')),
          maskYBottom: rs.getDouble(rs.getColumnIndex('mask_ybottom')),
          updatedAt: rs.getLong(rs.getColumnIndex('updated_at')),
          finished: rs.getLong(rs.getColumnIndex('finished')) === 1
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async saveWatchHistory(record: WatchHistoryRecord): Promise<void> {
    if (!this.rdb) return;
    const bucket: relationalStore.ValuesBucket = {
      item_id: record.itemId,
      title: record.title,
      subtitle_label: record.subtitleLabel,
      poster_url: record.posterUrl,
      stream_url: record.streamUrl,
      source_id: record.sourceId,
      position_ms: record.positionMs,
      duration_ms: record.durationMs,
      audio_track_index: record.audioTrackIndex,
      subtitle_track_index: record.subtitleTrackIndex,
      subtitle_delay_ms: record.subtitleDelayMs,
      playback_rate: record.playbackRate,
      mask_enabled: record.maskEnabled,
      mask_ytop: record.maskYTop,
      mask_ybottom: record.maskYBottom,
      updated_at: record.updatedAt,
      finished: record.finished ? 1 : 0
    };
    await this.rdb.insert('watch_history', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async deleteWatchHistoryItem(itemId: string): Promise<void> {
    if (!this.rdb) return;
    const pred = new relationalStore.RdbPredicates('watch_history');
    pred.equalTo('item_id', itemId);
    await this.rdb.delete(pred);
  }

  /** 批量删除媒体条目（清空离线影库时用）；分批避免 SQL 变量数上限 */
  async deleteMediaItems(ids: string[]): Promise<void> {
    if (!this.rdb || ids.length === 0) return;
    for (let i = 0; i < ids.length; i += 500) {
      const pred = new relationalStore.RdbPredicates('media_items');
      pred.in('id', ids.slice(i, i + 500));
      await this.rdb.delete(pred);
    }
  }

  async deleteWatchHistoryItems(ids: string[]): Promise<void> {
    if (!this.rdb || ids.length === 0) return;
    for (let i = 0; i < ids.length; i += 500) {
      const pred = new relationalStore.RdbPredicates('watch_history');
      pred.in('item_id', ids.slice(i, i + 500));
      await this.rdb.delete(pred);
    }
  }

  async clearWatchHistory(): Promise<void> {
    if (!this.rdb) return;
    const pred = new relationalStore.RdbPredicates('watch_history');
    await this.rdb.delete(pred);
  }

  async listHiddenFolders(): Promise<HiddenFolderRule[]> {
    if (!this.rdb) return [];
    const pred = new relationalStore.RdbPredicates('hidden_folders');
    pred.orderByDesc('created_at');
    const rs = await this.rdb.query(pred);
    const out: HiddenFolderRule[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          id: rs.getString(rs.getColumnIndex('id')),
          sourceId: rs.getString(rs.getColumnIndex('source_id')),
          folderPath: rs.getString(rs.getColumnIndex('folder_path')),
          folderName: rs.getString(rs.getColumnIndex('folder_name')),
          createdAt: rs.getLong(rs.getColumnIndex('created_at'))
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async upsertHiddenFolder(rule: HiddenFolderRule): Promise<void> {
    if (!this.rdb) return;
    const bucket: relationalStore.ValuesBucket = {
      id: rule.id,
      source_id: rule.sourceId,
      folder_path: rule.folderPath,
      folder_name: rule.folderName,
      created_at: rule.createdAt
    };
    await this.rdb.insert('hidden_folders', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async deleteHiddenFolder(ruleId: string): Promise<void> {
    if (!this.rdb) return;
    const pred = new relationalStore.RdbPredicates('hidden_folders');
    pred.equalTo('id', ruleId);
    await this.rdb.delete(pred);
  }

  async listVaultEntries(): Promise<VaultEntry[]> {
    if (!this.rdb) return [];
    const out: VaultEntry[] = [];
    const predicates = new relationalStore.RdbPredicates('vault_entries');
    predicates.orderByDesc('created_at');
    const rs = await this.rdb.query(predicates);
    try {
      while (rs.goToNextRow()) {
        const row: VaultEntry = {
          id: rs.getString(rs.getColumnIndex('id')),
          sourceId: rs.getString(rs.getColumnIndex('source_id')),
          kind: rs.getString(rs.getColumnIndex('kind')) as VaultEntryKind,
          targetKey: rs.getString(rs.getColumnIndex('target_key')),
          title: rs.getString(rs.getColumnIndex('title')),
          posterUrl: rs.getString(rs.getColumnIndex('poster_url')),
          createdAt: rs.getLong(rs.getColumnIndex('created_at'))
        };
        out.push(row);
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async upsertVaultEntry(entry: VaultEntry): Promise<void> {
    if (!this.rdb) return;
    const bucket: relationalStore.ValuesBucket = {
      'id': entry.id,
      'source_id': entry.sourceId,
      'kind': entry.kind,
      'target_key': entry.targetKey,
      'title': entry.title,
      'poster_url': entry.posterUrl,
      'created_at': entry.createdAt
    };
    await this.rdb.insert('vault_entries', bucket);
  }

  async deleteVaultEntry(entryId: string): Promise<void> {
    if (!this.rdb) return;
    const predicates = new relationalStore.RdbPredicates('vault_entries');
    predicates.equalTo('id', entryId);
    await this.rdb.delete(predicates);
  }
}
