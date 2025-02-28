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
      # Basics:
      #
          # Start a terminal
          bindsym $mod+Return exec $term

          # Kill focused window
          bindsym $mod+Shift+q kill

          # Start your launcher
          bindsym $mod+d exec $menu

          # Lock the session
          bindsym $mod+Control+l exec --no-startup-id swaylock -c 000000 -e

          # Drag floating windows by holding down $mod and left mouse button.
          # Resize them with right mouse button + $mod.
          # Despite the name, also works for non-floating windows.
          # Change normal to inverse to use left mouse button for resizing and right
          # mouse button for dragging.
          floating_modifier $mod normal

          # Reload the configuration file
          bindsym $mod+Shift+c reload

          # Exit sway (logs you out of your Wayland session)
          bindsym $mod+Shift+e exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -B 'Yes, exit sway' 'swaymsg exit'
      #
      # Moving around:
      #
          # Move your focus around
          bindsym $mod+$left focus left
          bindsym $mod+$down focus down
          bindsym $mod+$up focus up
          bindsym $mod+$right focus right
          # Or use $mod+[up|down|left|right]
          bindsym $mod+Left focus left
          bindsym $mod+Down focus down
          bindsym $mod+Up focus up
          bindsym $mod+Right focus right

          # Move the focused window with the same, but add Shift
          bindsym $mod+Shift+$left move left
          bindsym $mod+Shift+$down move down
          bindsym $mod+Shift+$up move up
          bindsym $mod+Shift+$right move right
          # Ditto, with arrow keys
          bindsym $mod+Shift+Left move left
          bindsym $mod+Shift+Down move down
          bindsym $mod+Shift+Up move up
          bindsym $mod+Shift+Right move right
      #
      # Workspaces:
      #
          # Switch to workspace
          bindsym $mod+ampersand workspace number 1
          bindsym $mod+eacute workspace number 2
          bindsym $mod+quotedbl workspace number 3
          bindsym $mod+apostrophe workspace number 4
          bindsym $mod+parenleft workspace number 5
          bindsym $mod+minus workspace number 6	# +section on Apple keyboards
          bindsym $mod+egrave workspace number 7
          bindsym $mod+underscore workspace number 8	# +exclam on Apple keyboards
          bindsym $mod+ccedilla workspace number 9
          bindsym $mod+agrave workspace number 10
          # Move focused container to workspace
          bindsym $mod+Shift+ampersand move container to workspace number 1
          bindsym $mod+Shift+eacute move container to workspace number 2
          bindsym $mod+Shift+quotedbl move container to workspace number 3
          bindsym $mod+Shift+apostrophe move container to workspace number 4
          bindsym $mod+Shift+parenleft move container to workspace number 5
          bindsym $mod+Shift+minus move container to workspace number 6
          bindsym $mod+Shift+egrave move container to workspace number 7
          bindsym $mod+Shift+underscore move container to workspace number 8
          bindsym $mod+Shift+ccedilla move container to workspace number 9
          bindsym $mod+Shift+agrave move container to workspace number 10
          # Note: workspaces can have any name you want, not just numbers.
          # We just use 1-10 as the default.
          # For multi-screens.
          bindsym $mod+m move workspace to output left
      #
      # Layout stuff:
      #
          # You can "split" the current object of your focus with
          # $mod+b or $mod+v, for horizontal and vertical splits
          # respectively.
          bindsym $mod+b splith
          bindsym $mod+v splitv

          # Switch the current container between different layout styles
          bindsym $mod+s layout stacking
          bindsym $mod+w layout tabbed
          bindsym $mod+e layout toggle split

          # Make the current focus fullscreen
          bindsym $mod+f fullscreen

          # Toggle the current focus between tiling and floating mode
          bindsym $mod+Shift+space floating toggle

          # Swap focus between the tiling area and the floating area
          bindsym $mod+space focus mode_toggle

          # Move focus to the parent container
          bindsym $mod+a focus parent
      #
      # Scratchpad:
      #
          # Sway has a "scratchpad", which is a bag of holding for windows.
          # You can send windows there and get them back later.

          # Move the currently focused window to the scratchpad
          bindsym $mod+Shift+s move scratchpad

          # Show the next scratchpad window or hide the focused scratchpad window.
          # If there are multiple scratchpad windows, this command cycles through them.
          bindsym $mod+s scratchpad show
      #
      # Resizing containers:
      #
      mode "resize" {
          # left will shrink the containers width
          # right will grow the containers width
          # up will shrink the containers height
          # down will grow the containers height
          bindsym $left resize shrink width 10px
          bindsym $down resize grow height 10px
          bindsym $up resize shrink height 10px
          bindsym $right resize grow width 10px

          # Ditto, with arrow keys
          bindsym Left resize shrink width 10px
          bindsym Down resize grow height 10px
          bindsym Up resize shrink height 10px
          bindsym Right resize grow width 10px

          # Return to default mode
          bindsym Return mode "default"
          bindsym Escape mode "default"
      }
      bindsym $mod+r mode "resize"

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
