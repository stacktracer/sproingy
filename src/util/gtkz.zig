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
