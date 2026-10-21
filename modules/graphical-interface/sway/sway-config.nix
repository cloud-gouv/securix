# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.securix.graphical-interface;
  terminal = if cfg.terminalVariant == "default" then "foot" else cfg.terminalVariant;
in
{
  config = mkIf (cfg.variant == "sway") {
    environment.etc."sway/config".source = pkgs.writeText "sway.config" ''
      # Default config for sway
      #
      # Copy this to ~/.config/sway/config and edit it to your liking.
      #
      # Read `man 5 sway` for a complete reference.
      # It is preconfigured for sane defaults for our usecases.

      ### Variables
      #
      # Logo key. Use Mod1 for Alt.
      set $mod Mod4
      # Home row direction keys, like vim
      set $left h
      set $down j
      set $up k
      set $right l
      # Your preferred terminal emulator
      set $term ${terminal}
      # Your preferred application launcher
      # Note: pass the final command to swaymsg so that the resulting window can be opened
      # on the original workspace that the command was run on.
      set $menu wofi --show run | xargs swaymsg exec --

      font pango:Fira Mono for Powerline 9

      # No window titles
      default_border pixel 1
      default_floating_border pixel 1

      ### Output configuration
      #
      # Default wallpaper
      # TODO
      # output * bg <securix background> fill

      ### Idle configuration
      #
      # Example configuration:
      #
      exec swayidle -w \
               timeout 300 'swaylock -f -c 000000' \
               timeout 600 'swaymsg "output * power off"' resume 'swaymsg "output * power on"' \
               before-sleep 'swaylock -f -c 000000'

      # This will lock your screen after 300 seconds of inactivity, then turn off
      # your displays after another 300 seconds, and turn your screens back on when
      # resumed. It will also lock your screen before your computer goes to sleep.

      ### Input configuration
      #
      # Example configuration:
      #
      #   input "2:14:SynPS/2_Synaptics_TouchPad" {
      #       dwt enabled
      #       tap enabled
      #       natural_scroll enabled
      #       middle_emulation enabled
      #   }
      #
      # You can get the names of your inputs by running: swaymsg -t get_inputs
      # Read `man 5 sway-input` for more information about this section.

      # By default, FR layout.
      input type:keyboard {
      	xkb_layout fr
      	xkb_model  pc105
        xkb_variant oss
        # Should make it specific to Ryan Lahfa.
      	repeat_delay 250
      	repeat_rate 60
      }

      ### Key bindings
      #
      # --to-code binds the physical key rather than the keysym, so the
      # shortcuts stay the same on fr and en keyboards.
      #
      # Basics:
      #
          # Start a terminal
          bindsym --to-code $mod+Return exec $term

          # Kill focused window
          bindsym --to-code $mod+Shift+q kill

          # Start your launcher
          bindsym --to-code $mod+d exec $menu

          # Lock the session
          bindsym --to-code $mod+Control+l exec --no-startup-id swaylock -c 000000 -e

          # Drag floating windows by holding down $mod and left mouse button.
          # Resize them with right mouse button + $mod.
          # Despite the name, also works for non-floating windows.
          # Change normal to inverse to use left mouse button for resizing and right
          # mouse button for dragging.
          floating_modifier $mod normal

          # Reload the configuration file
          bindsym --to-code $mod+Shift+c reload

          # Exit sway (logs you out of your Wayland session)
          bindsym --to-code $mod+Shift+e exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -B 'Yes, exit sway' 'swaymsg exit'
      #
      # Moving around:
      #
          # Move your focus around
          bindsym --to-code $mod+$left focus left
          bindsym --to-code $mod+$down focus down
          bindsym --to-code $mod+$up focus up
          bindsym --to-code $mod+$right focus right
          # Or use $mod+[up|down|left|right]
          bindsym --to-code $mod+Left focus left
          bindsym --to-code $mod+Down focus down
          bindsym --to-code $mod+Up focus up
          bindsym --to-code $mod+Right focus right

          # Move the focused window with the same, but add Shift
          bindsym --to-code $mod+Shift+$left move left
          bindsym --to-code $mod+Shift+$down move down
          bindsym --to-code $mod+Shift+$up move up
          bindsym --to-code $mod+Shift+$right move right
          # Ditto, with arrow keys
          bindsym --to-code $mod+Shift+Left move left
          bindsym --to-code $mod+Shift+Down move down
          bindsym --to-code $mod+Shift+Up move up
          bindsym --to-code $mod+Shift+Right move right
      #
      # Workspaces:
      #
          # Switch to workspace
          bindsym --to-code $mod+ampersand workspace number 1
          bindsym --to-code $mod+eacute workspace number 2
          bindsym --to-code $mod+quotedbl workspace number 3
          bindsym --to-code $mod+apostrophe workspace number 4
          bindsym --to-code $mod+parenleft workspace number 5
          bindsym --to-code $mod+minus workspace number 6	# +section on Apple keyboards
          bindsym --to-code $mod+egrave workspace number 7
          bindsym --to-code $mod+underscore workspace number 8	# +exclam on Apple keyboards
          bindsym --to-code $mod+ccedilla workspace number 9
          bindsym --to-code $mod+agrave workspace number 10
          # Move focused container to workspace
          bindsym --to-code $mod+Shift+ampersand move container to workspace number 1
          bindsym --to-code $mod+Shift+eacute move container to workspace number 2
          bindsym --to-code $mod+Shift+quotedbl move container to workspace number 3
          bindsym --to-code $mod+Shift+apostrophe move container to workspace number 4
          bindsym --to-code $mod+Shift+parenleft move container to workspace number 5
          bindsym --to-code $mod+Shift+minus move container to workspace number 6
          bindsym --to-code $mod+Shift+egrave move container to workspace number 7
          bindsym --to-code $mod+Shift+underscore move container to workspace number 8
          bindsym --to-code $mod+Shift+ccedilla move container to workspace number 9
          bindsym --to-code $mod+Shift+agrave move container to workspace number 10
          # Note: workspaces can have any name you want, not just numbers.
          # We just use 1-10 as the default.
          # For multi-screens.
          bindsym --to-code $mod+m move workspace to output left
      #
      # Layout stuff:
      #
          # You can "split" the current object of your focus with
          # $mod+b or $mod+v, for horizontal and vertical splits
          # respectively.
          bindsym --to-code $mod+b splith
          bindsym --to-code $mod+v splitv

          # Switch the current container between different layout styles
          bindsym --to-code $mod+s layout stacking
          bindsym --to-code $mod+w layout tabbed
          bindsym --to-code $mod+e layout toggle split

          # Make the current focus fullscreen
          bindsym --to-code $mod+f fullscreen

          # Toggle the current focus between tiling and floating mode
          bindsym --to-code $mod+Shift+space floating toggle

          # Swap focus between the tiling area and the floating area
          bindsym --to-code $mod+space focus mode_toggle

          # Move focus to the parent container
          bindsym --to-code $mod+a focus parent
      #
      # Scratchpad:
      #
          # Sway has a "scratchpad", which is a bag of holding for windows.
          # You can send windows there and get them back later.

          # Move the currently focused window to the scratchpad
          bindsym --to-code $mod+Shift+p move scratchpad

          # Show the next scratchpad window or hide the focused scratchpad window.
          # If there are multiple scratchpad windows, this command cycles through them.
          bindsym --to-code $mod+p scratchpad show
      #
      # Resizing containers:
      #
      mode "resize" {
          # left will shrink the containers width
          # right will grow the containers width
          # up will shrink the containers height
          # down will grow the containers height
          bindsym --to-code $left resize shrink width 10px
          bindsym --to-code $down resize grow height 10px
          bindsym --to-code $up resize shrink height 10px
          bindsym --to-code $right resize grow width 10px

          # Ditto, with arrow keys
          bindsym --to-code Left resize shrink width 10px
          bindsym --to-code Down resize grow height 10px
          bindsym --to-code Up resize shrink height 10px
          bindsym --to-code Right resize grow width 10px

          # Return to default mode
          bindsym --to-code Return mode "default"
          bindsym --to-code Escape mode "default"
      }
      bindsym --to-code $mod+r mode "resize"

      #
      # Status Bar:
      #
      # Read `man 5 sway-bar` for more information about this section.
      bar {
          font pango:DejaVu Sans Mono, FontAwesome 12
          position top
          status_command i3status-rs ${./bar-top.toml}
          colors {
              separator #666666
              background #222222
              statusline #dddddd
              focused_workspace #0088CC #0088CC #ffffff
              active_workspace #333333 #333333 #ffffff
              inactive_workspace #333333 #333333 #888888
              urgent_workspace #2f343a #900000 #ffffff
          }
      }
      bar {
          font pango:DejaVu Sans Mono, FontAwesome 12
          position bottom
          workspace_buttons no
          status_command i3status-rs ${./bar-bottom.toml}
          colors {
              separator #666666
              background #222222
              statusline #dddddd
              focused_workspace #0088CC #0088CC #ffffff
              active_workspace #333333 #333333 #ffffff
              inactive_workspace #333333 #333333 #888888
              urgent_workspace #2f343a #900000 #ffffff
          }
      }
    '';
  };
}
