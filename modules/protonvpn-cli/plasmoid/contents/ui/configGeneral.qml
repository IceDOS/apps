import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_refreshSec: refreshSpin.value
    property alias cfg_showServerInPanel: showServer.checked

    QQC2.SpinBox {
        id: refreshSpin
        Kirigami.FormData.label: i18n("Refresh status every (seconds):")
        from: 5
        to: 600
        stepSize: 5
    }

    QQC2.CheckBox {
        id: showServer
        Kirigami.FormData.label: i18n("Panel:")
        text: i18n("Show connected server name")
    }
}
