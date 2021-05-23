
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
 ./program
```

Show GTK Inspector:
```
GTK_DEBUG=interactive \
 GOBJECT_DEBUG=instance-count \
 ./program
```
