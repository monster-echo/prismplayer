/** 协议正文的最小 Markdown 解析：只处理标题、列表、段落，够用且不引入依赖。 */
export interface LegalBlock {
  kind: string;
  text: string;
}

function stripInline(text: string): string {
  return text.replace(/\*\*/g, '').replace(/`/g, '').trim();
}

export function navTitleFor(docType: string): string {
  return docType === 'agreement' ? '用户服务协议' : '隐私政策';
}

export function parseLegalMarkdown(md: string): LegalBlock[] {
  const out: LegalBlock[] = [];
  const lines = md.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (i === 0 && line.startsWith('# ')) {
      continue;
    }
    if (line.length === 0 || line === '---') {
      if (out.length > 0 && out[out.length - 1].kind !== 'gap') {
        out.push({ kind: 'gap', text: '' });
      }
      continue;
    }
    if (line.startsWith('### ')) {
      out.push({ kind: 'h3', text: stripInline(line.substring(4)) });
    } else if (line.startsWith('## ')) {
      out.push({ kind: 'h2', text: stripInline(line.substring(3)) });
    } else if (line.startsWith('- ')) {
      out.push({ kind: 'li', text: stripInline(line.substring(2)) });
    } else {
      out.push({ kind: 'p', text: stripInline(line) });
    }
  }
  return out;
}
