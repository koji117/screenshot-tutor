// js/prompts.js
// Prompt templates for the three operations. Tunable in one place.

const EN = {
  summarize:
    'You are a study tutor. Look at this screenshot and produce a concise ' +
    'study-friendly summary in markdown. Format: a one-sentence TL;DR (bold), ' +
    'then 3-5 key bullet points. Focus on what someone studying this material ' +
    'needs to take away. If it is code, summarize what the code does and the ' +
    'key concept it demonstrates. If it is a problem, identify the problem ' +
    'type and solution approach without giving away the answer. Keep it ' +
    'under 200 words.',

  breakdown: (summary) =>
    'Given the screenshot above and your prior summary, produce a study ' +
    'breakdown in markdown:\n\n' +
    '1. **Key terms** — 3-6 terms or concepts with one-line definitions.\n' +
    '2. **Practice questions** — 2-3 questions that test understanding ' +
    '(not trivia recall). Mark each with difficulty (easy/medium/hard). ' +
    'Provide answers in collapsible sections using ' +
    '`<details><summary>Answer</summary>...</details>`.\n\n' +
    'Your prior summary, for reference:\n\n' + summary,

  chatSystem: (summary) =>
    'You are a study tutor helping a learner understand a screenshot they ' +
    'have shared. The screenshot is above and your earlier summary follows. ' +
    'Answer their follow-up questions clearly and concisely. If they ask for ' +
    'a fact you cannot verify from the screenshot, say so rather than ' +
    'guessing. Match their depth: a short question gets a short answer.\n\n' +
    'Your earlier summary:\n\n' + summary,

  synthesize: (summaries) =>
    'You are a study tutor reviewing what a learner has been studying ' +
    'recently. Below are summaries of ' + summaries.length + ' screenshots ' +
    'they\'ve worked through, newest first. Produce a synthesis in markdown:\n\n' +
    '1. **Themes** — 2-4 recurring topics or concepts across these sessions.\n' +
    '2. **Connections** — how the topics relate to each other (one or two sentences).\n' +
    '3. **Strengths** — what the learner seems to have a solid grasp of.\n' +
    '4. **Gaps** — what is underexplored or could use more depth.\n' +
    '5. **Suggested next steps** — 2-3 specific things to study next based on the pattern.\n\n' +
    'Stay grounded in what the summaries actually say — do not invent topics ' +
    'that are not there. Keep the whole synthesis under 350 words.\n\n' +
    'Summaries:\n\n' +
    summaries.map((s, i) => '### Session ' + (i + 1) + '\n\n' + s).join('\n\n---\n\n'),
};

const JA = {
  summarize:
    'あなたは学習サポートの家庭教師です。このスクリーンショットを見て、' +
    '学習者向けの簡潔な要約を Markdown で作成してください。' +
    'フォーマット: 1文で太字の TL;DR、その後に 3〜5 個の重要なポイントを箇条書きで。' +
    'これを学んでいる人が押さえるべき要点に絞ってください。' +
    'コードであれば、コードが何をするかと示している重要な概念を要約してください。' +
    '問題であれば、答えを言わずに問題のタイプと解法のアプローチを示してください。' +
    '200語以内に収めてください。',

  breakdown: (summary) =>
    '上のスクリーンショットとあなたの先ほどの要約を踏まえて、' +
    '学習用ブレイクダウンを Markdown で作成してください:\n\n' +
    '1. **重要用語** — 3〜6 個の用語または概念を 1 行の定義つきで。\n' +
    '2. **練習問題** — 理解度を試す問題を 2〜3 問 (単なる暗記の確認ではなく)。' +
    'それぞれ難易度を easy / medium / hard でマークしてください。' +
    '答えは `<details><summary>答え</summary>...</details>` の折りたたみで提供してください。\n\n' +
    '参照用のあなたの先ほどの要約:\n\n' + summary,

  chatSystem: (summary) =>
    'あなたはスクリーンショットを共有してきた学習者を助ける家庭教師です。' +
    'スクリーンショットは上にあり、あなたの先ほどの要約は次の通りです。' +
    '彼らのフォローアップの質問に明確かつ簡潔に答えてください。' +
    'スクリーンショットから確認できない事実については、推測せずにその旨を伝えてください。' +
    '質問の深さに合わせてください: 短い質問には短い答えを。\n\n' +
    'あなたの先ほどの要約:\n\n' + summary,

  synthesize: (summaries) =>
    'あなたは学習者が最近学んだ内容を振り返る家庭教師です。' +
    '以下は、学習者が取り組んだ ' + summaries.length + ' 件のスクリーンショットの要約です (新しい順)。' +
    '次の構成で Markdown による「学びの統合」を作成してください:\n\n' +
    '1. **テーマ** — これらのセッションを通じて繰り返し現れる 2〜4 個のトピックや概念。\n' +
    '2. **つながり** — それらのトピックがどう関係しているか (1〜2 文で)。\n' +
    '3. **強み** — 学習者がしっかり理解できていそうな点。\n' +
    '4. **不足** — 掘り下げが足りない、または深める余地がある点。\n' +
    '5. **次の学習ステップ** — このパターンを踏まえた具体的な提案を 2〜3 個。\n\n' +
    '要約に書かれている内容にだけ基づいてください — 書かれていないトピックを' +
    '勝手に加えないでください。全体で 350 語以内に収めてください。\n\n' +
    '要約:\n\n' +
    summaries.map((s, i) => '### セッション ' + (i + 1) + '\n\n' + s).join('\n\n---\n\n'),
};

const TABLES = { en: EN, ja: JA };

export function summarizePrompt(lang) {
  return (TABLES[lang] || EN).summarize;
}

export function breakdownPrompt(lang, summary) {
  return (TABLES[lang] || EN).breakdown(summary || '');
}

export function chatSystemPrompt(lang, summary) {
  return (TABLES[lang] || EN).chatSystem(summary || '');
}

export function synthesisPrompt(lang, summaries) {
  return (TABLES[lang] || EN).synthesize(summaries || []);
}
