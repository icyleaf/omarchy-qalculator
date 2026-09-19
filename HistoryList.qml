import QtQuick
import qs.Commons
import "CalcModel.js" as CalcModel

// Scrollable history rows, extracted from the overlay so the same list can be
// placed above or below the input. Purely presentational: the owner supplies
// the entries, the highlighted index and the theme, and reacts to
// resultClicked(). Scrolling is capped by the owner's height; clip and
// StopAtBounds make overflow scroll and stop at both ends.
ListView {
  id: root

  property var entries: []
  property int highlightedIndex: -1
  property int rowHeight: 0
  property int shortcutSlotWidth: 0
  property int cornerRadius: 0
  property color foreground: "white"
  property color selectedText: "white"
  property color selectedBackground: "transparent"
  property string fontFamily: ""

  signal resultClicked(string value)

  clip: true
  model: root.entries
  spacing: Style.spacing.xs
  currentIndex: root.highlightedIndex
  boundsBehavior: Flickable.StopAtBounds

  // Keyboard browsing must keep the selected row on screen when the history is
  // longer than the visible area.
  onCurrentIndexChanged: {
    if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
  }

  delegate: Rectangle {
    required property int index
    required property var modelData
    width: ListView.view.width
    height: root.rowHeight
    radius: root.cornerRadius
    color: index === root.highlightedIndex ? root.selectedBackground : "transparent"

    readonly property bool hasShortcut: index < 10

    Rectangle {
      id: shortcutBadge
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      width: root.shortcutSlotWidth
      height: shortcutLabel.implicitHeight + Style.spacing.xxs * 2
      radius: Style.space(3)
      color: root.selectedBackground
      visible: parent.hasShortcut

      Text {
        id: shortcutLabel
        anchors.centerIn: parent
        text: CalcModel.historyShortcutLabel(index)
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.65
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Bold
      }
    }

    Text {
      anchors.left: parent.left
      // Fixed slot for every row, badge or not, so expressions line up.
      anchors.leftMargin: Style.spacing.sm + root.shortcutSlotWidth + Style.spacing.sm
      anchors.right: resultLabel.left
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: modelData.expression
      textFormat: Text.PlainText
      color: index === root.highlightedIndex ? root.selectedText : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      id: resultLabel
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(parent.width * 0.5, implicitWidth)
      text: modelData.result
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.85
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.resultClicked(modelData.result)
    }
  }
}
