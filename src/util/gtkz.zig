usingnamespace @import( "misc.zig" );
pub usingnamespace @import( "c.zig" );

pub const GtkzError = error {
    GenericFailure,
};

pub const GtkzSignalConnection = struct {
    instance: gpointer,
    handlerId: gulong,
};

pub fn gtkzSignalConnect( instance: gpointer, signalName: [*c]const gchar, handler: GCallback, userData: gpointer ) !GtkzSignalConnection {
    return GtkzSignalConnection {
        .instance = instance,
        .handlerId = try gtkz_signal_connect( instance, signalName, handler, userData ),
    };
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

pub fn gtkzMousePos_PX( widget: *GtkWidget, ev: anytype ) Vec2 {
    // The event also knows what window and device it came from ...
    // but ultimately the mouse is interacting with the contents of
    // a widget, so it's the widget's scale factor (not the window's
    // or the device's) that we care about here
    const scale = @intToFloat( f64, gtk_widget_get_scale_factor( widget ) );

    const xy_LPX = switch ( @TypeOf( ev ) ) {
        *GdkEventMotion => xy( ev.x, ev.y ),
        *GdkEventButton => xy( ev.x, ev.y ),
        *GdkEventScroll => xy( ev.x, ev.y ),
        else => @compileError( "Unsupported type: " ++ @typeName( @TypeOf( ev ) ) ),
    };

    return Vec2 {
        // Add 0.5 to get the center of a physical pixel
        .x = scale*xy_LPX.x + 0.5,
        .y = scale*xy_LPX.y + 0.5,
    };
}
