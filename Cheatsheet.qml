import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "CheatsheetModel.js" as Model

// Hold-SUPER keybinding cheat sheet.
//
// The Hyprland half lives in hypr/cheatsheet.lua: the press bind on SUPER_L
// raises cheatsheet:hold, then polls hl.is_key_down inside the compositor and
// raises cheatsheet:unhold the moment SUPER physically comes up. That is the
// primary dismissal and it holds for every chord. `hyprlandActivity` below
// additionally closes the sheet as soon as a chord visibly lands, and
// `maxTimer` is a last resort if the compositor side ever stops reporting.
Item {
  id: root

  property bool opened: false
  property var sections: []
  property bool loaded: false

  // Long enough that SUPER+W and friends never flash the sheet, short enough
  // that a deliberate hold feels immediate.
  readonly property int revealDelay: 200

  // Last resort, for when the compositor-side key poll stops reporting (a
  // shell restart mid-hold, say). It matches that poll's own bound in
  // hypr/cheatsheet.lua, and is deliberately far longer than a plausible
  // hold: the cap firing while SUPER is still down is a bug the user sees.
  readonly property int maxVisibleMs: 20000

  readonly property int pad: Style.space(20)
  readonly property int columnGap: Style.space(22)
  readonly property int rowGap: Style.space(7)
  readonly property int chipsWidth: Style.space(62)

  // Hyprland names the focused output; Quickshell wants the matching screen.
  readonly property var focusedScreen: {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    if (name === "") return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === name) return screens[i]
    return null
  }

  function reveal() {
    if (!root.loaded && !bindsProc.running) bindsProc.running = true
    // Baseline the focus comparison at press time, not when the timer fires. A
    // chord landing inside revealDelay updates focusedAddress first, so a
    // baseline taken later would be the window the chord just moved us to and
    // every subsequent event would look like "no change".
    root.addressAtReveal = root.focusedAddress
    revealTimer.restart()
  }

  function dismiss() {
    revealTimer.stop()
    maxTimer.stop()
    root.opened = false
  }

  function reload() {
    root.loaded = false
    if (!bindsProc.running) bindsProc.running = true
  }

  // Shell summon/hide contract.
  function open(payloadJson) { root.reveal() }
  function close() { root.dismiss() }

  Component.onCompleted: bindsProc.running = true

  Timer {
    id: revealTimer
    interval: root.revealDelay
    onTriggered: {
      root.opened = true
      maxTimer.restart()
    }
  }

  Timer {
    id: maxTimer
    interval: root.maxVisibleMs
    onTriggered: root.dismiss()
  }

  Process {
    id: bindsProc
    command: ["hyprctl", "-j", "binds"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.sections = Model.build(text)
        root.loaded = true
      }
    }
  }

  // A chord that landed means the hold is over, even though Hyprland suppresses
  // the release bind once a combo has fired. Only real actions count: Hyprland
  // re-emits activewindow/windowtitle on every title change, and an animated
  // terminal title alone fires those a couple of times a second.
  property string focusedAddress: ""
  property string addressAtReveal: ""

  readonly property var actionEvents: ({
    "openwindow": true, "closewindow": true, "movewindow": true, "movewindowv2": true,
    "workspace": true, "workspacev2": true, "createworkspace": true, "createworkspacev2": true,
    "focusedmon": true, "focusedmonv2": true, "changefloatingmode": true, "fullscreen": true,
    "activespecial": true, "activespecialv2": true, "togglegroup": true,
    "moveintogroup": true, "moveoutofgroup": true, "pin": true, "submap": true
  })

  Connections {
    id: hyprlandActivity
    target: Hyprland
    ignoreUnknownSignals: true
    function onRawEvent(event) {
      var name = String(event.name || "")

      // A hold counts as live from the moment SUPER goes down, not from when
      // the sheet becomes visible. Typing SUPER+RETURN quickly fires the chord
      // inside revealDelay, and gating on `opened` here would throw that
      // activity away and then show the sheet into the silence that follows.
      var live = root.opened || revealTimer.running

      // Track focus by address rather than by the event firing at all, so a
      // title change does not read as a focus move.
      if (name === "activewindowv2") {
        root.focusedAddress = String(event.data || "")
        // An empty baseline means no focus event has been seen yet this
        // session, not that focus moved — dismissing on it would kill the
        // first hold after every shell start.
        if (live && root.addressAtReveal !== "" && root.focusedAddress !== root.addressAtReveal) root.dismiss()
        return
      }

      // Rebinding something while the shell is up should update the sheet.
      if (name === "configreloaded") {
        root.reload()
        return
      }

      if (live && root.actionEvents[name] === true) root.dismiss()
    }
  }

  // Delivered over hyprland-global-shortcuts rather than by spawning a process
  // per keypress: every chord starts with SUPER, so an exec bind here would run
  // two processes on every shortcut the user types.
  //
  // Two shortcuts rather than one because Hyprland's `global` dispatcher
  // delivers one edge per bind: a press bind raises `pressed` and never
  // `released`. So dismissal is its own shortcut, raised by the compositor-side
  // key poll in hypr/cheatsheet.lua. Both edges are handled on both shortcuts,
  // since dismissing twice is harmless and the edge a programmatic dispatch
  // raises is version-dependent.
  GlobalShortcut {
    appid: "cheatsheet"
    name: "hold"
    description: "Hold SUPER to reveal the keybinding cheat sheet"
    onPressed: root.reveal()
    onReleased: root.dismiss()
  }

  GlobalShortcut {
    appid: "cheatsheet"
    name: "unhold"
    description: "Dismiss the keybinding cheat sheet when SUPER is released"
    onPressed: root.dismiss()
    onReleased: root.dismiss()
  }

  IpcHandler {
    target: "cheatsheet"
    function show(): string { root.reveal(); return "ok" }
    function hide(): string { root.dismiss(); return "ok" }
    function toggle(): string { root.opened ? root.dismiss() : root.reveal(); return "ok" }
    function refresh(): string { root.reload(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    id: panel
    visible: root.opened && root.sections.length > 0
    screen: root.focusedScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cheatsheet"
    WlrLayershell.layer: WlrLayer.Overlay
    // The whole point: it must never take the keyboard, or it would eat the
    // very chord it is advertising.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Empty input region, so clicks fall through to the windows underneath.
    mask: Region {}

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: layout.implicitWidth + root.pad * 2
      height: layout.implicitHeight + root.pad * 2
      color: Util.alpha(Color.popups.background, 0.97)
      border.color: Color.popups.border
      border.width: Math.max(1, Style.space(2))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
      }

      Column {
        id: layout
        anchors.centerIn: parent
        spacing: Style.space(14)

        Row {
          spacing: Style.space(10)

          Text {
            text: "SUPER"
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            color: Color.accent
          }

          Text {
            text: "held — ⇧ is shift"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Util.alpha(Color.popups.text, 0.5)
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          spacing: root.columnGap

          Repeater {
            model: root.sections

            Column {
              required property var modelData
              spacing: root.rowGap

              Text {
                text: modelData.title
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Util.alpha(Color.popups.text, 0.45)
                bottomPadding: Style.space(3)
              }

              Repeater {
                model: modelData.rows

                Row {
                  required property var modelData
                  spacing: Style.space(10)

                  Row {
                    width: root.chipsWidth
                    spacing: Style.space(4)
                    layoutDirection: Qt.RightToLeft

                    Repeater {
                      model: {
                        // Drawn right to left, so reverse for reading order.
                        var chips = modelData.chips.slice()
                        chips.reverse()
                        return chips
                      }

                      Rectangle {
                        required property var modelData
                        width: chipText.implicitWidth + Style.space(11)
                        height: chipText.implicitHeight + Style.space(5)
                        radius: Math.max(2, Style.space(3))
                        color: Util.alpha(Color.accent, 0.14)
                        border.color: Util.alpha(Color.accent, 0.35)
                        border.width: 1

                        Text {
                          id: chipText
                          anchors.centerIn: parent
                          text: modelData
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          color: Color.accent
                        }
                      }
                    }
                  }

                  Text {
                    text: modelData.label
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: Color.popups.text
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
