const std = @import( "std" );
const Builder = std.build.Builder;

pub fn build( b: *Builder ) void {
    // TODO: Does this default to debug mode, in spite of the "release" in there?
    const mode = b.standardReleaseOptions( );

    const exe = b.addExecutable( "dummy", "src/main2.zig" );
    exe.setBuildMode( mode );
    exe.addIncludeDir( "/usr/include" );

    // pkg-config --cflags gtk+-3.0
    exe.addIncludeDir( "/usr/include/gtk-3.0" );
    exe.addIncludeDir( "/usr/include/pango-1.0" );
    exe.addIncludeDir( "/usr/include/glib-2.0" );
    exe.addIncludeDir( "/usr/lib/glib-2.0/include" );
    exe.addIncludeDir( "/usr/include/harfbuzz" );
    exe.addIncludeDir( "/usr/include/freetype2" );
    exe.addIncludeDir( "/usr/include/libpng16" );
    exe.addIncludeDir( "/usr/include/libmount" );
    exe.addIncludeDir( "/usr/include/blkid" );
    exe.addIncludeDir( "/usr/include/fribidi" );
    exe.addIncludeDir( "/usr/include/cairo" );
    exe.addIncludeDir( "/usr/include/lzo" );
    exe.addIncludeDir( "/usr/include/pixman-1" );
    exe.addIncludeDir( "/usr/include/gdk-pixbuf-2.0" );
    exe.addIncludeDir( "/usr/include/gio-unix-2.0" );
    exe.addIncludeDir( "/usr/include/cloudproviders" );
    exe.addIncludeDir( "/usr/include/atk-1.0" );
    exe.addIncludeDir( "/usr/include/at-spi2-atk/2.0" );
    exe.addIncludeDir( "/usr/include/dbus-1.0" );
    exe.addIncludeDir( "/usr/lib/dbus-1.0/include" );
    exe.addIncludeDir( "/usr/include/at-spi-2.0" );

    // pkg-config --libs gtk+-3.0
    exe.linkSystemLibrary( "gtk-3" );
    exe.linkSystemLibrary( "gdk-3" );
    exe.linkSystemLibrary( "z" );
    exe.linkSystemLibrary( "pangocairo-1.0" );
    exe.linkSystemLibrary( "pango-1.0" );
    exe.linkSystemLibrary( "harfbuzz" );
    exe.linkSystemLibrary( "atk-1.0" );
    exe.linkSystemLibrary( "cairo-gobject" );
    exe.linkSystemLibrary( "cairo" );
    exe.linkSystemLibrary( "gdk_pixbuf-2.0" );
    exe.linkSystemLibrary( "gio-2.0" );
    exe.linkSystemLibrary( "gobject-2.0" );
    exe.linkSystemLibrary( "glib-2.0" );

    exe.addIncludeDir( "/usr/include/GL" );
    exe.linkSystemLibrary("c");
    //exe.linkSystemLibrary( "SDL2" );
    exe.linkSystemLibrary( "epoxy" );
    exe.install( );

    b.default_step.dependOn( &exe.step );
}
