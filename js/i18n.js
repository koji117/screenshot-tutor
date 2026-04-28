// js/i18n.js
// Tiny string table for the UI. Output language for the LLM is handled
// separately in prompts.js.

const STRINGS = {
  en: {
    'app.title': 'Screenshot Tutor',
    'empty.heading': 'Paste a screenshot, drop an image, or pick a file',
    'empty.hint': 'Cmd+V to paste · drag from Finder · or click below',
    'empty.pick': 'Pick a file',
    'empty.capture': 'Capture screen',
    'empty.webgpuRequired': 'WebGPU is required. Use Chrome, Edge, or Arc on Apple Silicon.',
    'topbar.model': 'Model',
    'topbar.lang': 'Output',
    'topbar.history': 'History',
    'topbar.new': 'New',
    'session.summary': 'Summary',
    'session.breakdown': 'Generate study breakdown',
    'session.chatHeading': 'Follow-up',
    'session.userRole': 'You',
    'session.assistantRole': 'Tutor',
    'session.askPlaceholder': 'Ask a follow-up about this screenshot…',
    'session.send': 'Send',
    'session.cancel': 'Cancel',
    'session.loading': 'Loading model… {pct}%',
    'session.thinking': 'Thinking…',
    'session.errorPaste': "Clipboard didn't contain an image",
    'session.errorDrop': "Dropped item wasn't an image",
    'session.errorWorker': 'Worker error: {error}',
    'session.errorBusy': 'Already generating — wait or cancel first',
    'history.empty': 'No past screenshots yet.',
    'history.delete': 'Delete',
    'history.confirmDelete': 'Delete this screenshot?',
  },
  ja: {
    'app.title': 'スクリーンショット家庭教師',
    'empty.heading': 'スクリーンショットを貼り付けるか、画像をドロップ、ファイル選択',
    'empty.hint': 'Cmd+V で貼り付け · Finder からドラッグ · または下のボタン',
    'empty.pick': 'ファイルを選択',
    'empty.capture': '画面をキャプチャ',
    'empty.webgpuRequired': 'WebGPU が必要です。Apple Silicon の Chrome / Edge / Arc を使ってください。',
    'topbar.model': 'モデル',
    'topbar.lang': '出力言語',
    'topbar.history': '履歴',
    'topbar.new': '新規',
    'session.summary': '要約',
    'session.breakdown': '学習ブレイクダウンを生成',
    'session.chatHeading': 'フォローアップ',
    'session.userRole': 'あなた',
    'session.assistantRole': '家庭教師',
    'session.askPlaceholder': 'このスクリーンショットについて質問…',
    'session.send': '送信',
    'session.cancel': 'キャンセル',
    'session.loading': 'モデル読み込み中… {pct}%',
    'session.thinking': '考え中…',
    'session.errorPaste': 'クリップボードに画像がありません',
    'session.errorDrop': 'ドロップされた項目は画像ではありません',
    'session.errorWorker': 'ワーカーエラー: {error}',
    'session.errorBusy': '生成中です — 待つかキャンセルしてください',
    'history.empty': '過去のスクリーンショットはありません',
    'history.delete': '削除',
    'history.confirmDelete': 'このスクリーンショットを削除しますか?',
  },
};

export function t(key, lang) {
  const table = STRINGS[lang] || STRINGS.en;
  let s = table[key];
  if (s == null) s = STRINGS.en[key];
  if (s == null) return key;
  return s;
}

export function tFmt(key, lang, vars) {
  let s = t(key, lang);
  if (vars) {
    for (const [k, v] of Object.entries(vars)) {
      s = s.replace('{' + k + '}', String(v));
    }
  }
  return s;
}
