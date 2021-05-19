const std = @import( "std" );
const print = std.debug.print;
const panic = std.debug.panic;

pub usingnamespace @cImport( {
    @cInclude( "gtk/gtk.h" );
} );

const G_CONNECT_FLAGS_NONE: GConnectFlags = gConnectFlagsNone: {
    // Force-cast 0 to GConnectFlags
    var zero = @as( c_int, 0 );
    const flags = @ptrCast( *GConnectFlags, &zero ).*;
    break :gConnectFlagsNone flags;
};

fn onMotion( widget: *GtkWidget, ev: *GdkEventMotion, userData: gpointer ) callconv(.C) gboolean {
    print( "        MOTION: {}\n", .{ ev.* } );
    return 1;
}

fn onButtonPress( widget: *GtkWidget, ev: *GdkEventButton, userData: gpointer ) callconv(.C) gboolean {
    print( "  BUTTON_PRESS: {}\n", .{ ev.* } );
    return 1;
}

fn onButtonRelease( widget: *GtkWidget, ev: *GdkEventButton, userData: gpointer ) callconv(.C) gboolean {
    print( "BUTTON_RELEASE: {}\n", .{ ev.* } );
    return 1;
}

/// Custom declaration of the GdkEventScroll struct, without the "is_stop" bitfield.
/// Zig doesn't currently support C structs that contain bitfields, and declares the
/// struct as an opaque type. Fortunately, in this case we just want to ignore the
/// last field, and it seems that we can get away with leaving that field out of the
/// declaration.
/// TODO: Does it work reliably to leave the last field out of the declaration?
const GdkEventScroll_WORKAROUND = extern struct {
    type: GdkEventType,
    window: *GdkWindow,
    send_event: gint8,
    time: guint32,
    x: gdouble,
    y: gdouble,
    state: guint,
    direction: GdkScrollDirection,
    device: *GdkDevice,
    x_root: gdouble,
    y_root: gdouble,
    delta_x: gdouble,
    delta_y: gdouble,
    // Bitfields aren't supported
    //is_stop: u1
};

fn onWheel( widget: *GtkWidget, ev: *GdkEventScroll_WORKAROUND, userData: gpointer ) callconv(.C) gboolean {
    print( "         WHEEL: {}\n", .{ ev.* } );
    return 1;
}

/// Custom declaration of the GdkEventKey struct, without the "is_modifier" bitfield.
/// Zig doesn't currently support C structs that contain bitfields, and declares the
/// struct as an opaque type. Fortunately, in this case we just want to ignore the
/// last field, and it seems that we can get away with leaving that field out of the
/// declaration.
/// TODO: Does it work reliably to leave the last field out of the declaration?
const GdkEventKey_WORKAROUND = extern struct {
    type: GdkEventType,
    window: *GdkWindow,
    send_event: gint8,
    time: guint32,
    state: guint,
    keyval: guint,
    length: gint,
    string: [*c]gchar,
    hardware_keycode: guint16,
    group: guint8,
    // Bitfields aren't supported
    //is_modifier: u1
};

fn onKeyPress( widget: *GtkWidget, ev: *GdkEventKey_WORKAROUND, userData: gpointer ) callconv(.C) gboolean {
    print( "     KEY_PRESS: keyval = {}, state = {}\n", .{ ev.keyval, ev.state } );
    return 1;
}

fn onKeyRelease( widget: *GtkWidget, ev: *GdkEventKey_WORKAROUND, userData: gpointer ) callconv(.C) gboolean {
    print( "   KEY_RELEASE: keyval = {}, state = {}\n", .{ ev.keyval, ev.state } );
    return 1;
}

fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, userData: gpointer ) callconv(.C) gboolean {
    print( "        RENDER\n", .{} );
    return 0;
}

fn onActivate( app: *GtkApplication, userData: ?*c_void ) callconv(.C) void {
    const window = gtk_application_window_new( app );

    const glArea = gtk_gl_area_new( );
    gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, glArea ), 3, 2 );
    gtk_widget_set_events( @ptrCast( *GtkWidget, glArea ), GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK );
    gtk_widget_set_can_focus( @ptrCast( *GtkWidget, glArea ), 1 );
    gtk_container_add( @ptrCast( *GtkContainer, window ), glArea );

    const renderHandlerId = g_signal_connect_data( glArea, "render", @ptrCast( GCallback, onRender ), null, null, G_CONNECT_FLAGS_NONE );
    if ( renderHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'render' handler", .{} );
    }

    const motionHandlerId = g_signal_connect_data( glArea, "motion-notify-event", @ptrCast( GCallback, onMotion ), null, null, G_CONNECT_FLAGS_NONE );
    if ( motionHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'motion' handler", .{} );
    }

    const buttonPressHandlerId = g_signal_connect_data( glArea, "button-press-event", @ptrCast( GCallback, onButtonPress ), null, null, G_CONNECT_FLAGS_NONE );
    if ( buttonPressHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'button-press' handler", .{} );
    }

    const buttonReleaseHandlerId = g_signal_connect_data( glArea, "button-release-event", @ptrCast( GCallback, onButtonRelease ), null, null, G_CONNECT_FLAGS_NONE );
    if ( buttonReleaseHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'button-release' handler", .{} );
    }

    const wheelHandlerId = g_signal_connect_data( glArea, "scroll-event", @ptrCast( GCallback, onWheel ), null, null, G_CONNECT_FLAGS_NONE );
    if ( wheelHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'wheel' handler", .{} );
    }

    const keyPressHandlerId = g_signal_connect_data( glArea, "key-press-event", @ptrCast( GCallback, onKeyPress ), null, null, G_CONNECT_FLAGS_NONE );
    if ( keyPressHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'key-press' handler", .{} );
    }

    const keyReleaseHandlerId = g_signal_connect_data( glArea, "key-release-event", @ptrCast( GCallback, onKeyRelease ), null, null, G_CONNECT_FLAGS_NONE );
    if ( keyReleaseHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'key-release' handler", .{} );
    }

    gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Dummy" );
    gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 800, 600 );
    gtk_widget_show_all( window );
}

pub fn main( ) void {
    // FIXME: What all do we need to dispose of at the end?

    var app = gtk_application_new( "net.hogye.dummy", .G_APPLICATION_FLAGS_NONE );
    defer g_object_unref( app );

    const activateHandlerId = g_signal_connect_data( app, "activate", @ptrCast( GCallback, onActivate ), null, null, G_CONNECT_FLAGS_NONE );
    if ( activateHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'activate' handler", .{} );
    }

    const runResult = g_application_run( @ptrCast( *GApplication, app ), 0, null );
    if ( runResult != 0 ) {
        // FIXME: Don't panic
        panic( "Application exited with code {}", .{ runResult } );
    }
}
