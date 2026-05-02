// js/components/markdown.js
// Minimal streaming-safe markdown renderer.
// Supports: **bold**, *italic*, `code`, lists (- / 1.), paragraphs, line breaks,
// $...$ inline math, $$...$$ block math (rendered with KaTeX, lazy-loaded),
// and a tiny HTML allowlist for <details>/<summary> (for collapsible answers).
// Everything else is escaped.

const MATH_OPEN = '\x00';
const MATH_CLOSE = '\x01';

function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function escapeAttr(s) {
  return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
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

// Pull math segments out of the source before any other processing so
// LaTeX braces, backslashes, asterisks and underscores survive the
// markdown pipeline. Only matches *closed* delimiters so a half-streamed
// `$x +` is left alone until the closing `$` arrives.
function extractMath(src) {
  const segments = [];
  let processed = src.replace(/\$\$([\s\S]+?)\$\$/g, (_, body) => {
    segments.push({ display: true, body });
    return MATH_OPEN + 'M' + (segments.length - 1) + MATH_CLOSE;
  });
  processed = processed.replace(/\$([^$\n]+?)\$/g, (_, body) => {
    segments.push({ display: false, body });
    return MATH_OPEN + 'M' + (segments.length - 1) + MATH_CLOSE;
  });
  return { processed, segments };
}

function restoreMath(html, segments) {
  if (segments.length === 0) return html;
  const re = new RegExp(MATH_OPEN + 'M(\\d+)' + MATH_CLOSE, 'g');
  return html.replace(re, (_, idx) => {
    const seg = segments[parseInt(idx, 10)];
    if (!seg) return '';
    const klass = seg.display ? 'math-block' : 'math-inline';
    return '<span class="' + klass + '" data-tex="' + escapeAttr(seg.body) + '"></span>';
  });
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
  const { processed, segments } = extractMath(src || '');
  const escaped = escapeHtml(processed);
  const restored = restoreAllowedTags(escaped);
  const html = renderBlocks(restored);
  return restoreMath(html, segments);
}

// --- KaTeX lazy loader ---
// CSS + JS are pulled from jsDelivr the first time math is encountered.
// On failure (offline, blocked CDN), math nodes fall back to the raw
// LaTeX source via the `:empty::before` rule in css/app.css so the
// reader still sees something useful.

const KATEX_VERSION = '0.16.11';
const KATEX_CSS = 'https://cdn.jsdelivr.net/npm/katex@' + KATEX_VERSION + '/dist/katex.min.css';
const KATEX_JS = 'https://cdn.jsdelivr.net/npm/katex@' + KATEX_VERSION + '/dist/katex.min.js';

let katexPromise = null;

function loadKatex() {
  if (katexPromise) return katexPromise;
  if (typeof document === 'undefined') return Promise.resolve(null);
  katexPromise = new Promise((resolve, reject) => {
    const css = document.createElement('link');
    css.rel = 'stylesheet';
    css.href = KATEX_CSS;
    document.head.appendChild(css);

    const script = document.createElement('script');
    script.src = KATEX_JS;
    script.async = true;
    script.onload = () => resolve(window.katex || null);
    script.onerror = () => {
      katexPromise = null; // allow retry on next call
      reject(new Error('failed to load KaTeX'));
    };
    document.head.appendChild(script);
  });
  return katexPromise;
}

function renderMathIn(root) {
  const nodes = root.querySelectorAll('.math-inline, .math-block');
  if (nodes.length === 0) return;
  loadKatex().then((katex) => {
    if (!katex) return;
    nodes.forEach((node) => {
      const tex = node.dataset.tex || '';
      const display = node.classList.contains('math-block');
      try {
        katex.render(tex, node, { displayMode: display, throwOnError: false });
      } catch {
        node.textContent = tex;
      }
    });
  }).catch(() => {
    // CDN failed; the :empty::before fallback in CSS will surface the
    // raw TeX so the reader isn't left staring at a blank space.
  });
}

export function setMarkdown(el, src) {
  el.innerHTML = renderMarkdown(src);
  renderMathIn(el);
}
