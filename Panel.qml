import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Dual monitor wallpaper: a bar icon with a panel to pick the wallpaper
// folder and to choose which monitor is the left one and which is the right
// one. All state lives in Service.qml, which the shell loads once; this
// widget exists once per monitor and only reads from and calls into that
// service, so the copies never disagree.
//
// Left-click opens the panel. NOTE: after editing this file run
// `omarchy restart shell` — the hot reload re-instantiates but keeps the old
// compiled QML.
Panel {
  id: root
  moduleName: "dual_monitor_wallpaper"
  ipcTarget: "dualwallpaper"

  readonly property var svc: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("dual_monitor_wallpaper") : null
  readonly property bool ready: svc !== null && svc !== undefined

  readonly property string wallpaperDir: ready ? svc.wallpaperDir : Model.defaultWallpaperDir()
  readonly property string leftMonitor: ready ? svc.leftMonitor : ""
  readonly property string rightMonitor: ready ? svc.rightMonitor : ""
  readonly property string leftWallpaper: ready ? svc.leftWallpaper : ""
  readonly property string rightWallpaper: ready ? svc.rightWallpaper : ""
  readonly property int pairIndex: ready ? svc.pairIndex : 0
  readonly property int pairCount: ready ? svc.pairList().length : 0

  // The list of screens the service sees, as plain rows for the dropdowns.
  // Refreshed whenever the panel opens so a hot-plugged monitor shows up.
  property var screenRows: []

  readonly property var monitorOptions: {
    var list = []
    for (var i = 0; i < root.screenRows.length; i++) {
      var s = root.screenRows[i]
      var label = s.name
      if (s.side === "left") label += "  (left)"
      else if (s.side === "right") label += "  (right)"
      list.push({ value: s.name, label: label })
    }
    return list
  }

  function refreshScreens() {
    if (ready) root.screenRows = Model.parseScreens(svc.screensJson())
    else root.screenRows = []
  }

  function setWallpaperDir(value) { if (ready) svc.setWallpaperDir(value) }
  function setLeftMonitor(value) { if (ready) svc.setLeftMonitor(value) }
  function setRightMonitor(value) { if (ready) svc.setRightMonitor(value) }
  function nextPair() { if (ready) svc.nextPair() }
  function prevPair() { if (ready) svc.prevPair() }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      root.refreshScreens()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.ready && (root.leftWallpaper !== "" || root.rightWallpaper !== "") ? "󰍺" : "󰍹"
    active: root.ready && root.leftWallpaper !== "" && root.rightWallpaper !== ""
    tooltipText: !root.ready
      ? "Dual monitor wallpaper: service not running"
      : ("Dual monitor wallpaper · pair " + (root.pairIndex + 1) + "/" + root.pairCount
         + " · left: " + (root.leftWallpaper ? Model.basename(root.leftWallpaper) : "—")
         + " · right: " + (root.rightWallpaper ? Model.basename(root.rightWallpaper) : "—")
         + " · right-click: next wallpaper")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.nextPair()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Dual monitor wallpaper"
          meta: root.ready
            ? (root.leftWallpaper !== "" && root.rightWallpaper !== ""
               ? "Two wallpapers applied · stock background disabled"
               : "Pick a folder and the two monitors")
            : "Service not running"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.ready ? 1.0 : 0.6
          iconComponent: Component {
            Text {
              text: "󰍺"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "WALLPAPER FOLDER"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: "Images for the left monitor end in _L, for the right one in _R — e.g. forest_L.png and forest_R.png."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          TextField {
            id: dirField
            width: parent.width
            text: root.wallpaperDir
            placeholderText: Model.defaultWallpaperDir()
            foreground: root.foreground
            accent: root.accent
            hasCursor: false
            onAccepted: root.setWallpaperDir(dirField.text)
            onEditingFinished: root.setWallpaperDir(dirField.text)
          }
        }

        PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "MONITORS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: "Choose which physical monitor is the left one and which is the right one. With no selection the leftmost screen is treated as the left."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Dropdown {
            id: leftDropdown
            width: parent.width
            label: "Left monitor"
            value: root.leftMonitor
            options: root.monitorOptions
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            hasCursor: false
            onChanged: function(v) { root.setLeftMonitor(v) }
          }

          Dropdown {
            id: rightDropdown
            width: parent.width
            label: "Right monitor"
            value: root.rightMonitor
            options: root.monitorOptions
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            hasCursor: false
            onChanged: function(v) { root.setRightMonitor(v) }
          }
        }

        PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "CURRENT PAIR"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            PanelActionButton {
              iconText: "◀"
              tooltipText: "Previous wallpaper"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.pairCount > 0
              onClicked: root.prevPair()
            }

            PanelActionButton {
              iconText: "▶"
              tooltipText: "Next wallpaper"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.pairCount > 0
              onClicked: root.nextPair()
            }

            Text {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              text: root.pairCount > 0
                ? ("Pair " + (root.pairIndex + 1) + " of " + root.pairCount)
                : "No wallpapers in folder"
              color: root.pairCount > 0 ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Style.space(6)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)
            Text {
              Layout.preferredWidth: Style.space(64)
              text: "LEFT"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              Layout.fillWidth: true
              text: root.leftWallpaper !== "" ? Model.basename(root.leftWallpaper) : "—"
              color: root.leftWallpaper !== "" ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)
            Text {
              Layout.preferredWidth: Style.space(64)
              text: "RIGHT"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              Layout.fillWidth: true
              text: root.rightWallpaper !== "" ? Model.basename(root.rightWallpaper) : "—"
              color: root.rightWallpaper !== "" ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
        }

        Text {
          width: parent.width
          text: "Note: this plugin renders on the background layer, so the stock omarchy.background plugin must stay disabled."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
