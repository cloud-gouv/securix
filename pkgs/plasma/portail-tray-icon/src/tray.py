# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

#!/usr/bin/env python3
"""
Tray icon for the Portail access proxy.
"""

import sys
import varlink
from dataclasses import dataclass
from enum import Enum, auto
from PySide6.QtCore import QTimer, QSize
from PySide6.QtGui import QIcon, QPixmap, QPainter, QColor, QAction
from PySide6.QtWidgets import QApplication, QSystemTrayIcon, QMenu, QMessageBox, QWidget
import signal
import json

class ProxyOperationalState(Enum):
    # Whether we have healthy backends we can use for requests and the service is running.
    HEALTHY = auto()
    # Whether we do not have any exit to use and we need to rely on local exits.
    STANDALONE_MODE = auto()
    # Whether we cannot service requests for any reason.
    UNHEALTHY = auto()
    # Cannot connect to the Varlink API
    CANNOT_CONNECT_TO_VARLINK = auto()
    # We just started and we are reading the current proxy's state.
    INITIALIZING = auto()

@dataclass
class ProxyState:
    op_state: ProxyOperationalState
    reason: str | None = None

class PortailTrayIcon:
    def __init__(self):
        self.varlink_client = None
        self.varlink_conn = None

        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

        self.current_state = ProxyState(
            op_state=ProxyOperationalState.INITIALIZING,
            reason=None
        )

        self.menu_parent = QWidget()
        self.tray_icon = QSystemTrayIcon(self.menu_parent)
        self.varlink_client, self.varlink_conn = self.connect_to_varlink()

        self.inhibit_updates = False
        self.update_pending = False
        self.menu = self.create_menu()
        self.tray_icon.setContextMenu(self.menu)

        self.update_icon_and_tooltip()

        # Poll the operational state of the proxy every 5s.
        # TODO: add a WatchEvents endpoint to Portail later on.
        self.timer = QTimer()
        self.timer.timeout.connect(self.poll_state)
        self.timer.start(5000)

    def show(self):
        self.tray_icon.show()
        print("Tray icon shown and started.")

    def signal_handler(self, signum, _frame):
        print(f"\nReceived signal {signum}, shutting down gracefully...")
        self.quit_app()

    def connect_to_varlink(self):
        try:
            varlink_client = varlink.Client("unix:/run/fr.gouv.portail.Control")
            varlink_conn = varlink_client.open("fr.gouv.portail.Control")
            print('Connected to Varlink')
            self.current_state.op_state = ProxyOperationalState.HEALTHY
            return (varlink_client, varlink_conn)
        except Exception as e:
            print('Failed to connect to Varlink', e)
            self.current_state.op_state = ProxyOperationalState.CANNOT_CONNECT_TO_VARLINK
            return None, None

    def list_backends(self) -> list[dict]:
        try:
            # HACK(Ryan): https://github.com/varlink/python/issues/89
            # It is not possible to reuse Varlink connections in async contexts like ours.
            # This method might be called simultaneously if the user is fast enough in its interaction.
            _client, conn = self.connect_to_varlink()
            return conn.ListBackends().get('backends', [])
        except Exception as e:
            print('Failed to list backends', e)
            return []

    def switch_backend(self, backend: dict):
        try:
            # HACK(Ryan): see `list_backends`.
            _client, conn = self.connect_to_varlink()
            if backend.get('current', False):
                # HACK(Ryan): the Varlink official library has a critical bug when it comes to nullable fields.
                # c.f. https://github.com/varlink/python/issues/36.
                # Fortunately, this is Python so we can just yolo this.
                conn._send_message(json.dumps({"method": "fr.gouv.portail.Control.SetDefaultBackend", "parameters": {"backend_id": None}}).encode('utf8'))
            else:
                conn.SetDefaultBackend(backend['id'])
        except Exception as e:
            print('Failed to switch to other backends', e)

    def on_menu_show(self):
        backends = self.update_state()
        self.update_menu(backends)
        self.inhibit_updates = True

    def create_menu(self, backends: list[dict] | None = None) -> QMenu:
        menu = QMenu(self.menu_parent)

        menu.aboutToShow.connect(self.on_menu_show)

        # Error case
        if self.varlink_conn is None:
            # Show connection error state
            connection_action = QAction("❌ Not connected to Portail", menu)
            connection_action.setEnabled(False)
            menu.addAction(connection_action)

            if self.current_state.reason is not None:
                error_action = QAction(f"Technical error message: {self.current_state.reason[:50]}...", menu)
                error_action.setEnabled(False)
                menu.addAction(error_action)

            return menu

        menu.addSection("Proxy state")

        state_display = {
            ProxyOperationalState.HEALTHY: "✅ Healthy",
            ProxyOperationalState.STANDALONE_MODE: "🟡 Standalone mode (traffic exits from this system)",
            ProxyOperationalState.UNHEALTHY: "🔴 Unhealthy",
            ProxyOperationalState.CANNOT_CONNECT_TO_VARLINK: "❌ Cannot connect to Varlink",
            ProxyOperationalState.INITIALIZING: "⏳ Initializing"
        }

        for state, display_text in state_display.items():
            state_action = QAction(display_text, menu)
            state_action.setCheckable(True)
            if self.current_state.op_state == state:
                state_action.setChecked(True)
            state_action.setEnabled(False)
            menu.addAction(state_action)

        if self.current_state.reason:
            menu.addSeparator()
            reason_action = QAction(f"Reason: {self.current_state.reason}", menu)
            reason_action.setEnabled(False)
            menu.addAction(reason_action)


        if self.current_state.op_state in (ProxyOperationalState.HEALTHY, ProxyOperationalState.STANDALONE_MODE):
            menu.addSeparator()

            # Backend selection menu
            backends_menu = menu.addMenu("🌐 Backends")
            if backends is None:
                backends = self.list_backends()

            if not backends:
                no_backend_action = QAction("No backend available", backends_menu)
                no_backend_action.setCheckable(False)
                backends_menu.addAction(no_backend_action)
                self.current_state.op_state = ProxyOperationalState.STANDALONE_MODE
            else:
                any_current = False
                for backend in backends:
                    backend_action = QAction(backend['id'], backends_menu)
                    backend_action.setCheckable(backend.get('spec', None) is not None)
                    backend_action.setChecked(backend.get('current', False))
                    any_current = any_current or backend.get('current', False)
                    backend_action.triggered.connect(lambda _, b=backend: self.switch_backend(b))
                    backends_menu.addAction(backend_action)

                if not any_current:
                    self.current_state.op_state = ProxyOperationalState.STANDALONE_MODE

        menu.addSeparator()

        refresh_action = QAction("🔄 Refresh the state", menu)
        refresh_action.triggered.connect(lambda _: self.poll_state())
        menu.addAction(refresh_action)

        menu.addSeparator()
        return menu

    def create_colored_icon(self, color):
        pixmap = QPixmap(QSize(22, 22))
        pixmap.fill(QColor(0, 0, 0, 0))

        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.Antialiasing)

        # Dessiner un cercle
        if isinstance(color, tuple):
            painter.setBrush(QColor(*color))
            painter.setPen(QColor(*color))
        else:
            painter.setBrush(color)
            painter.setPen(color)

        painter.drawEllipse(2, 2, 18, 18)
        painter.end()

        return QIcon(pixmap)

    def update_icon_and_tooltip(self):
        state_config = {
            ProxyOperationalState.HEALTHY: {
                'color': (50, 255, 50),
                'icon': '🟢',
                'tooltip': "Proxy is healthy and operational",
            },
            ProxyOperationalState.STANDALONE_MODE: {
                'color': (255, 215, 0),
                'icon': '🟡',
                'tooltip': "Standalone mode - using local exits",
            },
            ProxyOperationalState.UNHEALTHY: {
                'color': (255, 50, 50),
                'icon': '🔴',
                'tooltip': "Proxy is unhealthy - cannot service requests",
            },
            ProxyOperationalState.CANNOT_CONNECT_TO_VARLINK: {
                'color': (128, 128, 128),
                'icon': '⚫',
                'tooltip': "Cannot connect to Portail - is it running?",
            },
            ProxyOperationalState.INITIALIZING: {
                'color': (255, 165, 0),
                'icon': '🟠',
                'tooltip': "Initializing - fetching state...",
            }
        }

        config = state_config.get(self.current_state.op_state, state_config[ProxyOperationalState.INITIALIZING])
        icon = self.create_colored_icon(config['color'])

        tooltip = f"{config['icon']} Portail proxy: {config['tooltip']}"
        if self.current_state.reason:
            tooltip += f"\nReason: {self.current_state.reason}"

        self.tray_icon.setIcon(icon)
        self.tray_icon.setToolTip(tooltip)

    def update_state(self):
        backends = self.list_backends()
        if any(b.get('current', False) for b in backends):
            self.current_state.op_state = ProxyOperationalState.HEALTHY
        else:
            self.current_state.op_state = ProxyOperationalState.STANDALONE_MODE

        self.update_icon_and_tooltip()
        return backends


    def poll_state(self):
        if self.varlink_client is None or self.varlink_conn is None:
            self.varlink_client, self.varlink_conn = self.connect_to_varlink()

        backends = self.update_state()
        if self.inhibit_updates:
            pass # Skip updating the menu, it will be done upon opening it all the time.
        else:
            self.update_menu(backends)

    def update_menu(self, backends: list[dict]):
        old_menu = self.menu
        menu = self.create_menu(backends)
        self.tray_icon.setContextMenu(menu)
        old_menu.clear()
        self.menu = menu
        self.update_pending = False
        print('Menu updated.')

    def quit_app(self):
        self.tray_icon.hide()
        self.app.quit()


def main():
    try:
        app = QApplication(sys.argv)
        if not QSystemTrayIcon.isSystemTrayAvailable():
            print("Fatal error: no system tray available.")
            QMessageBox.critical(None, "Fatal error",
                                 "No system tray available in this environment")
            sys.exit(1)

        app.setQuitOnLastWindowClosed(False)
        tray_app = PortailTrayIcon()
        tray_app.show()
        sys.exit(app.exec())
    except Exception as e:
        print(f"Fatal exception: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
