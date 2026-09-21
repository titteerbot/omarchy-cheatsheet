// Curation + parsing for the hold-SUPER cheat sheet.
//
// Rows are resolved against live `hyprctl binds` output rather than hardcoded,
// so rebinding a key updates the sheet and unbinding one drops its row. SUPER
// is implied by the whole interaction, so it is never drawn on a chip.

var MOD_SHIFT = 1;
var MOD_CTRL = 4;
var MOD_ALT = 8;
var MOD_SUPER = 64;

var KEY_LABELS = {
  "RETURN": "Enter",
  "SPACE": "Space",
  "ESCAPE": "Esc",
  "BACKSPACE": "⌫",
  "TAB": "Tab",
  "LEFT": "←",
  "RIGHT": "→",
  "UP": "↑",
  "DOWN": "↓",
  "PRINT": "Print",
  "SLASH": "/",
  "PERIOD": ".",
  "comma": ",",
  "Delete": "Del",
  "Home": "Home"
};

// Each row is either a live lookup (`desc`) or a hand-drawn summary (`keys`)
// that collapses a family of bindings into one line. A summary row still names
// a `requires` description so it disappears if that family is unbound.
var SECTIONS = [
  {
    title: "Window",
    rows: [
      { desc: "Close window" },
      { desc: "Toggle window floating/tiling", label: "Float / tile" },
      { desc: "Full screen" },
      { desc: "Full width" },
      { desc: "Tiled full screen" },
      { desc: "Pop window out (float & pin)", label: "Pop out & pin" },
      { desc: "Toggle window split", label: "Toggle split" },
      { desc: "Toggle window grouping", label: "Group windows" }
    ]
  },
  {
    title: "Move & resize",
    rows: [
      { keys: ["←", "→", "↑", "↓"], label: "Focus window", requires: "Focus on left window" },
      { keys: ["⇧", "←→↑↓"], label: "Swap window", requires: "Swap window to the left" },
      { keys: ["-", "="], label: "Resize window", requires: "Expand window left" },
      { keys: ["Drag"], label: "Move window", requires: "Move window" },
      { keys: ["R-drag"], label: "Resize window", requires: "Resize window" },
      { keys: ["1", "–", "9"], label: "Switch workspace", requires: "Switch to workspace 1" },
      { keys: ["⇧", "1–9"], label: "Send to workspace", requires: "Move window to workspace 1" },
      { desc: "Next workspace" },
      { desc: "Toggle scratchpad", label: "Scratchpad" }
    ]
  },
  {
    title: "Launch",
    rows: [
      { desc: "Terminal" },
      { desc: "Browser" },
      { desc: "File manager" },
      { desc: "Editor" },
      { desc: "Omarchy menu" },
      { desc: "Apps menu" },
      { desc: "System menu" },
      { desc: "Keybindings", label: "All keybindings" }
    ]
  },
  {
    title: "Clipboard & system",
    rows: [
      { desc: "Universal copy", label: "Copy" },
      { desc: "Universal paste", label: "Paste" },
      { desc: "Clipboard manager", label: "Clipboard history" },
      { desc: "Capture menu", label: "Screenshot / record" },
      { desc: "Color picker" },
      { desc: "Emojis" },
      { desc: "Lock system", label: "Lock" },
      { desc: "Toggle nightlight", label: "Night light" }
    ]
  }
];

function keyLabel(bind) {
  var key = String(bind.key || "");
  if (key === "") return "";
  if (key.indexOf("mouse:272") === 0) return "Drag";
  if (key.indexOf("mouse:273") === 0) return "R-drag";
  if (key.indexOf("mouse_down") === 0) return "Scroll ↓";
  if (key.indexOf("mouse_up") === 0) return "Scroll ↑";
  if (KEY_LABELS.hasOwnProperty(key)) return KEY_LABELS[key];
  if (key.length === 1) return key.toUpperCase();
  return key;
}

// SUPER is held while the sheet is up, so only the extra modifiers earn a chip.
// Ctrl and Alt are spelled out: the Mac glyphs for them (⌃ ⌥) read as stray
// punctuation on a Linux desktop. ⇧ is recognised everywhere, so it stays.
function chipsFor(bind) {
  var chips = [];
  var mask = Number(bind.modmask || 0);
  if (mask & MOD_CTRL) chips.push("Ctrl");
  if (mask & MOD_ALT) chips.push("Alt");
  if (mask & MOD_SHIFT) chips.push("⇧");
  var key = keyLabel(bind);
  if (key !== "") chips.push(key);
  return chips;
}

function indexBinds(jsonText) {
  var byDescription = {};
  var binds = [];
  try {
    binds = JSON.parse(jsonText || "[]");
  } catch (e) {
    return byDescription;
  }
  for (var i = 0; i < binds.length; i++) {
    var bind = binds[i];
    if (!bind || !bind.has_description) continue;
    if (!(Number(bind.modmask || 0) & MOD_SUPER)) continue;
    if (bind.release) continue;
    var description = String(bind.description || "");
    // First match wins: several actions share a description (two Browser
    // bindings, for one), and the earlier entry is the canonical chord.
    if (!byDescription.hasOwnProperty(description)) byDescription[description] = bind;
  }
  return byDescription;
}

// A user row is kept only if it has the shape the built-in rows have: a `desc`
// string, or a `keys` array of strings with a `label`. Anything else is
// dropped rather than drawn half-broken.
function cleanRow(row) {
  if (!row || typeof row !== "object") return null;
  var label = typeof row.label === "string" && row.label !== "" ? row.label : null;

  if (typeof row.desc === "string" && row.desc !== "") {
    return label ? { desc: row.desc, label: label } : { desc: row.desc };
  }

  if (Array.isArray(row.keys) && row.keys.length > 0 && label) {
    for (var k = 0; k < row.keys.length; k++) {
      if (typeof row.keys[k] !== "string") return null;
    }
    var out = { keys: row.keys.slice(), label: label };
    if (typeof row.requires === "string" && row.requires !== "") out.requires = row.requires;
    return out;
  }

  return null;
}

// Layers the user's `sections` from shell.json over the built-in table. A
// section whose title matches a built-in one (ignoring case) gets its rows
// appended there; any other title becomes a new section after the built-ins.
function mergeSections(base, extra) {
  var merged = [];
  var byTitle = {};

  for (var b = 0; b < base.length; b++) {
    var copy = { title: base[b].title, rows: base[b].rows.slice() };
    merged.push(copy);
    byTitle[copy.title.toLowerCase()] = copy;
  }

  if (!Array.isArray(extra)) return merged;

  for (var e = 0; e < extra.length; e++) {
    var section = extra[e];
    if (!section || typeof section.title !== "string" || section.title === "") continue;
    if (!Array.isArray(section.rows)) continue;

    var rows = [];
    for (var r = 0; r < section.rows.length; r++) {
      var row = cleanRow(section.rows[r]);
      if (row) rows.push(row);
    }
    if (rows.length === 0) continue;

    var key = section.title.toLowerCase();
    if (byTitle.hasOwnProperty(key)) {
      byTitle[key].rows = byTitle[key].rows.concat(rows);
    } else {
      var added = { title: section.title, rows: rows };
      merged.push(added);
      byTitle[key] = added;
    }
  }

  return merged;
}

// Pulls this plugin's `sections` out of shell.json's top-level `plugins`
// list. Missing file, bad JSON or no entry all mean "no user sections".
function userSectionsFrom(shellJsonText, pluginId) {
  var config;
  try {
    config = JSON.parse(shellJsonText || "{}");
  } catch (e) {
    return [];
  }
  var plugins = config && Array.isArray(config.plugins) ? config.plugins : [];
  for (var i = 0; i < plugins.length; i++) {
    var entry = plugins[i];
    if (entry && entry.id === pluginId) {
      return Array.isArray(entry.sections) ? entry.sections : [];
    }
  }
  return [];
}

function build(jsonText, userSections) {
  var byDescription = indexBinds(jsonText);
  var table = mergeSections(SECTIONS, userSections);
  var sections = [];

  for (var s = 0; s < table.length; s++) {
    var section = table[s];
    var rows = [];

    for (var r = 0; r < section.rows.length; r++) {
      var row = section.rows[r];

      if (row.keys) {
        if (row.requires && !byDescription.hasOwnProperty(row.requires)) continue;
        rows.push({ chips: row.keys, label: row.label });
        continue;
      }

      var bind = byDescription[row.desc];
      if (!bind) continue;
      var chips = chipsFor(bind);
      if (chips.length === 0) continue;
      rows.push({ chips: chips, label: row.label || row.desc });
    }

    if (rows.length > 0) sections.push({ title: section.title, rows: rows });
  }

  return sections;
}
