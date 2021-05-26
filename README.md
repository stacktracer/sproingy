# Sproingy

A toy project for learning about some things:
 * [Zig](https://ziglang.org/)
 * GUI toolkits with OpenGL support ([GLFW](https://www.glfw.org/), [SDL2](http://wiki.libsdl.org/), [GTK3](https://developer.gnome.org/gtk3/stable/))
 * [Verlet integration](https://en.wikipedia.org/wiki/Verlet_integration) for simple physics modeling


## Build & Run

Development is all on Linux x86-64 so far. In theory, should work on any platform where Zig, GTK3, and OpenGL are supported.

To build and run:

1. Run the `header-tweaks.sh` script, which makes local copies of GTK headers, and patches them so Zig can digest them easily
1. `zig build run`
