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
};

// JA placeholders — filled in a later task with proper translations.
const JA = {
  summarize: EN.summarize,
  breakdown: EN.breakdown,
  chatSystem: EN.chatSystem,
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
