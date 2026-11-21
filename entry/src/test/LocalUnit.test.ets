import { describe, it, expect } from '@ohos/hypium';
import { AppConstants } from '../main/ets/common/Constants';
import { Formatters } from '../main/ets/common/Formatters';
import { MediaItem, MediaSource, MediaSourceType } from '../main/ets/common/Types';
import { DouyinClient } from '../main/ets/services/DouyinClient';
import { EmbyClient, EmbySessionContext } from '../main/ets/services/EmbyClient';
import { IptvClient } from '../main/ets/services/IptvClient';
import { NfoParser } from '../main/ets/services/NfoParser';
import { PlexClient } from '../main/ets/services/PlexClient';
import { RemoteSourceClient } from '../main/ets/services/RemoteSourceClient';
import { S3Client } from '../main/ets/services/S3Client';
import { SmbClient } from '../main/ets/services/SmbClient';
import { SubtitleEngine } from '../main/ets/services/SubtitleEngine';
import { WebDavClient } from '../main/ets/services/WebDavClient';
import { YouTubeClient } from '../main/ets/services/YouTubeClient';

export default function localUnitTest() {
  describe('PrismPlayerCoreUnitTests', () => {
    it('parses_movie_and_tv_filenames', 0, () => {
      const movie = Formatters.parseMediaFilename('Dune.Part.Two.2024.2160p.WEB-DL.H265.HDR.mkv');
      expect(movie.mediaType).assertEqual('movie');
      expect(movie.cleanTitle).assertEqual('Dune Part Two');
      expect(movie.year).assertEqual(2024);
      expect(movie.qualityTag.includes('4K')).assertTrue();
      expect(movie.qualityTag.includes('HEVC')).assertTrue();

      const tv = Formatters.parseMediaFilename('Severance.S02E05.1080p.BluRay.x265.mkv');
      expect(tv.mediaType).assertEqual('episode');
      expect(tv.cleanTitle).assertEqual('Severance');
      expect(tv.seasonNo).assertEqual(2);
      expect(tv.episodeNo).assertEqual(5);

      const cnTv = Formatters.parseMediaFilename('三体 第12集 4K.mp4');
      expect(cnTv.mediaType).assertEqual('episode');
      expect(cnTv.episodeNo).assertEqual(12);
    });

    it('encodes_basic_auth_header', 0, () => {
      const hdr = Formatters.buildBasicAuthHeader('admin', 'pass123');
      expect(hdr).assertEqual('Basic YWRtaW46cGFzczEyMw==');
    });

    it('routes_only_remote_streams_through_range_proxy', 0, () => {
      const makeSource = (type: MediaSourceType): MediaSource => {
        return {
          id: 's1',
          name: 'test',
          type: type,
          baseUrl: 'smb://nas/share',
          rootPath: '/',
          username: 'u',
          password: '',
          allowInsecureTls: false,
          cacheAlist302: false,
          createdAt: 0,
          lastScannedAt: 0
        };
      };

      expect(RemoteSourceClient.needsRangeProxy('smb://nas/Movies/a.mkv')).assertTrue();
      expect(RemoteSourceClient.needsRangeProxy('smb://nas/Movies/a.mkv', makeSource('smb'))).assertTrue();
      expect(RemoteSourceClient.needsRangeProxy('https://dav.local/a.mkv', makeSource('webdav'))).assertTrue();
      expect(RemoteSourceClient.needsRangeProxy('https://plex.local/a.mkv', makeSource('plex'))).assertFalse();
      // 已离线保存：沙箱路径即使仍关联 SMB/WebDAV 片源也不能套代理
      expect(RemoteSourceClient.needsRangeProxy(
        '/data/storage/el2/base/haps/entry/files/saved_videos/a.mkv', makeSource('smb'))).assertFalse();
      expect(RemoteSourceClient.needsRangeProxy(
        'file:///data/storage/el2/base/haps/entry/files/saved_videos/a.mkv', makeSource('webdav'))).assertFalse();
    });

    it('parses_webdav_propfind_xml', 0, () => {
      const xml = `<?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/Movies/</D:href>
            <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/Movies/SciFi/</D:href>
            <D:propstat><D:prop><D:displayname>SciFi</D:displayname><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/Movies/Interstellar.2014.2160p.mkv</D:href>
            <D:propstat><D:prop><D:getcontentlength>4294967296</D:getcontentlength></D:prop></D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/Movies/Interstellar.2014.2160p.ass</D:href>
            <D:propstat><D:prop><D:getcontentlength>81920</D:getcontentlength></D:prop></D:propstat>
          </D:response>
        </D:multistatus>`;

      const entries = WebDavClient.parsePropfindXml(xml, 'https://nas.local:5244/dav', '/Movies');
      expect(entries.length).assertEqual(3);
      expect(entries[0].isDirectory).assertTrue();
      expect(entries[0].name).assertEqual('SciFi');
      expect(entries[1].isSubtitle).assertTrue();
      expect(entries[2].isVideo).assertTrue();
      expect(entries[2].size).assertEqual(4294967296);
    });

    it('parses_kodi_nfo_metadata', 0, () => {
      const nfo = `<movie>
        <title><![CDATA[星际穿越]]></title>
        <originaltitle>Interstellar</originaltitle>
        <year>2014</year>
        <rating>9.3</rating>
        <tmdbid>157336</tmdbid>
        <plot>A team of explorers travel through a wormhole in space.</plot>
      </movie>`;
      const meta = NfoParser.parse(nfo);
      expect(meta !== null).assertTrue();
      expect(meta!.title).assertEqual('星际穿越');
      expect(meta!.year).assertEqual(2014);
      expect(meta!.tmdbId).assertEqual(157336);
    });

    it('parses_ass_subtitles_and_binary_search_with_delay', 0, () => {
      const ass = `[Script Info]
Title: Test
[V4+ Styles]
Format: Name, PrimaryColour, Bold, Italic, Alignment
Style: Default,&H00FFAA00,0,0,2
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:02.00,0:00:05.00,Default,,0,0,0,,{\\an8\\b1}Hello\\NWorld`;

      const track = SubtitleEngine.parse(ass, 'test.ass', 'test.ass');
      expect(track.format).assertEqual('ass');
      expect(track.cues.length).assertEqual(1);
      expect(track.cues[0].alignment).assertEqual(8);
      expect(track.cues[0].isBold).assertTrue();
      expect(track.cues[0].colorHex).assertEqual('#00AAFF');
      expect(track.cues[0].text).assertEqual('Hello\nWorld');

      const activeAt3s = SubtitleEngine.findActiveCues(track.cues, 3000, 0);
      expect(activeAt3s.length).assertEqual(1);

      const shiftedOut = SubtitleEngine.findActiveCues(track.cues, 3000, 1500);
      expect(shiftedOut.length).assertEqual(0);
    });

    it('parses_bom_bilingual_ass_and_encodes_nas_webdav_urls', 0, () => {
      const bomAss = `\uFEFF[Script Info]
ScriptType: v4.00+
[V4+ Styles]
Format: Name, PrimaryColour, Bold, Italic, Alignment
Style: Default,&H00E0E0E0,0,0,2
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:02:20.53,0:02:22.66,Default,,0000,0000,0000,,{\\fn华文楷体\\fs20\\1c&HE0E0E0&}关于这个世界{\\r}\\N{\\fnCronos Pro Subhead\\fs14\\1c&H3CF1F3&}A lot of stuff{\\r}`;

      const track = SubtitleEngine.parse(bomAss, 'Manchester.zh.ass', 'Manchester.zh.ass');
      expect(track.format).assertEqual('ass');
      expect(track.cues.length).assertEqual(1);
      expect(track.cues[0].text).assertEqual('关于这个世界\nA lot of stuff');

      const encoded = WebDavClient.joinRemoteFileUrl(
        'http://100.100.131.63:15244/dav',
        '/dav/movie/Interstellar (2014)/sample-Interstellar.mkv'
      );
      expect(encoded.includes('Interstellar%20(2014)')).assertTrue();
    });

    it('maps_raw_errors_to_friendly_copy', 0, () => {
      const netMsg = Formatters.toFriendlyError('what=-10000, extra=0', true);
      expect(netMsg.includes('-10000')).assertFalse();
      expect(netMsg.includes('片源服务器')).assertTrue();

      const authMsg = Formatters.toFriendlyError('WebDAV HTTP 401');
      expect(authMsg.includes('401')).assertFalse();
      expect(authMsg.includes('鉴权') || authMsg.includes('账号')).assertTrue();
    });

    it('parses_smb_and_plex_source_configs', 0, () => {
      const parsedSmb = SmbClient.parseSource({
        id: 'smb1',
        name: 'nas-ruan',
        type: 'smb',
        baseUrl: 'smb://100.100.131.63/homes',
        rootPath: '/rw/download/movie',
        username: 'admin',
        password: 'pw',
        allowInsecureTls: false,
        cacheAlist302: false,
        createdAt: 0,
        lastScannedAt: 0
      });
      expect(parsedSmb.host).assertEqual('100.100.131.63');
      expect(parsedSmb.port).assertEqual(445);
      expect(parsedSmb.share).assertEqual('homes');
      expect(parsedSmb.relPath).assertEqual('/rw/download/movie');

      const parsedPlainIp = SmbClient.parseSource({
        id: 'smb2',
        name: 'nas-ruan',
        type: 'smb',
        baseUrl: '100.100.131.63:445',
        rootPath: '/homes/rw/download/movie',
        username: 'admin',
        password: 'pw',
        allowInsecureTls: false,
        cacheAlist302: false,
        createdAt: 0,
        lastScannedAt: 0
      });
      expect(parsedPlainIp.share).assertEqual('homes');
      expect(parsedPlainIp.relPath).assertEqual('/rw/download/movie');

      expect(PlexClient.normalizeBaseUrl('100.100.131.63')).assertEqual('http://100.100.131.63:32400');
      const tokenUrl = PlexClient.appendToken('http://100.100.131.63:32400', '/library/parts/1/file.mkv', 'tok123');
      expect(tokenUrl).assertEqual('http://100.100.131.63:32400/library/parts/1/file.mkv?X-Plex-Token=tok123');
    });

    it('s3_sigv4_signing_presign_and_list_xml', 0, () => {
      expect(S3Client.sha256Hex('abc')).assertEqual(
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
      );
      expect(S3Client.inferRegionFromHost('my.r2.cloudflarestorage.com')).assertEqual('auto');
      expect(S3Client.inferRegionFromHost('s3.ap-southeast-1.amazonaws.com')).assertEqual('ap-southeast-1');

      const s3Src: MediaSource = {
        id: 's3_1',
        name: 'Cloud S3',
        type: 's3',
        baseUrl: 'https://s3.us-east-1.amazonaws.com/cinema-bucket',
        rootPath: '/',
        username: 'AKIAIOSFODNN7EXAMPLE',
        password: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        allowInsecureTls: false,
        cacheAlist302: false,
        createdAt: 0,
        lastScannedAt: 0,
        extraConfig: '{"region":"us-east-1","usePathStyle":true}'
      };
      const signed = S3Client.buildPresignedGetUrl(
        s3Src,
        'movies/Dune (2021).mkv',
        3600,
        new Date(Date.UTC(2026, 10, 19, 0, 0, 0))
      );
      expect(signed.includes('X-Amz-Algorithm=AWS4-HMAC-SHA256')).assertTrue();
      expect(signed.includes('X-Amz-SignedHeaders=host')).assertTrue();
      expect(signed.includes('X-Amz-Signature=')).assertTrue();
      expect(signed.includes('/cinema-bucket/movies/Dune%20%282021%29.mkv')).assertTrue();

      const listXml = `<?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
          <CommonPrefixes><Prefix>movies/SciFi/</Prefix></CommonPrefixes>
          <Contents><Key>movies/Dune.2021.1080p.mkv</Key><Size>4294967296</Size><LastModified>2026-11-18T12:00:00.000Z</LastModified></Contents>
          <Contents><Key>movies/Dune.2021.1080p.srt</Key><Size>65536</Size><LastModified>2026-11-18T12:00:00.000Z</LastModified></Contents>
        </ListBucketResult>`;
      const entries = S3Client.parseListObjectsXml(listXml, 'movies/');
      expect(entries.length).assertEqual(3);
      expect(entries[0].isDirectory).assertTrue();
      expect(entries[0].name).assertEqual('SciFi');
      expect(entries[1].isVideo).assertTrue();
      expect(entries[1].fullUrl).assertEqual('s3:///movies/Dune.2021.1080p.mkv');
      expect(entries[2].isSubtitle).assertTrue();
    });

    it('youtube_target_and_rss_parsing', 0, () => {
      expect(YouTubeClient.extractVideoId('https://youtu.be/aqz-KE-bpKQ?t=10')).assertEqual('aqz-KE-bpKQ');
      expect(YouTubeClient.extractVideoId('youtube://watch?v=dQw4w9WgXcQ')).assertEqual('dQw4w9WgXcQ');
      expect(YouTubeClient.parseTarget('https://www.youtube.com/@TED').kind).assertEqual('handle');
      expect(YouTubeClient.parseTarget('https://www.youtube.com/playlist?list=PL12345').kind).assertEqual('playlist');

      const rssXml = `<feed>
        <author><name>Blender Foundation</name></author>
        <entry>
          <yt:videoId>aqz-KE-bpKQ</yt:videoId>
          <title>Big Buck Bunny 60fps 4K</title>
          <published>2024-05-01T10:00:00+00:00</published>
          <media:thumbnail url="https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg"/>
          <media:description>Open movie showcase</media:description>
        </entry>
      </feed>`;
      const vids = YouTubeClient.parseRssXml(rssXml);
      expect(vids.length).assertEqual(1);
      expect(vids[0].videoId).assertEqual('aqz-KE-bpKQ');
      expect(vids[0].title).assertEqual('Big Buck Bunny 60fps 4K');
      expect(vids[0].author).assertEqual('Blender Foundation');
    });

    it('iptv_m3u_html_and_emby_helpers', 0, () => {
      const m3u = `#EXTM3U
#EXTINF:-1 tvg-logo="https://img.example/cctv.png" group-title="央视新闻",CCTV-13 新闻
https://live.example.com/cctv13/index.m3u8
#EXTINF:-1 group-title="电影频道",4K 测试频道
https://cdn.example.com/cinema.mp4`;
      const channels = IptvClient.parseM3uPlaylist(m3u);
      expect(channels.length).assertEqual(2);
      expect(channels[0].group).assertEqual('央视新闻');
      expect(channels[0].name).assertEqual('CCTV-13 新闻');
      expect(channels[1].url).assertEqual('https://cdn.example.com/cinema.mp4');

      const htmlIdx = `<html><body><a href="../">../</a><a href="Series/">Series/</a><a href="Movie.2024.mp4">Movie.2024.mp4</a><a href="Movie.2024.ass">Movie.2024.ass</a></body></html>`;
      const entries = IptvClient.parseHtmlDirectoryIndex(htmlIdx, 'http://192.168.1.10:8080/media/');
      expect(entries.length).assertEqual(3);
      expect(entries[0].isDirectory).assertTrue();
      expect(entries[1].isVideo).assertTrue();
      expect(entries[2].isSubtitle).assertTrue();

      expect(EmbyClient.normalizeBaseUrl('192.168.1.10:8096/')).assertEqual('http://192.168.1.10:8096');
      const embyCtx: EmbySessionContext = { baseUrl: 'http://nas:8096', token: 'tok99', userId: 'u1' };
      expect(EmbyClient.buildStreamUrl(embyCtx, '42'))
        .assertEqual('http://nas:8096/Videos/42/stream?Static=true&api_key=tok99');
    });

    it('douyin_share_text_router_data_and_watermark_free_url', 0, () => {
      const shareCopy =
        '7.46 复制打开抖音，看看【风光摄影师的作品】航拍川西雪山日照金山 4K 原片 https://v.douyin.com/iY8xYz12/ 08/19 e@o.Pk';
      const parsed = DouyinClient.parseShareText(shareCopy);
      expect(parsed.author).assertEqual('风光摄影师');
      expect(parsed.title).assertEqual('航拍川西雪山日照金山 4K 原片');
      expect(parsed.shareUrl).assertEqual('https://v.douyin.com/iY8xYz12/');

      const userShare =
        '7.97 :6pm rRX:/ Z@Z.mQ 01/22 详细解读电影淮海战役 邱清泉这手徐东大捷玩的很六  https://v.douyin.com/C2Mfnq9YWLs/ 复制此链接，打开Dou音搜索，直接观看视频！';
      const parsedUser = DouyinClient.parseShareText(userShare);
      expect(parsedUser.title).assertEqual('详细解读电影淮海战役 邱清泉这手徐东大捷玩的很六');
      expect(parsedUser.shareUrl).assertEqual('https://v.douyin.com/C2Mfnq9YWLs/');

      expect(DouyinClient.extractAwemeId('https://www.iesdouyin.com/share/video/7391234567890123456/?region=CN'))
        .assertEqual('7391234567890123456');

      const nwm = DouyinClient.toWatermarkFreeUrl(
        'http://aweme.snssdk.com/aweme/v1/playwm/?video_id=v0200fg10000abc'
      );
      expect(nwm).assertEqual('https://aweme.snssdk.com/aweme/v1/play/?video_id=v0200fg10000abc&ratio=1080p&line=0');

      const mockHtml = `<script>window._ROUTER_DATA = {"loaderData":{"video_(id)/page":{"itemId":"7391234567890123456","videoInfoRes":{"item_list":[{"aweme_id":"7391234567890123456","desc":"川西雪山","author":{"nickname":"风光摄影师"},"video":{"duration":18500,"cover":{"url_list":["https://p3.douyinpic.com/cover.jpg"]},"play_addr":{"url_list":["https://aweme.snssdk.com/aweme/v1/playwm/?video_id=v0200fg1"]}}}]}}}}</script>`;
      const info = DouyinClient.parseRouterDataHtml(mockHtml, parsed);
      expect(info !== null).assertTrue();
      expect(info!.awemeId).assertEqual('7391234567890123456');
      expect(info!.playUrl.includes('/play/?video_id=v0200fg1')).assertTrue();
      expect(info!.durationMs).assertEqual(18500);
    });

    it('hardware_supported_formats_pre_routes_hw_and_ffmpeg_engines', 0, () => {
      const mp4Item: MediaItem = {
        id: '1', sourceId: 's1', sourceType: 'webdav', remotePath: '/Movie.2024.1080p.H264.AAC.mp4',
        streamUrl: 'https://cdn.example.com/Movie.2024.1080p.H264.AAC.mp4', fileName: 'Movie.2024.1080p.H264.AAC.mp4',
        fileSize: 100, mediaType: 'movie', seriesKey: '1', seriesTitle: 'Movie', seasonNo: 1, episodeNo: 0,
        title: 'Movie', originalTitle: '', year: 2024, overview: '', posterUrl: '', backdropUrl: '', rating: 8,
        qualityTag: '1080P', tmdbId: 0, durationMs: 0, subtitleUrl: '', addedAt: 0
      };
      const mkvDtsItem: MediaItem = {
        id: '2', sourceId: 's1', sourceType: 'smb', remotePath: '/Fireflies.in.the.Sun.2021.2160p.WEB-DL.H265.DDP5.1.Atmos.mkv',
        streamUrl: 'smb://100.100.131.63/homes/rw/download/movie/Fireflies.mkv',
        fileName: 'Fireflies.in.the.Sun.2021.2160p.WEB-DL.H265.DDP5.1.Atmos.mkv',
        fileSize: 100, mediaType: 'movie', seriesKey: '2', seriesTitle: 'Fireflies', seasonNo: 1, episodeNo: 0,
        title: '误杀 2', originalTitle: '', year: 2021, overview: '', posterUrl: '', backdropUrl: '', rating: 8,
        qualityTag: '4K · HEVC', tmdbId: 0, durationMs: 0, subtitleUrl: '', addedAt: 0
      };
      const aviXvidItem: MediaItem = {
        id: '3', sourceId: 's1', sourceType: 'plex', remotePath: '/Earth.Girls.Are.Easy.DVDrip.Xvid.AC3.avi',
        streamUrl: 'http://100.100.131.63:32400/library/parts/99/file.avi',
        fileName: 'Earth.Girls.Are.Easy.DVDrip.Xvid.AC3.avi',
        fileSize: 100, mediaType: 'movie', seriesKey: '3', seriesTitle: 'Earth', seasonNo: 1, episodeNo: 0,
        title: 'Earth Girls', originalTitle: '', year: 1988, overview: '', posterUrl: '', backdropUrl: '', rating: 7,
        qualityTag: 'HD', tmdbId: 0, durationMs: 0, subtitleUrl: '', addedAt: 0
      };

      const defaultList = AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS;
      const r1 = Formatters.selectDecodeEngine(mp4Item, true, defaultList);
      expect(r1.engine).assertEqual('native_hw');

      const r2 = Formatters.selectDecodeEngine(mkvDtsItem, true, defaultList);
      expect(r2.engine).assertEqual('ffmpeg_sw');

      const r3 = Formatters.selectDecodeEngine(aviXvidItem, true, defaultList);
      expect(r3.engine).assertEqual('ffmpeg_sw');

      // If user explicitly adds 'mkv' and 'dts' to hardwareSupportedFormats, it routes to native_hw
      const customHw = ['mp4', 'mkv', 'dts'];
      const r4 = Formatters.selectDecodeEngine(mkvDtsItem, true, customHw);
      expect(r4.engine).assertEqual('native_hw');
    });

    it('detects_multilingual_subtitle_filenames_dynamically', 0, () => {
      expect(Formatters.detectSubtitleLanguage('Amelie.2001.fr.srt', 0).label).assertEqual('法文');
      expect(Formatters.detectSubtitleLanguage('Amelie.2001.fre.ass', 1).label).assertEqual('法文');
      expect(Formatters.detectSubtitleLanguage('Spirited.Away.ja.vtt', 2).label).assertEqual('日文');
      expect(Formatters.detectSubtitleLanguage('Movie.zh-CN.chs.ass', 3).label).assertEqual('中文');
      expect(Formatters.detectSubtitleLanguage('Movie.eng.srt', 4).label).assertEqual('英文');
    });
  });
}
