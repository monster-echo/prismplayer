import {
  LocalMediaMeta,
  NativePlayerEvent,
  NativeTrackInfo,
  ProxyStreamConfig,
  ProxyStreamStats,
  SmbNativeConfig,
  SmbNativeListResult,
  SmbNativeTestResult
} from '../main/cpp/types/libprismplayer/Index';

export function startStreamProxy(_cacheBudgetMb: number): number {
  return 0;
}

export function stopStreamProxy(): void {}

export function registerProxyStream(_streamId: string, config: ProxyStreamConfig): string {
  return config.url;
}

export function unregisterProxyStream(_streamId: string): void {}

export function getProxyStats(_streamId: string): ProxyStreamStats {
  return {
    bytesServed: 0,
    cacheHits: 0,
    cacheMisses: 0,
    cachedBytes: 0,
    totalSize: 0,
    resolvedUrl: ''
  };
}

export function setHttpsFetchHandler(
  _handler: (reqId: number, url: string, authHeader: string, rangeStart: number, rangeEnd: number, allowInsecure: boolean) => void
): void {}

export function resolveHttpsChunk(
  _reqId: number,
  _statusCode: number,
  _totalSize: number,
  _contentType: string,
  _redirectUrl: string,
  _data: ArrayBuffer
): void {}

export function createPlayer(): number {
  return 1;
}

export function destroyPlayer(_playerId: number): void {}

export function bindSurface(_playerId: number, _surfaceId: string): boolean {
  return true;
}

export function setUrlSource(_playerId: number, _url: string): number {
  return 0;
}

export function setFdSource(_playerId: number, _fd: number, _offset: number, _size: number): number {
  return 0;
}

export function preparePlayer(_playerId: number): number {
  return 0;
}

export function playPlayer(_playerId: number): number {
  return 0;
}

export function pausePlayer(_playerId: number): number {
  return 0;
}

export function stopPlayer(_playerId: number): number {
  return 0;
}

export function resetPlayer(_playerId: number): number {
  return 0;
}

export function seekPlayer(_playerId: number, _positionMs: number, _mode: number): number {
  return 0;
}

export function setPlayerRate(_playerId: number, _rate: number): number {
  return 0;
}

export function setPlayerVolume(_playerId: number, _volume: number): number {
  return 0;
}

export function selectPlayerTrack(_playerId: number, _trackIndex: number): number {
  return 0;
}

export function deselectPlayerTrack(_playerId: number, _trackIndex: number): number {
  return 0;
}

export function getPlayerTracks(_playerId: number): NativeTrackInfo[] {
  return [];
}

export function setPlayerEventCallback(_playerId: number, _callback: (event: NativePlayerEvent) => void): void {}

export function probeLocalMedia(_fd: number, _offset: number, _size: number): LocalMediaMeta {
  return {
    durationMs: 0,
    width: 0,
    height: 0,
    title: '',
    mimeType: ''
  };
}

export async function smbTestConnection(_config: SmbNativeConfig, _initialPath?: string): Promise<SmbNativeTestResult> {
  return {
    ok: false,
    latencyMs: 0,
    entryCount: 0,
    message: 'mock'
  };
}

export async function smbListDirectory(_config: SmbNativeConfig, _dirPath: string): Promise<SmbNativeListResult> {
  return {
    ok: false,
    error: 'mock',
    entries: []
  };
}

export async function smbReadTextFile(_config: SmbNativeConfig, _filePath: string, _maxBytes?: number): Promise<string> {
  return '';
}

class MockPrismPlayerModule {
  startStreamProxy = startStreamProxy;
  stopStreamProxy = stopStreamProxy;
  registerProxyStream = registerProxyStream;
  unregisterProxyStream = unregisterProxyStream;
  getProxyStats = getProxyStats;
  setHttpsFetchHandler = setHttpsFetchHandler;
  resolveHttpsChunk = resolveHttpsChunk;
  createPlayer = createPlayer;
  destroyPlayer = destroyPlayer;
  bindSurface = bindSurface;
  setUrlSource = setUrlSource;
  setFdSource = setFdSource;
  preparePlayer = preparePlayer;
  playPlayer = playPlayer;
  pausePlayer = pausePlayer;
  stopPlayer = stopPlayer;
  resetPlayer = resetPlayer;
  seekPlayer = seekPlayer;
  setPlayerRate = setPlayerRate;
  setPlayerVolume = setPlayerVolume;
  selectPlayerTrack = selectPlayerTrack;
  deselectPlayerTrack = deselectPlayerTrack;
  getPlayerTracks = getPlayerTracks;
  setPlayerEventCallback = setPlayerEventCallback;
  probeLocalMedia = probeLocalMedia;
  smbTestConnection = smbTestConnection;
  smbListDirectory = smbListDirectory;
  smbReadTextFile = smbReadTextFile;
}

const mockPrismPlayer = new MockPrismPlayerModule();
export default mockPrismPlayer;
