import { ExternalSubtitleTrack, SubtitleCue, SubtitleLangTag, SubtitleLanguageMode } from '../common/Types';

interface AssStyleDef {
  name: string;
  primaryColorHex: string;
  bold: boolean;
  italic: boolean;
  alignment: number;
}

export class SubtitleEngine {
  static parse(content: string, label: string, sourceUrl: string): ExternalSubtitleTrack {
    const cleanContent = content.replace(/^\uFEFF/, '');
    const lowerUrl = sourceUrl.toLowerCase();
    const trimmed = cleanContent.trim();
    let format: 'ass' | 'ssa' | 'srt' | 'vtt' = 'srt';
    if (lowerUrl.endsWith('.ass') || trimmed.includes('[Script Info]') || trimmed.includes('[V4+ Styles]')) {
      format = 'ass';
    } else if (lowerUrl.endsWith('.ssa') || trimmed.includes('[V4 Styles]')) {
      format = 'ssa';
    } else if (lowerUrl.endsWith('.vtt') || trimmed.startsWith('WEBVTT')) {
      format = 'vtt';
    }

    let cues: SubtitleCue[] = [];
    if (format === 'ass' || format === 'ssa') {
      cues = SubtitleEngine.parseAss(cleanContent);
    } else {
      cues = SubtitleEngine.parseSrtOrVtt(cleanContent);
    }

    cues.sort((a, b) => a.startMs - b.startMs);
    return {
      id: `${sourceUrl}_${label}`,
      label,
      format,
      sourceUrl,
      langTag: SubtitleEngine.detectLangTag(label, cues),
      cues
    };
  }

  // Detect track language: filename hints first, then sample cue text for CJK content
  static detectLangTag(label: string, cues: SubtitleCue[]): SubtitleLangTag {
    const lower = (label || '').toLowerCase();
    const dualHints = ['chs&eng', 'chs.eng', 'chs-eng', 'chs_eng', 'chsen', '简英', '英简', '双语', '双语字幕', 'chs+eng', 'zh-en', 'zhen', 'bilingual'];
    for (let i = 0; i < dualHints.length; i++) {
      if (lower.includes(dualHints[i])) return 'zh-en';
    }
    const zhHints = ['chs', 'cht', 'zh', 'cn', 'sc', 'tc', 'gb', 'big5', '简体', '繁体', '中文', '国配', '中字'];
    let hasZhHint = false;
    for (let i = 0; i < zhHints.length; i++) {
      if (lower.includes(zhHints[i])) {
        hasZhHint = true;
        break;
      }
    }
    const enHints = ['eng', 'en.', 'en_', '.en', 'english', '英文', '英语'];
    let hasEnHint = false;
    for (let i = 0; i < enHints.length; i++) {
      if (lower.includes(enHints[i])) {
        hasEnHint = true;
        break;
      }
    }
    if (hasZhHint && hasEnHint) return 'zh-en';
    if (hasZhHint) return 'zh';
    if (hasEnHint) return 'en';

    // Content fallback: sample the first cues and split into lines
    let zhLines = 0;
    let enLines = 0;
    const sampleLimit = Math.min(cues.length, 30);
    for (let i = 0; i < sampleLimit; i++) {
      const lines = cues[i].text.split('\n');
      for (let j = 0; j < lines.length; j++) {
        const line = lines[j].trim();
        if (!line) continue;
        if (/[\u4e00-\u9fff\u3400-\u4dbf]/.test(line)) {
          zhLines++;
        } else if (/[A-Za-z]{2,}/.test(line)) {
          enLines++;
        }
      }
    }
    if (zhLines > 0 && enLines > 0) return 'zh-en';
    if (zhLines > 0) return 'zh';
    if (enLines > 0) return 'en';
    return 'und';
  }

  // Line-level language filter for bilingual cues; returns the cue text with
  // only the lines matching the requested language, '' when nothing survives
  static filterCueLines(text: string, mode: SubtitleLanguageMode): string {
    if (mode === 'all' || !text) return text;
    const lines = text.split('\n');
    const kept: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;
      const hasCjk = /[\u4e00-\u9fff\u3400-\u4dbf]/.test(line);
      if (mode === 'zh' && hasCjk) {
        kept.push(line);
      } else if (mode === 'en' && !hasCjk) {
        kept.push(line);
      }
    }
    return kept.join('\n');
  }

  static findActiveCues(cues: SubtitleCue[], positionMs: number, delayMs: number): SubtitleCue[] {
    if (!cues || cues.length === 0) return [];
    const t = positionMs - delayMs;
    // Binary search for the first cue whose startMs > t, then scan backwards over overlapping cues
    let lo = 0;
    let hi = cues.length - 1;
    let upper = cues.length;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (cues[mid].startMs > t) {
        upper = mid;
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }

    const active: SubtitleCue[] = [];
    const scanStart = Math.max(0, upper - 24);
    for (let i = scanStart; i < upper; i++) {
      const c = cues[i];
      if (c.startMs <= t && t <= c.endMs) {
        active.push(c);
      }
    }
    return active;
  }

  private static parseTimeMs(raw: string): number {
    // Supports "00:01:23,456", "00:01:23.456", "1:23.45", "0:01:23.45" (ASS centiseconds)
    const cleaned = raw.trim().replace(',', '.');
    const parts = cleaned.split(':');
    if (parts.length === 3) {
      const h = parseInt(parts[0], 10) || 0;
      const m = parseInt(parts[1], 10) || 0;
      const secParts = parts[2].split('.');
      const s = parseInt(secParts[0], 10) || 0;
      let frac = 0;
      if (secParts.length > 1) {
        const fracStr = secParts[1];
        if (fracStr.length === 2) {
          frac = (parseInt(fracStr, 10) || 0) * 10; // centiseconds -> ms
        } else {
          frac = parseInt(fracStr.padEnd(3, '0').substring(0, 3), 10) || 0;
        }
      }
      return ((h * 3600 + m * 60 + s) * 1000) + frac;
    }
    if (parts.length === 2) {
      const m = parseInt(parts[0], 10) || 0;
      const secParts = parts[1].split('.');
      const s = parseInt(secParts[0], 10) || 0;
      const ms = secParts.length > 1 ? (parseInt(secParts[1].padEnd(3, '0').substring(0, 3), 10) || 0) : 0;
      return ((m * 60 + s) * 1000) + ms;
    }
    return 0;
  }

  private static parseSrtOrVtt(content: string): SubtitleCue[] {
    const normalized = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const blocks = normalized.split(/\n{2,}/);
    const cues: SubtitleCue[] = [];
    let idx = 0;

    for (let i = 0; i < blocks.length; i++) {
      const lines = blocks[i].split('\n').map(l => l.trim()).filter(l => l.length > 0);
      if (lines.length === 0) continue;
      if (lines[0].startsWith('WEBVTT') || lines[0].startsWith('NOTE')) continue;

      let timeLineIdx = 0;
      if (!lines[0].includes('-->') && lines.length > 1 && lines[1].includes('-->')) {
        timeLineIdx = 1;
      }
      if (!lines[timeLineIdx] || !lines[timeLineIdx].includes('-->')) continue;

      const timeParts = lines[timeLineIdx].split('-->');
      const startMs = SubtitleEngine.parseTimeMs(timeParts[0]);
      const endRaw = timeParts[1].trim().split(/\s+/)[0];
      const endMs = SubtitleEngine.parseTimeMs(endRaw);
      if (endMs <= startMs) continue;

      const textLines = lines.slice(timeLineIdx + 1);
      if (textLines.length === 0) continue;
      const rawText = textLines.join('\n');
      const isBold = /<b>/i.test(rawText);
      const isItalic = /<i>/i.test(rawText);
      const cleanText = rawText
        .replace(/<[^>]+>/g, '')
        .replace(/\{\\[^}]+\}/g, '')
        .trim();
      if (!cleanText) continue;

      cues.push({
        index: idx++,
        startMs,
        endMs,
        text: cleanText,
        alignment: 2,
        colorHex: '#FFFFFF',
        isBold,
        isItalic,
        layer: 0
      });
    }
    return cues;
  }

  private static assColorToHex(assColor: string): string {
    // ASS format: &HAABBGGRR or &HBBGGRR&
    const m = assColor.match(/&H([0-9A-Fa-f]{6,8})&?/);
    if (!m) return '#FFFFFF';
    let hex = m[1];
    if (hex.length === 8) {
      hex = hex.substring(2); // strip AA alpha
    }
    if (hex.length !== 6) return '#FFFFFF';
    const bb = hex.substring(0, 2);
    const gg = hex.substring(2, 4);
    const rr = hex.substring(4, 6);
    return `#${rr}${gg}${bb}`.toUpperCase();
  }

  private static parseAss(content: string): SubtitleCue[] {
    const lines = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    let section = '';
    const styles = new Map<string, AssStyleDef>();
    let styleFormat: string[] = [];
    let eventFormat: string[] = ['Layer', 'Start', 'End', 'Style', 'Name', 'MarginL', 'MarginR', 'MarginV', 'Effect', 'Text'];
    const cues: SubtitleCue[] = [];
    let idx = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.toLowerCase();
        continue;
      }

      if (section === '[v4+ styles]' || section === '[v4 styles]') {
        if (line.toLowerCase().startsWith('format:')) {
          styleFormat = line.substring(7).split(',').map(s => s.trim().toLowerCase());
        } else if (line.toLowerCase().startsWith('style:')) {
          const vals = line.substring(6).split(',').map(s => s.trim());
          const nameIdx = styleFormat.indexOf('name');
          const colorIdx = styleFormat.indexOf('primarycolour');
          const boldIdx = styleFormat.indexOf('bold');
          const italicIdx = styleFormat.indexOf('italic');
          const alignIdx = styleFormat.indexOf('alignment');
          const styleName = nameIdx >= 0 && nameIdx < vals.length ? vals[nameIdx] : 'Default';
          styles.set(styleName, {
            name: styleName,
            primaryColorHex: colorIdx >= 0 && colorIdx < vals.length ? SubtitleEngine.assColorToHex(vals[colorIdx]) : '#FFFFFF',
            bold: boldIdx >= 0 && boldIdx < vals.length ? vals[boldIdx] === '-1' || vals[boldIdx] === '1' : false,
            italic: italicIdx >= 0 && italicIdx < vals.length ? vals[italicIdx] === '-1' || vals[italicIdx] === '1' : false,
            alignment: alignIdx >= 0 && alignIdx < vals.length ? (parseInt(vals[alignIdx], 10) || 2) : 2
          });
        }
      } else if (section === '[events]') {
        if (line.toLowerCase().startsWith('format:')) {
          eventFormat = line.substring(7).split(',').map(s => s.trim().toLowerCase());
        } else if (line.toLowerCase().startsWith('dialogue:')) {
          const body = line.substring(9).trim();
          const fieldCount = eventFormat.length;
          const cols: string[] = [];
          let cursor = 0;
          for (let f = 0; f < fieldCount - 1; f++) {
            const comma = body.indexOf(',', cursor);
            if (comma < 0) break;
            cols.push(body.substring(cursor, comma).trim());
            cursor = comma + 1;
          }
          cols.push(body.substring(cursor));
          if (cols.length < fieldCount) continue;

          const startIdx = eventFormat.indexOf('start');
          const endIdx = eventFormat.indexOf('end');
          const styleIdx = eventFormat.indexOf('style');
          const layerIdx = eventFormat.indexOf('layer');
          const textIdx = fieldCount - 1;

          const startMs = startIdx >= 0 ? SubtitleEngine.parseTimeMs(cols[startIdx]) : 0;
          const endMs = endIdx >= 0 ? SubtitleEngine.parseTimeMs(cols[endIdx]) : 0;
          if (endMs <= startMs) continue;

          const styleName = styleIdx >= 0 ? cols[styleIdx] : 'Default';
          const styleDef = styles.get(styleName);
          const layer = layerIdx >= 0 ? (parseInt(cols[layerIdx], 10) || 0) : 0;
          const rawText = cols[textIdx];

          // Skip ASS vector drawings (\p1 ... \p0)
          if (/\{\\[^}]*\\p[1-9]/.test(rawText)) continue;

          let alignment = styleDef ? styleDef.alignment : 2;
          let colorHex = styleDef ? styleDef.primaryColorHex : '#FFFFFF';
          let isBold = styleDef ? styleDef.bold : false;
          let isItalic = styleDef ? styleDef.italic : false;

          const anMatch = rawText.match(/\\an([1-9])/);
          if (anMatch) alignment = parseInt(anMatch[1], 10);

          const cMatch = rawText.match(/\\(?:1?c)(&H[0-9A-Fa-f]{6,8}&?)/);
          if (cMatch) colorHex = SubtitleEngine.assColorToHex(cMatch[1]);

          if (/\\b1/.test(rawText)) isBold = true;
          if (/\\i1/.test(rawText)) isItalic = true;

          const cleanText = rawText
            .replace(/\{[^}]*\}/g, '')
            .replace(/\\N/g, '\n')
            .replace(/\\n/g, '\n')
            .replace(/\\h/g, ' ')
            .trim();
          if (!cleanText) continue;

          cues.push({
            index: idx++,
            startMs,
            endMs,
            text: cleanText,
            alignment,
            colorHex,
            isBold,
            isItalic,
            layer
          });
        }
      }
    }
    return cues;
  }
}
