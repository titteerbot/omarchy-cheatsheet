-- Hyprland side of the hold-SUPER cheat sheet (plugin: titteerbot.cheatsheet).
--
-- Load it from ~/.config/hypr/bindings.lua — see the README for the line.
--
-- Why poll instead of a release bind: Hyprland suppresses a release bind once
-- any chord has fired during the hold, and many chords (SUPER+C, SUPER+V, the
-- menus) emit no compositor event the shell could use as a substitute. So the
-- press bind asks the compositor directly, via hl.is_key_down, until SUPER
-- physically comes up. It runs inside Hyprland's own Lua runtime — nothing is
-- spawned — and only for as long as SUPER is held.

local POLL_MS = 50

-- Matches the shell's maxVisibleMs, and bounds the loop if key state ever
-- reports wrongly.
local MAX_TICKS = 400

-- xkb keysym name, and the casing is load-bearing: "Super_L" returns a
-- boolean, while "SUPER_L" and "SUPER" silently return nil.
local SUPER = "Super_L"

local polling = false

local function watch_release(tick)
  if hl.is_key_down(SUPER) and tick < MAX_TICKS then
    hl.timer(function() watch_release(tick + 1) end, { timeout = POLL_MS, type = "oneshot" })
    return
  end

  polling = false
  hl.dispatch(hl.dsp.global("cheatsheet:unhold"))
end

-- non_consuming, or SUPER stops working as a modifier for every chord the
-- sheet advertises.
o.bind("SUPER_L", "Cheat sheet (hold SUPER)", function()
  hl.dispatch(hl.dsp.global("cheatsheet:hold"))
  if polling then return end
  polling = true
  watch_release(0)
end, { non_consuming = true })
