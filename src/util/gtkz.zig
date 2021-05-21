pub usingnamespace @import( "c.zig" );

pub const GtkzError = error {
    GenericFailure,
};

pub fn gtkz_signal_connect_data( instance: gpointer, signalName: [*c]const gchar, handler: GCallback, userData: gpointer, userDataDestroyFn: GClosureNotify, flags: GConnectFlags ) !gulong {
    const handlerId = g_signal_connect_data( instance, signalName, @ptrCast( GCallback, handler ), userData, userDataDestroyFn, flags );
    return switch ( handlerId ) {
        0 => GtkzError.GenericFailure,
        else => handlerId,
    };
}
