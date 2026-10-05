import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // Both tokens are replaced at build time (icedos.nix): absolute CLI path, JSON list of codes.
    readonly property string pvpn: "@protonvpn@"
    readonly property var favorites: @favorites@

    // ---- state ----
    property bool haveStatus: false
    property bool connected: false
    property string server: ""
    property string load: ""
    property string protocol: ""
    property bool statusRunning: false

    property bool busy: false
    property string busyText: ""
    property string lastOutput: ""
    property bool lastOk: true

    property var countries: []        // [{name, code}] from `countries list`
    property bool countriesLoading: false
    property var cities: ({})         // code -> [{name, features}] from `cities list CODE`
    property string openCountry: ""
    property string filterText: ""

    property bool optP2p: false
    property bool optSecureCore: false
    property bool optTor: false
    property bool optRandom: false

    // The system tray forces square icons, so there is no room for the server label.
    readonly property bool inTray: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentForcesSquarePlasmoids) !== 0

    // ---- command runner ----
    property var pending: ({})
    property int seq: 0

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            var cb = root.pending[sourceName];
            delete root.pending[sourceName];
            if (cb)
                cb(data["exit code"], data["stdout"] || "", data["stderr"] || "");
        }
    }

    // The engine runs a shell command; the trailing comment keeps each source name unique.
    function run(cmd, cb) {
        root.seq += 1;
        var src = cmd + " #" + root.seq;
        root.pending[src] = cb;
        executable.connectSource(src);
    }

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // Rows under the "-----  ----" ruler of the CLI's tabulate output, split on 2+ spaces.
    function parseTable(text) {
        var rows = [], started = false;
        text.split("\n").forEach(function (line) {
            if (/^-+(\s+-+)*\s*$/.test(line)) { started = true; return; }
            if (started && line.trim())
                rows.push(line.trim().split(/\s{2,}/));
        });
        return rows;
    }

    // Keyring/logging tracebacks go to stderr ahead of the real message; keep only the CLI's own lines.
    function cleanOutput(text) {
        var err = text.split("\n").filter(function (l) { return /^Error:/.test(l); });
        if (err.length) return err.join("\n");
        return text.split("\n").filter(function (l) {
            return l.trim() && !/^(\s|Traceback|---|[\w.]+(Error|Exception)\b|The above|During handling|Call stack|Message:|Arguments:)/.test(l);
        }).join("\n").trim();
    }

    function refreshStatus() {
        if (root.statusRunning) return;
        root.statusRunning = true;
        run(root.pvpn + " status 2>&1", function (code, out) {
            root.statusRunning = false;
            var f = {};
            out.split("\n").forEach(function (line) {
                var m = line.match(/^(Status|Server|Load|Protocol):\s*(.*)$/);
                if (m) f[m[1]] = m[2].trim();
            });
            if (!f.Status) {
                root.haveStatus = false;
                root.lastOutput = root.cleanOutput(out) || ("status exited " + code);
                root.lastOk = false;
                return;
            }
            root.haveStatus = true;
            root.connected = f.Status === "Connected";
            root.server = f.Server || "";
            root.load = f.Load || "";
            root.protocol = f.Protocol || "";
        });
    }

    function loadCountries() {
        if (root.countriesLoading) return;
        root.countriesLoading = true;
        run(root.pvpn + " countries list", function (code, out, err) {
            root.countriesLoading = false;
            if (code !== 0) {
                root.lastOutput = root.cleanOutput(err + "\n" + out);
                root.lastOk = false;
                return;
            }
            root.countries = parseTable(out)
                .filter(function (r) { return r.length >= 2; })
                .map(function (r) { return { name: r[0], code: r[1] }; });
        });
    }

    function toggleCountry(code) {
        if (root.openCountry === code) { root.openCountry = ""; return; }
        root.openCountry = code;
        if (root.cities[code]) return;
        run(root.pvpn + " cities list " + quote(code), function (exit, out, err) {
            var c = Object.assign({}, root.cities);
            c[code] = exit === 0
                ? parseTable(out).map(function (r) { return { name: r[0], features: r[1] || "" }; })
                : [];
            root.cities = c;
            if (exit !== 0) {
                root.lastOutput = root.cleanOutput(err + "\n" + out);
                root.lastOk = false;
            }
        });
    }

    function countryName(code) {
        for (var i = 0; i < root.countries.length; i++)
            if (root.countries[i].code === code) return root.countries[i].name;
        return code;
    }

    function filteredCountries() {
        var q = root.filterText.trim().toLowerCase();
        if (!q) return root.countries;
        return root.countries.filter(function (c) {
            return c.name.toLowerCase().indexOf(q) !== -1 || c.code.toLowerCase() === q;
        });
    }

    // Runs a connect/disconnect, shows its output, then re-reads status.
    function act(label, cmd) {
        if (root.busy) return;
        root.busy = true;
        root.busyText = label;
        run(cmd + " 2>&1", function (code, out) {
            root.busy = false;
            root.lastOutput = root.cleanOutput(out) || (code === 0 ? "Done." : "exit " + code);
            root.lastOk = code === 0;
            root.refreshStatus();
        });
    }

    // args: extra connect arguments, already quoted; feature ticks are appended.
    function connectTo(label, args) {
        var a = [root.pvpn, "connect"].concat(args || []);
        if (root.optP2p) a.push("--p2p");
        if (root.optSecureCore) a.push("--securecore");
        if (root.optTor) a.push("--tor");
        if (root.optRandom) a.push("--random");
        act(i18n("Connecting to %1…", label), a.join(" "));
    }

    function disconnectVpn() {
        act(i18n("Disconnecting…"), root.pvpn + " disconnect");
    }

    Timer {
        interval: Math.max(5, Plasmoid.configuration.refreshSec) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }

    onExpandedChanged: {
        if (!root.expanded) return;
        root.refreshStatus();
        if (!root.countries.length) root.loadCountries();
    }

    Plasmoid.icon: "network-vpn"

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Quick Connect")
            icon.name: "network-connect"
            enabled: !root.busy
            onTriggered: root.connectTo(i18n("fastest server"), [])
        },
        PlasmaCore.Action {
            text: i18n("Disconnect")
            icon.name: "network-disconnect"
            enabled: !root.busy && root.connected
            onTriggered: root.disconnectVpn()
        },
        PlasmaCore.Action {
            text: i18n("Refresh Status")
            icon.name: "view-refresh"
            onTriggered: root.refreshStatus()
        }
    ]

    function statusTitle() {
        if (root.busy) return root.busyText;
        if (!root.haveStatus) return i18n("Status unknown");
        return root.connected ? i18n("Connected") : i18n("Disconnected");
    }

    function statusColor() {
        if (root.busy || !root.haveStatus) return Kirigami.Theme.neutralTextColor;
        return root.connected ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
    }

    toolTipMainText: "ProtonVPN: " + statusTitle()
    toolTipSubText: {
        if (!root.connected) return root.haveStatus ? "" : root.lastOutput;
        return [root.server, i18n("Load %1", root.load), root.protocol]
            .filter(function (s) { return s; }).join("\n");
    }

    // ---- compact (panel) face ----
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true

        // Plasma closes the popup on the outside press before onClicked runs; latch the old state.
        property bool wasExpanded: false
        onPressed: compact.wasExpanded = root.expanded
        onClicked: root.expanded = !compact.wasExpanded

        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Item {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small

                Kirigami.Icon {
                    anchors.fill: parent
                    source: "network-vpn"
                    opacity: root.connected ? 1.0 : 0.45
                }
                Rectangle {
                    width: Math.round(parent.width * 0.4)
                    height: width
                    radius: width / 2
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    color: root.statusColor()
                    border.color: Kirigami.Theme.backgroundColor
                    border.width: 1
                }
            }

            PlasmaComponents.Label {
                // "IT#23 in Milan" -> "IT#23"
                text: root.server.split(" in ")[0]
                visible: !root.inTray && Plasmoid.configuration.showServerInPanel && root.connected && text !== ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }

    // ---- full (popup) face ----
    fullRepresentation: PlasmaExtras.Representation {
        id: rep

        readonly property real smallFont: Kirigami.Theme.smallFont.pointSize

        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.minimumHeight: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 34

        collapseMarginsHint: true

        // desktop placement shows this face without ever toggling `expanded`
        Component.onCompleted: if (!root.countries.length) root.loadCountries()

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "network-vpn"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    opacity: root.connected ? 1.0 : 0.45
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Kirigami.Heading {
                        level: 3
                        text: root.statusTitle()
                        color: root.statusColor()
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        visible: root.connected
                        text: root.server
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        visible: root.connected
                        opacity: 0.7
                        font.pointSize: rep.smallFont
                        text: i18n("Load %1 · %2", root.load, root.protocol)
                    }
                }
                PlasmaComponents.BusyIndicator {
                    visible: root.busy || root.statusRunning
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Refresh Status")
                    onClicked: root.refreshStatus()
                    PlasmaComponents.ToolTip.text: text
                    PlasmaComponents.ToolTip.visible: hovered
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    icon.name: "network-connect"
                    text: i18n("Quick Connect")
                    enabled: !root.busy
                    onClicked: root.connectTo(i18n("fastest server"), [])
                }
                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    icon.name: "network-disconnect"
                    text: i18n("Disconnect")
                    enabled: !root.busy && root.connected
                    onClicked: root.disconnectVpn()
                }
            }

            // feature filters, appended to every connect below
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.CheckBox { text: "P2P"; checked: root.optP2p; onToggled: root.optP2p = checked }
                PlasmaComponents.CheckBox { text: i18n("Secure Core"); checked: root.optSecureCore; onToggled: root.optSecureCore = checked }
                PlasmaComponents.CheckBox { text: "Tor"; checked: root.optTor; onToggled: root.optTor = checked }
                PlasmaComponents.CheckBox { text: i18n("Random"); checked: root.optRandom; onToggled: root.optRandom = checked }
            }

            Flow {
                Layout.fillWidth: true
                visible: root.favorites.length > 0
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.favorites
                    delegate: PlasmaComponents.Button {
                        text: root.countryName(modelData)
                        icon.name: "starred-symbolic"
                        enabled: !root.busy
                        onClicked: root.connectTo(text, ["--country", root.quote(modelData)])
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.TextField {
                    id: serverId
                    Layout.fillWidth: true
                    placeholderText: i18n("Server ID, e.g. IT#23")
                    onAccepted: connectServer.clicked()
                }
                PlasmaComponents.Button {
                    id: connectServer
                    icon.name: "network-connect"
                    text: i18n("Connect")
                    enabled: !root.busy && serverId.text.trim() !== ""
                    onClicked: root.connectTo(serverId.text.trim(), [root.quote(serverId.text.trim())])
                }
            }

            PlasmaExtras.SearchField {
                Layout.fillWidth: true
                placeholderText: i18n("Filter countries…")
                onTextChanged: root.filterText = text
            }

            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    clip: true
                    model: root.filteredCountries()
                    reuseItems: false

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: list.count === 0
                        iconName: "globe"
                        text: root.countriesLoading ? i18n("Loading servers…")
                                                    : i18n("No countries")
                    }

                    delegate: ColumnLayout {
                        id: countryRow

                        readonly property bool open: root.openCountry === modelData.code
                        readonly property var cityList: root.cities[modelData.code]

                        width: ListView.view.width
                        spacing: 0

                        PlasmaComponents.ItemDelegate {
                            Layout.fillWidth: true
                            onClicked: root.toggleCountry(modelData.code)

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: countryRow.open ? "arrow-down" : "arrow-right"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }
                                PlasmaComponents.Label {
                                    text: modelData.name
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents.Label {
                                    text: modelData.code
                                    opacity: 0.6
                                    font.pointSize: rep.smallFont
                                }
                                PlasmaComponents.ToolButton {
                                    icon.name: "network-connect"
                                    display: QQC2.AbstractButton.IconOnly
                                    text: i18n("Connect to %1", modelData.name)
                                    enabled: !root.busy
                                    onClicked: root.connectTo(modelData.name, ["--country", root.quote(modelData.code)])
                                    PlasmaComponents.ToolTip.text: text
                                    PlasmaComponents.ToolTip.visible: hovered
                                }
                            }
                        }

                        PlasmaComponents.Label {
                            visible: countryRow.open && countryRow.cityList === undefined
                            text: i18n("Loading cities…")
                            opacity: 0.6
                            leftPadding: Kirigami.Units.gridUnit * 2
                        }

                        Repeater {
                            model: countryRow.open ? (countryRow.cityList || []) : []

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.gridUnit * 2
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: modelData.name
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents.Label {
                                    text: modelData.features
                                    opacity: 0.6
                                    font.pointSize: rep.smallFont
                                }
                                PlasmaComponents.ToolButton {
                                    icon.name: "network-connect"
                                    display: QQC2.AbstractButton.IconOnly
                                    text: i18n("Connect to %1", modelData.name)
                                    enabled: !root.busy
                                    onClicked: root.connectTo(modelData.name, [
                                        "--country", root.quote(root.openCountry),
                                        "--city", root.quote(modelData.name)
                                    ])
                                    PlasmaComponents.ToolTip.text: text
                                    PlasmaComponents.ToolTip.visible: hovered
                                }
                            }
                        }
                    }
                }
            }
        }

        footer: PlasmaExtras.PlasmoidHeading {
            visible: root.lastOutput !== ""
            position: PlasmaExtras.PlasmoidHeading.Footer

            RowLayout {
                anchors.fill: parent

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.lastOutput
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    font.pointSize: rep.smallFont
                    color: root.lastOk ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                }
                PlasmaComponents.ToolButton {
                    icon.name: "window-close"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Dismiss")
                    onClicked: root.lastOutput = ""
                }
            }
        }
    }
}
