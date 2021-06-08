const std = @import( "std" );
pub usingnamespace @import( "c.zig" );

pub const GtkzError = error {
    GenericFailure,
};

pub const GtkzHandlerConnection = struct {
    instance: gpointer,
    handlerId: gulong,
};

pub fn gtkzConnectHandler( instance: gpointer, signalName: [*c]const gchar, handlerFn: anytype, userData: gpointer ) !GtkzHandlerConnection {
    return GtkzHandlerConnection {
        .instance = instance,
        .handlerId = try gtkz_signal_connect( instance, signalName, @ptrCast( GCallback, handlerFn ), userData ),
    };
}

pub fn gtkzDisconnectHandlers( connections: []const GtkzHandlerConnection ) void {
    for ( connections ) |conn| {
        g_signal_handler_disconnect( conn.instance, conn.handlerId );
    }
}

pub fn gtkzDrawWidgets( widgets: []*GtkWidget ) void {
    for ( widgets ) |widget| {
        gtk_widget_queue_draw( widget );
    }
}

pub fn gtkzCloseWindows( windows: []*GtkWindow ) void {
    for ( windows ) |window| {
        gtk_window_close( window );
    }
}

pub fn gtkzScaleFactor( widget: *GtkWidget ) f64 {
    return @intToFloat( f64, gtk_widget_get_scale_factor( widget ) );
}

/// Y coord increases upward.
pub fn gtkzMousePos_PX( widget: *GtkWidget, ev: anytype ) [2]f64 {
    // The event also knows what window and device it came from ...
    // but ultimately the mouse is interacting with the contents of
    // a widget, so it's the widget's scale factor (not the window's
    // or the device's) that we care about here
    const scale = gtkzScaleFactor( widget );

    const h_LPX = @intToFloat( f64, gtk_widget_get_allocated_height( widget ) );
    const mouse_LPX = switch ( @TypeOf( ev ) ) {
        *GdkEventMotion => [_]f64 { ev.x, h_LPX - ev.y },
        *GdkEventButton => [_]f64 { ev.x, h_LPX - ev.y },
        *GdkEventScroll => [_]f64 { ev.x, h_LPX - ev.y },
        else => @compileError( "Unsupported type: " ++ @typeName( @TypeOf( ev ) ) ),
    };

    var mouse_PX = @as( [2]f64, undefined );
    for ( mouse_LPX ) |coord_LPX, n| {
        // Scale, then add 0.5 to get the center of a physical pixel
        mouse_PX[n] = scale*coord_LPX + 0.5;
    }
    return mouse_PX;
}

pub fn gtkz_signal_connect( instance: gpointer, signalName: [*c]const gchar, handler: GCallback, userData: gpointer ) !gulong {
    return gtkz_signal_connect_data( instance, signalName, handler, userData, null, .G_CONNECT_FLAGS_NONE );
}

pub fn gtkz_signal_connect_data( instance: gpointer, signalName: [*c]const gchar, handler: GCallback, userData: gpointer, userDataDestroyFn: GClosureNotify, flags: GConnectFlags ) !gulong {
    const handlerId = g_signal_connect_data( instance, signalName, @ptrCast( GCallback, handler ), userData, userDataDestroyFn, flags );
    return switch ( handlerId ) {
        0 => GtkzError.GenericFailure,
        else => handlerId,
    };
}

pub const FullscreenKeysHandler = struct {
    keyvals: []const guint,

    pub fn init( keyvals: []const guint ) @This() {
        return @This() {
            .keyvals = keyvals,
        };
    }

    pub fn onKeyDown( widget: *GtkWidget, ev: *GdkEventKey, self: *@This() ) callconv(.C) gboolean {
        // TODO: Use a hash set
        for ( self.keyvals ) |keyval| {
            if ( ev.keyval == keyval ) {
                const gdkWindow = gtk_widget_get_window( widget );
                if ( gdkWindow != null ) {
                    const gtkAncestor = gtk_widget_get_toplevel( widget );
                    if ( gtk_widget_is_toplevel( gtkAncestor ) == 1 ) {
                        const gtkWindow = @ptrCast( *GtkWindow, gtkAncestor );
                        const windowState = gdk_window_get_state( gdkWindow );
                        if ( @enumToInt( windowState ) & GDK_WINDOW_STATE_FULLSCREEN != 0 ) {
                            gtk_window_unfullscreen( gtkWindow );

                            // If mouse is not in the unfullscreened window, and using focus-
                            // follows-mouse, then the window loses focus, so call present to
                            // get focus back ... and the focus loss isn't quite immediate, so
                            // pass a timestep that tells the window manager that the "regain
                            // focus" comes AFTER the "lose focus"
                            gtk_window_present_with_time( gtkWindow, ev.time + 500 );
                        }
                        else {
                            gtk_window_fullscreen( gtkWindow );
                        }
                        return 1;
                    }
                }
            }
        }
        return 0;
    }
};

pub const CloseKeysHandler = struct {
    keyvals: []const guint,

    pub fn init( keyvals: []const guint ) @This() {
        return @This() {
            .keyvals = keyvals,
        };
    }

    pub fn onKeyDown( widget: *GtkWidget, ev: *GdkEventKey, self: *@This() ) callconv(.C) gboolean {
        // TODO: Use a hash set
        for ( self.keyvals ) |keyval| {
            if ( ev.keyval == keyval ) {
                const ancestor = gtk_widget_get_toplevel( widget );
                if ( gtk_widget_is_toplevel( ancestor ) == 1 ) {
                    gtk_window_close( @ptrCast( *GtkWindow, ancestor ) );
                    return 1;
                }
            }
        }
        return 0;
    }
};

pub const QuittingHandler = struct {
    _ignored: u32 = undefined,

    pub fn init( ) QuittingHandler {
        return QuittingHandler {};
    }

    pub fn onWindowClosing( window: *GtkWindow, ev: *GdkEvent, self: *@This() ) callconv(.C) gboolean {
        gtk_main_quit( );
        return 0;
    }
};
