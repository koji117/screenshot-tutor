# Testing

## Unit tests

Open these in a WebGPU-capable browser served from `python3 -m http.server`:

- `http://localhost:8000/js/store.test.html`
- `http://localhost:8000/js/input.test.html`
- `http://localhost:8000/js/i18n.test.html`

All assertions should be green.

## Manual acceptance checklist

1. Open `http://localhost:8000/` in Chrome / Edge / Arc on Apple Silicon.
2. **Empty state:** large dashed-bordered drop zone is visible with two buttons (Pick a file, Capture screen).
3. **Paste:** take a screenshot (`Cmd+Ctrl+Shift+4` for clipboard), `Cmd+V` into the page.
   - First time: status shows "Loading model… X%" for several minutes.
   - Once loaded: status shows "Thinking…" then summary streams in.
4. **Drop:** drag an image file from Finder anywhere into the page.
5. **File pick:** click "Pick a file" → file picker opens → select an image.
6. **Capture screen:** click "Capture screen" → browser picker appears → choose a screen/window/tab → region-selection overlay appears → drag a rectangle → click "Use selection" (Enter also confirms; Esc cancels). The cropped region runs through the same pipeline.
7. **Breakdown:** click "Generate study breakdown" under the summary → streams a list of key terms + practice questions with collapsible answers.
8. **Chat:** type a follow-up in the chat input → user bubble appears, then a Tutor bubble streams a response. Ask a second follow-up — both turns stay visible.
9. **Reload:** refresh the page. The current session is gone (returns to empty state) but past sessions are in the History drawer.
10. **History drawer:** click "History" in the topbar → drawer slides in from the left with thumbnail + summary preview for past sessions. Click one → it loads. Hover → delete (×) button reveals → confirm → it's deleted.
11. **Language toggle:** switch Output to JA — UI labels switch to Japanese. Paste a new screenshot → summary streams in Japanese.
12. **Model toggle:** switch Model to e2b — paste a screenshot. First load downloads the smaller model (~1.5GB).
13. **Error paths:**
    - Paste plain text → toast slides up: "clipboard didn't contain an image".
    - Drop a `.txt` file → toast: "dropped item wasn't an image".
    - Open in Safari → empty state shows the WebGPU-required message.
14. **Cancel:** click Cancel mid-generation → status clears, partial output is preserved.
15. **History cap:** add 25+ screenshots over multiple pastes → list caps at 20 (newest first).
