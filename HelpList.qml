import QtQuick
import qs.Commons
import "CalcModel.js" as CalcModel

// Scrollable help reference, extracted from the overlay so the same list can be
// placed above or below the input. Purely presentational: the owner supplies
// the sections, line height and theme; scrolling is capped by the owner's
// height.
Flickable {
  id: root

  property var sections: []
  property int lineHeight: 0
  property color foreground: "white"
  property color accent: "white"
  property string fontFamily: ""

  contentWidth: width
  contentHeight: column.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: column
    width: parent.width
    spacing: 0

    Repeater {
      model: root.sections

      Column {
        required property var modelData
        width: column.width
        spacing: 0

        Text {
          width: parent.width
          height: root.lineHeight
          text: modelData.title
          textFormat: Text.PlainText
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.DemiBold
          verticalAlignment: Text.AlignVCenter
        }

        Repeater {
          model: modelData.rows

          Item {
            required property var modelData
            width: parent.width
            height: root.lineHeight

            Text {
              id: syntaxText
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.syntax
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.left: syntaxText.right
              anchors.leftMargin: Style.spacing.lg
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.note
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.55
              horizontalAlignment: Text.AlignRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
