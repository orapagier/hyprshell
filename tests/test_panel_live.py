"""Geometry verifier checks; these do not create a compositor output."""
import copy
import unittest

from tools.check_panel_live import check_geometry, fixture_source


class PanelLiveGeometryTests(unittest.TestCase):
    def setUp(self):
        self.output = dict(x=1920, y=100, width=1920, height=1080, scale=2)
        self.rows = [
            dict(namespace='hyprshell-dock', x=1930, y=105, w=940, h=32),
            dict(namespace='hyprshell-taskbar', x=1930, y=603, w=940, h=32),
        ]

    def test_scaled_output_and_global_offset(self):
        check_geometry(self.rows, self.output, ('top', 'bottom'))

    def test_reject_wrong_edge(self):
        with self.assertRaises(AssertionError):
            check_geometry(self.rows, self.output, ('bottom', 'top'))

    def test_reject_offscreen_surface(self):
        rows = copy.deepcopy(self.rows)
        rows[1]['w'] = 960
        with self.assertRaises(AssertionError):
            check_geometry(rows, self.output, ('top', 'bottom'))

    def test_reject_overlap_at_adjacent_corner(self):
        rows = copy.deepcopy(self.rows)
        rows[1].update(x=1925, y=110, w=32, h=520)
        with self.assertRaises(AssertionError):
            check_geometry(rows, self.output, ('top', 'left'))

    def test_accept_adjacent_corner_clearance(self):
        rows = copy.deepcopy(self.rows)
        rows[1].update(x=1925, y=142, w=32, h=488)
        check_geometry(rows, self.output, ('top', 'left'))

    def test_both_hyprpane_pairs_allow_content_height(self):
        for component, namespace in [('hyprdock', 'hyprshell-dock'),
                                     ('hyprbar', 'hyprshell-taskbar')]:
            with self.subTest(component=component):
                rows = copy.deepcopy(self.rows)
                rows[0].update(namespace='hyprshell', h=36)
                rows[1]['namespace'] = namespace
                check_geometry(rows, self.output, ('top', 'bottom'), ('hyprpane', component))

    def test_reject_missing_or_wrong_component(self):
        for rows in (self.rows[:1], [self.rows[0], self.rows[0]]):
            with self.subTest(rows=rows), self.assertRaises(AssertionError):
                check_geometry(rows, self.output, ('top', 'bottom'))

    def test_fixture_uses_production_panels_with_output_filter(self):
        source = fixture_source()
        self.assertEqual(source.count("model: Quickshell.screens.filter("), 3)
        for text in ('id: panels', 'id: docks', 'id: taskbars',
                     'pane.vertical ? pane.implicitWidth : pane.implicitHeight',
                     'cornerInsets.top + (availableHeight - implicitHeight) / 2'):
            self.assertIn(text, source)
        self.assertNotIn('NotificationInbox {', source)
        self.assertNotIn('DesktopServices {', source)
