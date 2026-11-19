export interface NativeTrackInfo {
  index: number;
  trackType: number; // 0: audio, 1: video, 2: subtitle
  mimeType: string;
  language: string;
  title: string;
  sampleRate: number;
  channels: number;
  width: number;
  height: number;
}

export interface NativePlayerEvent {
  type: 'state' | 'position' | 'duration' | 'resolution' | 'buffering' | 'eos' | 'seekDone' | 'rateDone' | 'tracksReady' | 'error';
  state?: number;
  positionMs?: number;
  durationMs?: number;
  width?: number;
  height?: number;
  bufferingType?: number;
  bufferingValue?: number;
  rate?: number;
  errorCode?: number;
  errorMsg?: string;
}

export interface ProxyStreamConfig {
  url: string;
  authHeader?: string;
  userAgent?: string;
  allowInsecureTls?: boolean;
  cacheAlist302?: boolean;
  smbHost?: string;
  smbPort?: number;
  smbShare?: string;
  smbPath?: string;
  smbUser?: string;
  smbPass?: string;
}

export interface SmbNativeConfig {
  host: string;
  port?: number;
  share: string;
  domain?: string;
  username?: string;
  password?: string;
}

export interface SmbNativeEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  lastModifiedMs: number;
}

export interface SmbNativeTestResult {
  ok: boolean;
  latencyMs: number;
  entryCount: number;
  message: string;
}

export interface SmbNativeListResult {
  ok: boolean;
  error: string;
  entries: SmbNativeEntry[];
}

export interface ProxyStreamStats {
  bytesServed: number;
  cacheHits: number;
  cacheMisses: number;
  cachedBytes: number;
  totalSize: number;
  resolvedUrl: string;
}

export interface LocalMediaMeta {
  durationMs: number;
  width: number;
  height: number;
  title: string;
  mimeType: string;
}

export const startStreamProxy: (cacheBudgetMb: number) => number;
export const stopStreamProxy: () => void;
export const registerProxyStream: (streamId: string, config: ProxyStreamConfig) => string;
export const unregisterProxyStream: (streamId: string) => void;
export const getProxyStats: (streamId: string) => ProxyStreamStats;

export const setHttpsFetchHandler: (
  handler: (reqId: number, url: string, authHeader: string, rangeStart: number, rangeEnd: number, allowInsecure: boolean) => void
) => void;
export const resolveHttpsChunk: (
  reqId: number,
  statusCode: number,
  totalSize: number,
  contentType: string,
  redirectUrl: string,
  data: ArrayBuffer
) => void;

export const createPlayer: () => number;
export const destroyPlayer: (playerId: number) => void;
export const bindSurface: (playerId: number, surfaceId: string) => boolean;
export const setUrlSource: (playerId: number, url: string) => number;
export const setFdSource: (playerId: number, fd: number, offset: number, size: number) => number;
export const preparePlayer: (playerId: number) => number;
export const playPlayer: (playerId: number) => number;
export const pausePlayer: (playerId: number) => number;
export const stopPlayer: (playerId: number) => number;
export const resetPlayer: (playerId: number) => number;
export const seekPlayer: (playerId: number, positionMs: number, mode: number) => number;
export const setPlayerRate: (playerId: number, rate: number) => number;
export const setPlayerVolume: (playerId: number, volume: number) => number;
export const selectPlayerTrack: (playerId: number, trackIndex: number) => number;
export const deselectPlayerTrack: (playerId: number, trackIndex: number) => number;
export const getPlayerTracks: (playerId: number) => NativeTrackInfo[];
export const setPlayerEventCallback: (playerId: number, callback: (event: NativePlayerEvent) => void) => void;

export const probeLocalMedia: (fd: number, offset: number, size: number) => LocalMediaMeta;

export const smbTestConnection: (config: SmbNativeConfig, initialPath?: string) => Promise<SmbNativeTestResult>;
export const smbListDirectory: (config: SmbNativeConfig, dirPath: string) => Promise<SmbNativeListResult>;
export const smbReadTextFile: (config: SmbNativeConfig, filePath: string, maxBytes?: number) => Promise<string>;
