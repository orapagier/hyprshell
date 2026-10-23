# Hyprpane persistence

`tests/test_panel_persistence.py` exercises four-edge Hyprpane settings through
fresh setup, preference-preserving deployment, deployment rollback, installer
entry points, explicit sync, reviewed updates, settings recovery and setup backup
restore with undo. All writes and remotes stay inside temporary roots.

Fixtures retain appearance, item choices, application identity corrections,
monitor selection, workspace scopes/overrides, notification preferences and
accessibility choices. Invalid imported settings are rejected before deployment.
These tests do not certify physical display rendering or native tray input.
