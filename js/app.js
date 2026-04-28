// js/app.js
// Sandbox UI: paste / drop / pick zone that previews the normalized image.
// Replaced in later tasks with the real component-based UI.
import { installInputHandlers } from './input.js';

const root = document.getElementById('app');
root.innerHTML = `
  <div class="sandbox" id="zone" tabindex="0">
    <h1>Screenshot Tutor — sandbox</h1>
    <p>Paste (Cmd+V), drop, or <button id="pick">pick a file</button>.</p>
    <div id="preview"></div>
    <div id="msg" class="muted"></div>
  </div>
`;

const zone = document.getElementById('zone');
const preview = document.getElementById('preview');
const msg = document.getElementById('msg');

const handlers = installInputHandlers(
  zone,
  ({ image, thumb, width, height }) => {
    msg.textContent = `loaded ${width}x${height}`;
    preview.innerHTML = `<img src="${image}" style="max-width:100%; border:1px solid #ccc;">`;
  },
  (err) => {
    msg.textContent = 'error: ' + err;
  },
);

document.getElementById('pick').addEventListener('click', () => handlers.pickFile());
