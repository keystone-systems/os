import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window

    property var windowWidth: Math.round(fontMetrics.height * 32.2856)
    property var windowHeight: Math.round(fontMetrics.height * 13.9528)
    property var heightSafeMargin: 15
    property string resolvedThemePath: typeof keystoneThemePath === "string" ? keystoneThemePath : ""
    property var defaultTheme: ({
        background: "#111827",
        surface: "#0f172a",
        border: "#334155",
        accent: "#7c3aed",
        text: "#e5e7eb",
        mutedText: "#94a3b8",
        placeholder: "#94a3b8",
        error: "#fb7185"
    })
    property var theme: loadTheme()

    minimumWidth: Math.max(windowWidth, dialog.Layout.minimumWidth) + dialog.anchors.margins * 2
    minimumHeight: Math.max(windowHeight, dialog.Layout.minimumHeight) + dialog.anchors.margins * 2 + heightSafeMargin
    maximumWidth: minimumWidth
    maximumHeight: minimumHeight
    visible: true
    color: theme.background
    title: "Authentication required"

    function loadTheme() {
        if (!resolvedThemePath) {
            return defaultTheme;
        }

        const request = new XMLHttpRequest();

        try {
            request.open("GET", "file://" + resolvedThemePath, false);
            request.send();

            if (request.status !== 0 && request.status !== 200) {
                return defaultTheme;
            }

            const parsed = JSON.parse(request.responseText);
            return {
                background: parsed.background || defaultTheme.background,
                surface: parsed.surface || parsed.background || defaultTheme.surface,
                border: parsed.border || parsed.accent || defaultTheme.border,
                accent: parsed.accent || parsed.border || defaultTheme.accent,
                text: parsed.text || defaultTheme.text,
                mutedText: parsed.mutedText || parsed.placeholder || parsed.text || defaultTheme.mutedText,
                placeholder: parsed.placeholder || parsed.mutedText || parsed.text || defaultTheme.placeholder,
                error: parsed.error || defaultTheme.error
            };
        } catch (error) {
            console.log("Failed to load Keystone polkit theme:", error);
            return defaultTheme;
        }
    }

    onClosing: {
        hpa.setResult("fail");
    }

    FontMetrics {
        id: fontMetrics
    }

    Item {
        id: dialog

        anchors.fill: parent
        anchors.margins: 18
        focus: true

        Keys.onEscapePressed: (e) => {
            hpa.setResult("fail");
        }
        Keys.onReturnPressed: (e) => {
            hpa.setResult("auth:" + passwordField.text);
        }
        Keys.onEnterPressed: (e) => {
            hpa.setResult("auth:" + passwordField.text);
        }

        // The Hyprland windowrule already paints an outer border (theme
        // border colour via general.col.active_border). A second 1px
        // border here read as a doubled frame inside the rounded corner
        // — clean it up by leaving the surface fill only.
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: theme.surface
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: Math.round(fontMetrics.height * 0.7)

            Label {
                color: theme.text
                font.bold: true
                font.pointSize: Math.round(fontMetrics.height * 1.1)
                text: "Authenticating for " + hpa.getUser()
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
            }

            HSeparator {
                Layout.topMargin: fontMetrics.height / 4
                Layout.bottomMargin: fontMetrics.height / 4
            }

            Label {
                color: theme.mutedText
                text: hpa.getMessage()
                Layout.maximumWidth: parent.width
                wrapMode: Text.WordWrap
            }

            TextField {
                id: passwordField

                Layout.topMargin: fontMetrics.height / 3
                Layout.fillWidth: true
                placeholderText: "Password"
                placeholderTextColor: theme.placeholder
                color: theme.text
                selectionColor: theme.accent
                selectedTextColor: theme.surface
                hoverEnabled: true
                persistentSelection: true
                echoMode: TextInput.Password
                focus: true

                background: Rectangle {
                    radius: 12
                    color: window.theme.background
                    border.width: 1
                    border.color: passwordField.activeFocus ? window.theme.accent : window.theme.border
                }

                Connections {
                    target: hpa
                    function onFocusField() {
                        passwordField.focus = true;
                    }
                    function onBlockInput(block) {
                        passwordField.readOnly = block;
                        if (!block) {
                            passwordField.focus = true;
                            passwordField.selectAll();
                        }
                    }
                }
            }

            Label {
                id: errorLabel

                color: theme.error
                font.italic: true
                Layout.maximumWidth: parent.width
                text: ""
                wrapMode: Text.WordWrap

                Connections {
                    target: hpa
                    function onSetErrorString(e) {
                        errorLabel.text = e;
                    }
                }
            }

            Rectangle {
                color: "transparent"
                Layout.fillHeight: true
            }

            HSeparator {
                Layout.topMargin: fontMetrics.height / 4
                Layout.bottomMargin: fontMetrics.height / 6
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 10

                Button {
                    id: cancelButton

                    text: "Cancel"
                    onClicked: (e) => {
                        hpa.setResult("fail");
                    }

                    contentItem: Label {
                        text: cancelButton.text
                        color: window.theme.mutedText
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: 12
                        color: "transparent"
                        border.width: 1
                        border.color: window.theme.border
                    }
                }

                Button {
                    id: authenticateButton

                    text: "Authenticate"
                    onClicked: (e) => {
                        hpa.setResult("auth:" + passwordField.text);
                    }

                    contentItem: Label {
                        text: authenticateButton.text
                        color: window.theme.accent
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: 12
                        color: window.theme.background
                        border.width: 1
                        border.color: window.theme.accent
                    }
                }
            }
        }
    }

    component Separator: Rectangle {
        color: window.theme.border
    }

    component HSeparator: Separator {
        implicitHeight: 1
        Layout.fillWidth: true
    }
}
