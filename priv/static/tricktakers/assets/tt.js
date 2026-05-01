// Tricktakers — shared helpers (vanilla JS)
// Used across mock screens. Keep it dumb so it ports easily to Phoenix EEx components.

window.TT = (function () {
  const SUIT_GLYPH = { red: "❤", blue: "◆", green: "♣", black: "★" };

  function pcard({ suit, value, kind, size }) {
    // kind: "number" | "rare" | "white-flag" | "back" | "berserker"
    const cls = ["pcard"];
    if (size) cls.push("size-" + size);
    if (kind === "rare") cls.push("rare");
    else if (kind === "white-flag") cls.push("white-flag");
    else if (kind === "back") cls.push("back");
    else if (kind === "berserker") cls.push("rare");
    else cls.push(suit);

    let inner = "";
    if (kind === "back") {
      inner = "";
    } else if (kind === "rare") {
      inner = `
        <div class="corner"><div class="num">R</div></div>
        <div class="center">★</div>
        <div class="corner tr"><div class="num">R</div></div>
      `;
    } else if (kind === "white-flag") {
      inner = `
        <div class="corner"><div class="num">⚑</div></div>
        <div class="center">⚑</div>
        <div class="corner tr"><div class="num">⚑</div></div>
      `;
    } else if (kind === "berserker") {
      inner = `
        <div class="corner"><div class="num">B</div></div>
        <div class="center">⚔</div>
        <div class="corner tr"><div class="num">B</div></div>
      `;
    } else {
      inner = `
        <div class="corner"><div class="num">${value}</div><div class="pip"></div></div>
        <div class="center">${value}</div>
        <div class="corner tr"><div class="num">${value}</div><div class="pip"></div></div>
      `;
    }
    return `<div class="${cls.join(" ")}">${inner}</div>`;
  }

  // 8 characters with priority + ability + win condition (per rulebook)
  const CHARACTERS = [
    {
      id: "king",
      name: "King",
      priority: "1A",
      tag: "Trick winner",
      ability: "Earn 80 pts per trick won. Holds an exclusive Rare card to swap into hand.",
      win: "Win 2 tricks in a single round",
      points: "+80 / trick",
    },
    {
      id: "gambler",
      name: "Gambler",
      priority: "2A",
      tag: "Bid + bet",
      ability: "Bid trick count with the die; bet up to 50 pts on your call. Hit it, double up. Miss, lose all.",
      win: "Win all 5 tricks",
      points: "Bid × stake",
    },
    {
      id: "resistance",
      name: "Resistance",
      priority: "3A",
      tag: "Kakumei",
      ability: "Declare Kakumei once per round to invert card strength. Score by reversing the table.",
      win: "Win a Kakumei trick with a Black card",
      points: "+30~100 / trick",
    },
    {
      id: "hermit",
      name: "Hermit",
      priority: "4A",
      tag: "Dexterous hand",
      ability: "Draw, then discard, before each trick. White Flag defeats Rare in your hand.",
      win: "—",
      points: "+30 / Rare beaten",
    },
    {
      id: "berserker",
      name: "Berserker",
      priority: "5A",
      tag: "Fierce uplift",
      ability: "Swap your hand for the Berserker deck. Berserker card beats everything — except any 1.",
      win: "Win 0 tricks in the final round",
      points: "Crown-focused",
    },
    {
      id: "adventurer",
      name: "Adventurer",
      priority: "3B",
      tag: "Items",
      ability: "Equip and trigger items. Each won trick spawns a new equipment slot.",
      win: "—",
      points: "Up to +60 / item",
    },
    {
      id: "collector",
      name: "Collector",
      priority: "4B",
      tag: "Set collection",
      ability: "Reserve cards from any trick. Score poker-style combinations from your collection.",
      win: "Form a Straight Flush 9",
      points: "10–∞ / set",
    },
    {
      id: "ruler",
      name: "Ruler",
      priority: "5B",
      tag: "Tasks",
      ability: "Assign tasks to other players. Earn the same points they do — cooperatively.",
      win: "Have everyone complete their tasks",
      points: "Mirror others",
    },
  ];

  function charById(id) { return CHARACTERS.find(c => c.id === id); }

  function charCard(c, opts = {}) {
    const cls = ["char-card"];
    if (opts.selected) cls.push("selected");
    if (opts.taken) cls.push("taken");
    if (opts.compact) cls.push("compact");
    return `
      <div class="${cls.join(" ")}" data-id="${c.id}">
        <div class="head">
          <div>
            <div class="priority">${c.priority} · ${c.tag}</div>
            <div class="name">${c.name}</div>
          </div>
          <span class="pill">${c.points}</span>
        </div>
        <div class="body-area">
          <div class="ability">${c.ability}</div>
          <div class="win-cond"><strong>Win:</strong> ${c.win}</div>
        </div>
      </div>
    `;
  }

  function appBar(active) {
    const items = [
      ["index.html", "Overview"],
      ["landing.html", "Landing"],
      ["lobby.html", "Lobby"],
      ["setup.html", "Setup"],
      ["table.html", "Table"],
      ["resolve.html", "Trick"],
      ["round.html", "Round"],
      ["characters.html", "Characters"],
      ["profile.html", "Profile"],
    ];
    return `
      <div class="app-bar">
        <a href="index.html" class="brand">
          <span class="glyph">T</span>
          <span>Tricktakers</span>
        </a>
        <nav>
          ${items.map(([href, label]) => {
            const cur = active === label.toLowerCase() ? ' aria-current="page"' : "";
            return `<a href="${href}"${cur}>${label}</a>`;
          }).join("")}
        </nav>
        <div class="you">
          <span>You're playing as <strong>Hiroken</strong></span>
          <span class="avatar a4">H</span>
        </div>
      </div>
    `;
  }

  // Hand fan: spreads cards left-to-right with slight rotation
  function renderHand(container, cards) {
    container.innerHTML = "";
    const N = cards.length;
    const spread = Math.min(380, N * 70); // total px width
    const step = N > 1 ? spread / (N - 1) : 0;
    cards.forEach((c, i) => {
      const wrap = document.createElement("div");
      wrap.innerHTML = pcard(c);
      const el = wrap.firstElementChild;
      const t = N > 1 ? (i / (N - 1)) - 0.5 : 0;
      const x = t * spread;
      const rot = t * 8; // degrees
      const y = Math.abs(t) * 6;
      el.style.transform = `translateX(${x}px) translateY(${y}px) rotate(${rot}deg)`;
      el.style.left = "50%";
      el.style.marginLeft = `-${48}px`; // half card width
      if (c.playable !== false) el.classList.add("playable");
      if (c.disabled) el.classList.add("disabled");
      el.dataset.idx = i;
      container.appendChild(el);
    });

    // hover lift handled in CSS, but enrich with selection
    container.addEventListener("click", (e) => {
      const card = e.target.closest(".pcard");
      if (!card || card.classList.contains("disabled")) return;
      container.querySelectorAll(".pcard").forEach(p => p.classList.remove("selected"));
      card.classList.add("selected");
    });
  }

  return { pcard, CHARACTERS, charById, charCard, appBar, renderHand, SUIT_GLYPH };
})();
