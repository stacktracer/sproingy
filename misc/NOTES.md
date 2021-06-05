
Run in a nested window with artificially inflated display scaling:
```
MUTTER_DEBUG_DUMMY_MODE_SPECS=1700x1000 MUTTER_DEBUG_DUMMY_MONITOR_SCALES=2 mutter --wayland --nested
WAYLAND_DISPLAY=wayland-1 ./zig-cache/bin/sproingy
```

Record a GIF:
```
# Doesn't work in Wayland
./zig-cache/bin/sproingy & ( sleep 0.2 && ffmpeg -y -f x11grab -framerate 30 -video_size 482x390 -i :0.0+719,391 -c:v libx264rgb -crf 0 -preset ultrafast sproingy0.mkv )
ffmpeg -frames 1080 -i sproingy0.mkv4 -vf "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" sproingy0.gif
gifsicle -O9 --lossy=200 -o sproingy.gif sproingy0.gif
```

Run under Valgrind:
```
valgrind \
 --leak-check=full \
 --track-origins=yes \
 --show-leak-kinds=all \
 --suppressions=/usr/share/gtk-3.0/valgrind/gtk.supp \
 --suppressions=/usr/share/glib-2.0/valgrind/glib.supp \
 --num-callers=30 \
 --log-file=valgrind.txt \
 ./zig-cache/bin/sproingy
```

Show GTK Inspector:
```
GTK_DEBUG=interactive \
 GOBJECT_DEBUG=instance-count \
 ./zig-cache/bin/sproingy
```
