// js/components/markdown.js
// Minimal streaming-safe markdown renderer.
// Supports: **bold**, *italic*, `code`, lists (- / 1.), paragraphs, line breaks,
// and a tiny HTML allowlist for <details>/<summary> (for collapsible answers).
// Everything else is escaped.

function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function restoreAllowedTags(s) {
  return s
    .replace(/&lt;details&gt;/g, '<details>')
    .replace(/&lt;\/details&gt;/g, '</details>')
    .replace(/&lt;summary&gt;/g, '<summary>')
    .replace(/&lt;\/summary&gt;/g, '</summary>');
}

function inline(s) {
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>');
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  return s;
}

function renderBlocks(src) {
  const lines = src.split('\n');
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*$/.test(line)) { i++; continue; }

    if (/^\s*-\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*-\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*-\s+/, ''));
        i++;
      }
      out.push('<ul>' + items.map((x) => '<li>' + inline(x) + '</li>').join('') + '</ul>');
      continue;
    }

    if (/^\s*\d+\.\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*\d+\.\s+/, ''));
        i++;
      }
      out.push('<ol>' + items.map((x) => '<li>' + inline(x) + '</li>').join('') + '</ol>');
      continue;
    }

    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) {
      const level = h[1].length;
      out.push('<h' + level + '>' + inline(h[2]) + '</h' + level + '>');
      i++;
      continue;
    }

    if (/^<details>/.test(line) || /^<\/details>/.test(line) ||
        /^<summary>/.test(line) || /^<\/summary>/.test(line)) {
      out.push(inline(line));
      i++;
      continue;
    }

    const para = [line];
    i++;
    while (i < lines.length && !/^\s*$/.test(lines[i]) && !/^\s*-\s+/.test(lines[i]) && !/^\s*\d+\.\s+/.test(lines[i])) {
      para.push(lines[i]);
      i++;
    }
    out.push('<p>' + inline(para.join('<br>')) + '</p>');
  }
  return out.join('\n');
}

export function renderMarkdown(src) {
  const escaped = escapeHtml(src || '');
  const restored = restoreAllowedTags(escaped);
  return renderBlocks(restored);
}

export function setMarkdown(el, src) {
  el.innerHTML = renderMarkdown(src);
}
