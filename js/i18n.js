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
    'empty.modelLabel': 'Model',
    'empty.loadModel': 'Load model',
    'empty.loadingModel': 'Loading…',
    'empty.modelReady': 'Model ready',
    'empty.retryLoad': 'Retry load',
    'topbar.model': 'Model',
    'topbar.lang': 'Output',
    'topbar.history': 'History',
    'topbar.new': 'New',
    'session.summary': 'Summary',
    'session.breakdown': 'Generate study breakdown',
    'session.chatHeading': 'Follow-up',
    'session.userRole': 'You',
    'session.assistantRole': 'Tutor',
    'session.export': 'Export to Obsidian',
    'session.exportNotSupported': 'File export needs Chrome, Edge, or Arc.',
    'session.exportSuccess': 'Saved {filename}',
    'session.exportFailed': 'Export failed: {error}',
    'session.exportCancelled': 'Export cancelled',
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
    'history.synthesize': 'Synthesize',
    'history.synthesizeHint': 'Find themes and gaps across past sessions',
    'synthesis.heading': 'What you have been studying',
    'synthesis.subheading': 'Across {count} sessions',
    'synthesis.notEnough': 'You need at least 2 past summaries before a synthesis is meaningful.',
    'synthesis.thinking': 'Reading your past sessions…',
    'synthesis.export': 'Export synthesis to Obsidian',
    'synthesis.archived': 'Archived {count} sessions from history',
  },
  ja: {
    'app.title': 'スクリーンショット家庭教師',
    'empty.heading': 'スクリーンショットを貼り付けるか、画像をドロップ、ファイル選択',
    'empty.hint': 'Cmd+V で貼り付け · Finder からドラッグ · または下のボタン',
    'empty.pick': 'ファイルを選択',
    'empty.capture': '画面をキャプチャ',
    'empty.webgpuRequired': 'WebGPU が必要です。Apple Silicon の Chrome / Edge / Arc を使ってください。',
    'empty.modelLabel': 'モデル',
    'empty.loadModel': 'モデルを読み込む',
    'empty.loadingModel': '読み込み中…',
    'empty.modelReady': 'モデル準備完了',
    'empty.retryLoad': '再試行',
    'topbar.model': 'モデル',
    'topbar.lang': '出力言語',
    'topbar.history': '履歴',
    'topbar.new': '新規',
    'session.summary': '要約',
    'session.breakdown': '学習ブレイクダウンを生成',
    'session.chatHeading': 'フォローアップ',
    'session.userRole': 'あなた',
    'session.assistantRole': '家庭教師',
    'session.export': 'Obsidian にエクスポート',
    'session.exportNotSupported': 'ファイルエクスポートには Chrome / Edge / Arc が必要です。',
    'session.exportSuccess': '{filename} を保存しました',
    'session.exportFailed': 'エクスポート失敗: {error}',
    'session.exportCancelled': 'エクスポートをキャンセルしました',
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
    'history.synthesize': '学びを統合',
    'history.synthesizeHint': '過去のセッション全体からテーマや不足を見つけます',
    'synthesis.heading': '最近学んだこと',
    'synthesis.subheading': '{count} 件のセッションを通して',
    'synthesis.notEnough': '統合するには過去の要約が 2 件以上必要です。',
    'synthesis.thinking': '過去のセッションを読んでいます…',
    'synthesis.export': 'Obsidian にエクスポート',
    'synthesis.archived': '{count} 件のセッションを履歴から整理しました',
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
