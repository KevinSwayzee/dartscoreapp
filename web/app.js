/* DartScore frontend — talks to the JSON API and renders game state. */
'use strict';

const $ = (sel) => document.querySelector(sel);

// ---------- screens ----------
const screens = {
  config: $('#config-screen'),
  game: $('#game-screen'),
  over: $('#over-screen'),
};
function show(name) {
  for (const [k, el] of Object.entries(screens)) el.hidden = k !== name;
}

// ---------- config screen ----------
function segmented(id, onChange) {
  const box = $(id);
  box.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', () => {
      box.querySelectorAll('button').forEach((b) => b.classList.remove('selected'));
      btn.classList.add('selected');
      if (onChange) onChange(Number(btn.dataset.value));
    });
  });
  return () => Number(box.querySelector('button.selected').dataset.value);
}

const readGame = segmented('#game-choice');
const readSets = segmented('#sets-choice');
const readCount = segmented('#count-choice', (n) => {
  document.querySelectorAll('#name-fields input').forEach((inp) => {
    inp.hidden = Number(inp.dataset.idx) >= n;
  });
});

let lastConfig = null; // remembered for "Rematch"

$('#start-btn').addEventListener('click', async () => {
  const names = [...document.querySelectorAll('#name-fields input')]
    .slice(0, readCount())
    .map((inp, i) => inp.value.trim() || `Player ${i + 1}`);
  const config = {
    startScore: readGame(),
    bestOf: readSets(),
    players: names,
    doubleOut: $('#double-out').checked,
  };
  const state = await api('/api/game', config);
  if (state) {
    lastConfig = config;
    resetLocal();
    show('game');
    refresh(true);
  }
});

$('#rematch-btn').addEventListener('click', async () => {
  if (!lastConfig) {
    show('config'); // never joined this match from this page — go configure
    return;
  }
  const state = await api('/api/game', {
    ...lastConfig,
    continueStats: $('#keep-stats').checked,
  });
  if (state) {
    resetLocal();
    show('game');
    refresh(true);
  }
});

$('#newmatch-btn').addEventListener('click', () => show('config'));
$('#new-match-btn').addEventListener('click', () => show('config'));

$('#double-out').addEventListener('change', (e) => {
  const on = e.target.checked;
  $('#double-out-label').textContent = on ? 'Double out' : 'Single out';
  $('#rules-hint').textContent = on
    ? 'Checkout: double-out · Bust: below 0, on 1, or 0 without a double'
    : 'Checkout: single-out · Bust: below 0';
});

$('#keep-stats').addEventListener('change', (e) => {
  $('#keep-stats-label').textContent =
    e.target.checked ? 'Continue stats' : 'Reset stats';
});

// ---------- API ----------
async function api(path, body) {
  try {
    const res = await fetch(path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const data = await res.json();
    if (!res.ok) {
      toast(data.error || 'Error', 'bust');
      return null;
    }
    return data;
  } catch (e) {
    toast('Server unreachable', 'bust');
    return null;
  }
}

// ---------- state rendering ----------
let rev = -1;
let lastLogLen = 0;

function resetLocal() {
  rev = -1;
  lastLogLen = 0;
  kpValue = '';
  segMode = 'S';
  renderKeypad();
}

async function refresh(force = false) {
  if (screens.game.hidden && screens.over.hidden) return;
  const st = await api('/api/state');
  if (!st) return;
  if (!st.hasGame) {
    // Server discarded the game (idle timeout) — every tablet falls back
    // to the config screen with us.
    resetLocal();
    show('config');
    return;
  }
  if (!force && st.rev === rev) return;
  const first = rev === -1;
  rev = st.rev;
  render(st, first);
}

function render(st, first) {
  // scoreboard
  const sb = $('#scoreboard');
  sb.innerHTML = '';
  st.players.forEach((p, i) => {
    const chip = document.createElement('div');
    chip.className = 'pchip' + (p.active ? ' active' : '');
    chip.innerHTML =
      `<div class="pname"></div><div class="pscore">${p.score}</div>` +
      `<div class="psets">${'●'.repeat(p.setsWon)}${'○'.repeat(st.config.setsToWin - p.setsWon)}</div>`;
    chip.querySelector('.pname').textContent = p.name;
    sb.appendChild(chip);
  });

  // center
  const cur = st.players[st.currentPlayer];
  if (st.matchOver) {
    // Rebuild config from the server so Rematch works even after a page
    // reload or on a device that only joined this match.
    lastConfig = {
      startScore: st.config.startScore,
      bestOf: st.config.bestOf,
      players: st.config.names,
      doubleOut: st.config.doubleOut !== false,
    };
    $('#winner-text').textContent = `🏆 ${st.players[st.matchWinner].name} wins!`;
    $('#final-score').textContent = st.players
      .map((p) => `${p.name} ${p.setsWon}`)
      .join('  -  ');
    renderFinalStats(st.players);
    show('over');
  } else {
    // If another tablet started a new match while we showed 'over', follow.
    if (!screens.over.hidden) show('game');
    $('#turn-banner').textContent = `${cur.name} to throw`;
    $('#remaining-score').textContent = cur.score;
    renderOpenVisit(st);
  }

  // history of current player (this match, newest first)
  const who = st.matchOver ? st.matchWinner : st.currentPlayer;
  $('#history-player').textContent = st.players[who] ? st.players[who].name : '';
  const list = $('#visit-list');
  list.innerHTML = '';
  const mine = st.visits.filter((v) => v.player === who).slice(-30).reverse();
  for (const v of mine) {
    const li = document.createElement('li');
    li.className = v.busted ? 'bust' : v.checkout ? 'checkout' : '';
    li.innerHTML =
      `<span class="vlabels"></span><span class="vscore">${v.busted ? 'Bust' : v.scored}</span>`;
    li.querySelector('.vlabels').textContent = v.labels.join(' ');
    list.appendChild(li);
  }

  // stats of current player
  const s = cur;
  $('#stats-player').textContent = s.name;
  $('#stats-body').innerHTML = `
    <div class="stat-row hero"><span class="slabel">3-dart avg</span><span class="svalue">${s.avg.toFixed(1)}</span></div>
    <div class="stat-row"><span class="slabel">100+ visits</span><span class="svalue">${s.over100}</span></div>
    <div class="stat-row"><span class="slabel">140+ visits</span><span class="svalue">${s.over140}</span></div>
    <div class="stat-row"><span class="slabel">Highest checkout</span><span class="svalue">${checkoutLabel(s.highestCheckout)}</span></div>
    <div class="stat-row"><span class="slabel">Last visit</span><span class="svalue">${s.lastVisit}</span></div>
    <div class="stat-row"><span class="slabel">Best visit</span><span class="svalue">${s.bestVisit}</span></div>
    <div class="stat-row"><span class="slabel">Checkouts</span><span class="svalue">${s.checkouts} of ${s.checkoutAttempts}</span></div>
    <div class="stat-row"><span class="slabel">Darts thrown</span><span class="svalue">${s.dartsThrown}</span></div>
  `;

  $('#undo-btn').disabled = st.historyLength === 0;

  // toast for new log lines
  if (!first && st.log.length > lastLogLen) {
    const entry = st.log[st.log.length - 1];
    toast(entry.text, entry.kind === 'bust' ? 'bust' : entry.kind === 'match' ? 'match' : '');
  }
  lastLogLen = st.log.length;
}

/// Player-vs-stat table shown on the match-over screen.
function renderFinalStats(players) {
  const rows = [
    ['3-dart avg', (p) => p.avg.toFixed(1)],
    ['100+ visits', (p) => p.over100],
    ['140+ visits', (p) => p.over140],
    ['Highest checkout', (p) => checkoutLabel(p.highestCheckout)],
    ['Checkouts', (p) => `${p.checkouts} of ${p.checkoutAttempts}`],
    ['Best visit', (p) => p.bestVisit],
    ['Darts thrown', (p) => p.dartsThrown],
  ];
  const esc = (s) =>
    String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  $('#final-stats').innerHTML =
    '<table><tr><th></th>' +
    players.map((p) => `<th>${esc(p.name)}</th>`).join('') +
    '</tr>' +
    rows
      .map(
        ([label, fn]) =>
          `<tr><td class="fsl">${label}</td>` +
          players.map((p) => `<td>${esc(fn(p))}</td>`).join('') +
          '</tr>',
      )
      .join('') +
    '</table>';
}

/// "32" → "D16 (32)", "50" → "Bull (50)", 0 → "—"
function checkoutLabel(points) {
  if (!points) return '—';
  if (points === 50) return 'Bull (50)';
  return points % 2 === 0 ? `D${points / 2} (${points})` : `${points}`;
}

function renderOpenVisit(st) {
  const ov = st.openVisit;
  const el = $('#open-visit');
  if (!ov) {
    el.textContent = '';
    return;
  }
  el.innerHTML = ov.labels
    .map((l) => `<span class="done">${l}</span>`)
    .join(' · ');
}

// ---------- toast ----------
let toastTimer = null;
function toast(text, kind = '') {
  const t = $('#toast');
  t.textContent = text;
  t.className = kind;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (t.hidden = true), 2600);
}

// ---------- keypad ----------
// Entry model: a ring segment type (S → D → T) + the segment number you hit.
// D25 = Bull (50). Points sent to the server: S=seg, D=seg*2, T=seg*3.
let kpValue = '';
let segMode = 'S'; // 'S' | 'D' | 'T'

function cycleSeg() {
  segMode = segMode === 'S' ? 'D' : segMode === 'D' ? 'T' : 'S';
}

/// Converts (segMode, kpValue) into {points, double} or {error}.
function buildThrow() {
  const seg = Number(kpValue);
  if (!(seg >= 1 && seg <= 20) && seg !== 25) {
    return { error: 'Segment must be 1-20 or 25' };
  }
  if (seg === 25 && segMode === 'T') return { error: 'No triple 25' };
  const mult = segMode === 'S' ? 1 : segMode === 'D' ? 2 : 3;
  return { points: seg * mult, double: segMode === 'D' };
}

function renderKeypad() {
  $('#kp-value').textContent = kpValue || ' ';
  const chip = $('#kp-seg');
  chip.textContent = segMode;
  chip.className = 'seg seg-' + segMode;
  const btn = document.querySelector('#keypad .kp-toggle');
  btn.textContent = segMode;
  btn.classList.toggle('kp-on', segMode !== 'S');
}

async function postDart(points, isDouble) {
  const st = await api('/api/dart', { points, double: isDouble });
  if (st) {
    kpValue = '';
    segMode = 'S'; // reset segment after every recorded throw
    renderKeypad();
    rev = st.rev;
    render(st, false);
  }
}

$('#keypad .kp-grid').addEventListener('click', (e) => {
  const btn = e.target.closest('button');
  if (!btn) return;
  const k = btn.dataset.kp;
  if (k >= '0' && k <= '9') {
    if ((kpValue + k).length <= 2) kpValue += k;
  } else if (k === 'seg') {
    cycleSeg();
  } else if (k === 'back') {
    kpValue = kpValue.slice(0, -1);
  } else if (k === 'clear') {
    kpValue = '';
  } else if (k === 'miss') {
    postDart(0, false);
    return;
  } else if (k === 'enter') {
    if (kpValue === '') {
      postDart(0, false); // Enter on empty display = miss
      return;
    }
    const t = buildThrow();
    if (t.error) {
      toast(t.error, 'bust');
      return;
    }
    postDart(t.points, t.double);
    return;
  }
  renderKeypad();
});

$('#undo-btn').addEventListener('click', async () => {
  const st = await api('/api/undo', {});
  if (st) {
    rev = st.rev;
    render(st, true); // suppress toast right after an undo
  }
});

// physical keyboard support (desktop testing)
window.addEventListener('keydown', (e) => {
  if (screens.game.hidden) return;
  if (e.key >= '0' && e.key <= '9') {
    if ((kpValue + e.key).length <= 2) kpValue += e.key;
    renderKeypad();
  } else if (e.key === 'Enter') {
    const btn = document.querySelector('[data-kp="enter"]');
    btn.click();
  } else if (e.key === 'Backspace') {
    kpValue = kpValue.slice(0, -1);
    renderKeypad();
  } else if (['s', 'd', 't'].includes(e.key.toLowerCase())) {
    segMode = e.key.toUpperCase();
    renderKeypad();
  } else if (e.key.toLowerCase() === 'u') {
    $('#undo-btn').click();
  }
});

// ---------- polling ----------
setInterval(() => refresh(false), 1000);

// On load: if a match is running on the server, jump straight into it.
(async () => {
  const st = await api('/api/state');
  if (st && st.hasGame && !st.matchOver) {
    show('game');
    renderKeypad();
    render(st, true);
  } else if (st && st.hasGame && st.matchOver) {
    render(st, true);
  }
})();
