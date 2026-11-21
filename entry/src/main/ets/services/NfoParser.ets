export interface NfoMetadata {
  title: string;
  originalTitle: string;
  year: number;
  overview: string;
  rating: number;
  tmdbId: number;
  seasonNo: number;
  episodeNo: number;
  posterUrl: string;
  /** `<thumb>` 原值：可能是相对文件名，交由调用方按本地图片解析 */
  thumbRaw: string;
}

export class NfoParser {
  private static extractTag(xml: string, tag: string): string {
    const regex = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tag}>`, 'i');
    const m = xml.match(regex);
    if (!m || !m[1]) return '';
    return m[1]
      .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .trim();
  }

  static parse(xml: string): NfoMetadata | null {
    if (!xml || (!xml.includes('<movie') && !xml.includes('<tvshow') && !xml.includes('<episodedetails'))) {
      return null;
    }
    const title = NfoParser.extractTag(xml, 'title');
    const originalTitle = NfoParser.extractTag(xml, 'originaltitle');
    const yearRaw = NfoParser.extractTag(xml, 'year');
    const overview = NfoParser.extractTag(xml, 'plot') || NfoParser.extractTag(xml, 'outline');
    const ratingRaw = NfoParser.extractTag(xml, 'rating') || NfoParser.extractTag(xml, 'value');
    const tmdbRaw = NfoParser.extractTag(xml, 'tmdbid');
    const seasonRaw = NfoParser.extractTag(xml, 'season');
    const episodeRaw = NfoParser.extractTag(xml, 'episode');
    const posterUrl = NfoParser.extractTag(xml, 'thumb');

    return {
      title,
      originalTitle,
      year: yearRaw ? (parseInt(yearRaw, 10) || 0) : 0,
      overview,
      rating: ratingRaw ? (parseFloat(ratingRaw) || 0) : 0,
      tmdbId: tmdbRaw ? (parseInt(tmdbRaw, 10) || 0) : 0,
      seasonNo: seasonRaw ? (parseInt(seasonRaw, 10) || 1) : 1,
      episodeNo: episodeRaw ? (parseInt(episodeRaw, 10) || 0) : 0,
      posterUrl: posterUrl.startsWith('http') ? posterUrl : '',
      thumbRaw: posterUrl
    };
  }
}
