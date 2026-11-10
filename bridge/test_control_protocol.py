from __future__ import annotations

import json
import tempfile
import time
import unittest
from pathlib import Path

from control_protocol import control_enabled, load_control, write_control
from signal_bridge import Bridge


class ControlProtocolTests(unittest.TestCase):
    def test_write_control_uses_fail_closed_flags(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "NixoBridge" / "control.json"

            write_control(path, False)
            self.assertFalse(control_enabled(load_control(path)))

            write_control(path, True)
            self.assertTrue(control_enabled(load_control(path)))

            content = json.loads(path.read_text(encoding="utf-8"))
            content["demo_only"] = False
            path.write_text(json.dumps(content), encoding="utf-8")
            self.assertFalse(control_enabled(load_control(path)))

    def test_bridge_requires_fresh_demo_ea_heartbeat_when_managed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            common_files = root / "common"
            config = root / "sources.json"
            config.write_text(
                json.dumps({"sources": [], "mt5_common_files": str(common_files)}),
                encoding="utf-8",
            )
            bridge = Bridge(config)

            self.assertTrue(bridge.signal_intake_enabled())
            write_control(bridge.control_path, True)
            self.assertFalse(bridge.signal_intake_enabled())

            status = {
                "demo_account": True,
                "system_enabled": True,
                "trading_mode": "EXTERNAL",
                "heartbeat": int(time.time()),
            }
            bridge.status_path.parent.mkdir(parents=True, exist_ok=True)
            (bridge.status_path.parent / "ea_status.json").write_text(
                json.dumps(status), encoding="utf-8"
            )
            self.assertTrue(bridge.signal_intake_enabled())

            status["demo_account"] = False
            (bridge.status_path.parent / "ea_status.json").write_text(
                json.dumps(status), encoding="utf-8"
            )
            self.assertFalse(bridge.signal_intake_enabled())

            status["demo_account"] = True
            status["heartbeat"] = int(time.time()) - 30
            (bridge.status_path.parent / "ea_status.json").write_text(
                json.dumps(status), encoding="utf-8"
            )
            self.assertFalse(bridge.signal_intake_enabled())

    def test_bridge_discards_new_messages_while_off(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            common_files = root / "common"
            config = root / "sources.json"
            config.write_text(
                json.dumps({"sources": [], "mt5_common_files": str(common_files)}),
                encoding="utf-8",
            )
            bridge = Bridge(config)
            write_control(bridge.control_path, False)

            bridge.handle_message(
                {"id": "test", "allowed_symbols": ["XAUUSD"]},
                1,
                "BUY XAUUSD NOW\nSL: 4040\nTP1: 4060",
                int(time.time()),
            )
            self.assertEqual(list(bridge.inbox.glob("*.sig")), [])


if __name__ == "__main__":
    unittest.main()
