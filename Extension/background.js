let polling = false;
let wasActive = false;
let lastActiveCallTime = Date.now();
const INACTIVITY_LIMIT_MS = 45 * 60 * 1000;
const MEETING_URL_RE = /^https:\/\/meet\.google\.com\/(meet\/)?[a-z]{3}-[a-z]{4}-[a-z]{3}/i;

function domGetState() {
  const minTop = window.innerHeight * 0.5;
  const btns = Array.from(document.querySelectorAll('button')).filter(b => {
    const r = b.getBoundingClientRect();
    return r.width > 10 && r.height > 10 && r.top >= minTop;
  });

  const findBottomBtn = (re) => btns.find(b => {
    const a = (b.getAttribute('aria-label') || '').toLowerCase();
    return re.test(a) && !/налаштув|параметр|settings|select|вибрати|меню|додатков|more/.test(a);
  });

  const m = btns.find(b => b.hasAttribute('data-is-muted') && /мікрофон|microphone/i.test(b.getAttribute('aria-label') || '')) ||
            findBottomBtn(/(вимкнути|увімкнути|включити|turn off|turn on).*?(мікрофон|microphone)/);
  const c = btns.find(b => b.hasAttribute('data-is-muted') && /камер|camera/i.test(b.getAttribute('aria-label') || '')) ||
            findBottomBtn(/(вимкнути|увімкнути|включити|turn off|turn on).*?(камер|camera)/);
  const h = findBottomBtn(/(підняти|опустити|raise|lower).*?(руку|hand)/);
  const leave = findBottomBtn(/завершити|покинути|вийти з дзвінка|leave call|end call/);

  const micOn = m ? (m.getAttribute('data-is-muted') === 'false') : false;
  const camOn = c ? (c.getAttribute('data-is-muted') === 'false') : false;
  const handUp = h ? (h.getAttribute('aria-pressed') === 'true' || /опустити|lower/i.test(h.getAttribute('aria-label') || '')) : false;

  return {
    found: !!(m || c || h),
    inCall: !!(leave && (m || c)),
    mic: micOn ? 1 : 0,
    cam: camOn ? 1 : 0,
    hand: handUp ? 1 : 0
  };
}

function domRunCommand(cmd) {
  const minTop = window.innerHeight * 0.5;
  const btns = Array.from(document.querySelectorAll('button')).filter(b => {
    const r = b.getBoundingClientRect();
    return r.width > 10 && r.height > 10 && r.top >= minTop;
  });

  const findBottomBtn = (re) => btns.find(b => {
    const a = (b.getAttribute('aria-label') || '').toLowerCase();
    return re.test(a) && !/налаштув|параметр|settings|select|вибрати|меню|додатков|more/.test(a);
  });

  if (cmd === 'mic') {
    const m = btns.find(b => b.hasAttribute('data-is-muted') && /мікрофон|microphone/i.test(b.getAttribute('aria-label') || '')) ||
              findBottomBtn(/(вимкнути|увімкнути|включити|turn off|turn on).*?(мікрофон|microphone)/);
    if (m) m.click();
  } else if (cmd === 'cam') {
    const c = btns.find(b => b.hasAttribute('data-is-muted') && /камер|camera/i.test(b.getAttribute('aria-label') || '')) ||
              findBottomBtn(/(вимкнути|увімкнути|включити|turn off|turn on).*?(камер|camera)/);
    if (c) c.click();
  } else if (cmd === 'hand') {
    const h = findBottomBtn(/(підняти|опустити|raise|lower).*?(руку|hand)/);
    if (h) h.click();
  } else if (cmd === 'closeReactions') {
    const rBtn = findBottomBtn(/реакц|reaction|емодзі|emoji/);
    if (rBtn && (rBtn.getAttribute('aria-expanded') === 'true' || rBtn.getAttribute('aria-pressed') === 'true')) {
      rBtn.click();
    }
  } else if (cmd && cmd.startsWith('emoji:')) {
    const emoji = cmd.slice(6) || '💖';
    const isHeart = (emoji === '💖' || emoji === '❤️' || emoji === '❤');
    const findEmoji = () => Array.from(document.querySelectorAll('button, [role="button"]')).find(b => {
      const t = b.innerText || '';
      const a = (b.getAttribute('aria-label') || '').toLowerCase();
      const d = b.getAttribute('data-emoji') || '';
      if (isHeart) {
        return d.includes('❤') || d.includes('💖') || t.includes('❤') || t.includes('💖') || /сердеч|сердц|heart|love/.test(a);
      }
      return d === emoji || t.includes(emoji) || a.includes(emoji);
    });
    const el = findEmoji();
    if (el) { el.click(); return; }
    const rBtn = findBottomBtn(/реакц|reaction|емодзі|emoji/);
    if (rBtn && rBtn.getAttribute('aria-expanded') !== 'true') rBtn.click();
    setTimeout(() => {
      const el2 = findEmoji();
      if (el2) el2.click();
    }, 180);
  }
}

async function pollOnce() {
  try {
    const allTabs = await chrome.tabs.query({ url: "https://meet.google.com/*" });
    const tabs = (allTabs || []).filter(t => t.url && MEETING_URL_RE.test(t.url));

    // Якщо відкритого сайту або дзвінка Meet немає взагалі:
    if (tabs.length === 0) {
      if (wasActive) {
        await fetch("http://127.0.0.1:48123/poll?hasMeet=0&mic=0&cam=0&hand=0&onMeet=1").catch(() => {});
        wasActive = false;
      }
      return { hasMeet: false, acted: false, noTabs: true };
    }

    let targetTab = null;
    let fallbackTab = null;
    let st = { found: false, inCall: false, mic: 0, cam: 0, hand: 0 };

    for (const tab of tabs) {
      try {
        const results = await chrome.scripting.executeScript({
          target: { tabId: tab.id, allFrames: true },
          func: domGetState
        });
        if (results) {
          const inCallHit = results.map(r => r.result).find(r => r && r.inCall);
          const anyHit = results.map(r => r.result).find(r => r && r.found);
          if (inCallHit) {
            targetTab = tab;
            st = inCallHit;
            lastActiveCallTime = Date.now();
            break;
          } else if (anyHit && !fallbackTab) {
            fallbackTab = tab;
            st = anyHit;
            lastActiveCallTime = Date.now();
          }
        }
      } catch (_) {}
    }

    if (!targetTab) {
      targetTab = fallbackTab || tabs.find(t => t.active) || tabs[0];
    }

    if (!st.found && (Date.now() - lastActiveCallTime > INACTIVITY_LIMIT_MS)) {
      if (wasActive) {
        await fetch("http://127.0.0.1:48123/poll?hasMeet=0&mic=0&cam=0&hand=0&onMeet=1").catch(() => {});
        wasActive = false;
      }
      return { hasMeet: false, acted: false, noTabs: true };
    }

    const win = await chrome.windows.get(targetTab.windowId).catch(() => null);
    const onMeet = (targetTab.active && win && win.focused) ? 1 : 0;

    const resp = await fetch(`http://127.0.0.1:48123/poll?hasMeet=1&mic=${st.mic}&cam=${st.cam}&hand=${st.hand}&onMeet=${onMeet}`);
    const data = await resp.json();
    wasActive = true;

    if (data && data.cmd) {
      if (data.cmd === 'focusMeet') {
        await chrome.windows.update(targetTab.windowId, { focused: true }).catch(() => {});
        await chrome.tabs.update(targetTab.id, { active: true }).catch(() => {});
      } else {
        await chrome.scripting.executeScript({
          target: { tabId: targetTab.id, allFrames: true },
          func: domRunCommand,
          args: [data.cmd]
        }).catch(() => {});
      }
      return { hasMeet: true, acted: true, noTabs: false };
    }
    return { hasMeet: true, acted: false, noTabs: false };
  } catch (_) {
    return { hasMeet: false, acted: false, noTabs: true };
  }
}

async function loop() {
  if (polling) return;
  polling = true;
  try {
    while (true) {
      const res = await pollOnce();
      if (res.noTabs) {
        // Коли немає відкритого сайту чи додатку Meet — цикл зупиняється!
        // Жодного фонового споживання ресурсів, браузер і система сплять.
        break;
      }
      if (res.acted) {
        await new Promise(r => setTimeout(r, 60));
      } else {
        await new Promise(r => setTimeout(r, 600));
      }
    }
  } finally {
    polling = false;
  }
}

function triggerLoop() {
  if (!polling) {
    loop();
  }
}

// Запуск опитування виключно тоді, коли з'являється чи змінюється вкладка Meet
chrome.runtime.onStartup.addListener(triggerLoop);
chrome.runtime.onInstalled.addListener(triggerLoop);
chrome.tabs.onUpdated.addListener((tabId, info, tab) => {
  if ((info.url && MEETING_URL_RE.test(info.url)) || (tab.url && MEETING_URL_RE.test(tab.url))) {
    lastActiveCallTime = Date.now();
    triggerLoop();
  }
});
chrome.tabs.onCreated.addListener((tab) => {
  if (tab.url && MEETING_URL_RE.test(tab.url)) {
    triggerLoop();
  }
});
chrome.tabs.onRemoved.addListener(() => triggerLoop());
triggerLoop();
