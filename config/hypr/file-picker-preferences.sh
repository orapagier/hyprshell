#!/bin/sh
# Compact dark GTK chooser: retain navigation while reducing visual clutter.
# Geometry is also bounded by the compositor's file-picker window rules.
set -eu
schema=org.gtk.Settings.FileChooser
gsettings set "$schema" window-size '(860, 560)'
gsettings set "$schema" show-size-column false
gsettings set "$schema" show-type-column false
gsettings set "$schema" sort-directories-first true
