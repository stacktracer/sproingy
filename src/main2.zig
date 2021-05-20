const std = @import( "std" );
const print = std.debug.print;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub usingnamespace @cImport( {
    @cInclude( "epoxy/gl.h" );
    @cInclude( "gtk/gtk.h" );
} );


const G_CONNECT_FLAGS_NONE: GConnectFlags = gConnectFlagsNone: {
    // Force-cast 0 to GConnectFlags
    var zero = @as( c_int, 0 );
    const flags = @ptrCast( *GConnectFlags, &zero ).*;
    break :gConnectFlagsNone flags;
};

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


pub const Painter = struct {
    needsInit: bool = true,

    initFn: fn ( self: *Painter ) anyerror!void,
    paintFn: fn ( self: *Painter ) anyerror!void,
    deinitFn: fn ( self: *Painter ) void,

    pub fn paint( self: *Painter ) !void {
        if ( self.needsInit ) {
            try self.initFn( self );
            self.needsInit = false;
        }
        return self.paintFn( self );
    }

    pub fn deinit( self: *Painter ) void {
        return self.deinitFn( self );
    }
};

pub const Paintable = opaque {};

pub const MultiPaintable = struct {
    allocator: *Allocator,
    childPaintables: ArrayList( *Paintable ),
    childPainters: ArrayList( *Painter ),
    painter: Painter,

    pub fn init( self: *MultiPaintable, allocator: *Allocator ) void {
        self.allocator = allocator;
        self.childPaintables = ArrayList( *Paintable ).init( allocator );
        self.childPainters = ArrayList( *Painter ).init( allocator );
        self.painter = Painter {
            .initFn = painterInit,
            .paintFn = painterPaint,
            .deinitFn = painterDeinit,
        };
    }

    pub fn addChild( self: *MultiPaintable, comptime T: type ) !*T {
        var childPaintable = try self.allocator.create( T );
        try self.childPaintables.append( @ptrCast( *Paintable, childPaintable ) );
        try self.childPainters.append( &childPaintable.painter );
        return childPaintable;
    }

    fn painterInit( painter: *Painter ) !void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        // Do nothing
    }

    fn painterPaint( painter: *Painter ) !void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            try childPainter.paint( );
        }
    }

    fn painterDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            childPainter.deinit( );
        }
        self.childPainters.deinit( );
    }

    pub fn deinit( self: *MultiPaintable ) void {
        for ( self.childPaintables.items ) |childPaintable| {
            self.allocator.destroy( childPaintable );
        }
        self.childPaintables.deinit( );
    }
};


pub const DummyPaintable = struct {
    painter: Painter,
    // vao: GLuint,
    // dVertexCoords: GLuint,
    // dProgram: DummyProgram,

    pub fn init( self: *DummyPaintable ) void {
        self.painter = Painter {
            .initFn = painterInit,
            .paintFn = painterPaint,
            .deinitFn = painterDeinit,
        };
    }

    fn painterInit( painter: *Painter ) !void {
        const self = @fieldParentPtr( DummyPaintable, "painter", painter );
        print( "    Dummy INIT\n", .{} );
    }

    fn painterPaint( painter: *Painter ) !void {
        const self = @fieldParentPtr( DummyPaintable, "painter", painter );
        print( "   Dummy PAINT\n", .{} );
    }

    fn painterDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( DummyPaintable, "painter", painter );
        print( "  Dummy DEINIT\n", .{} );
    }
};

const Model = struct {
    allocator: *Allocator,
    // axis: Axis2,
    paintable: MultiPaintable,
    // mouseFrac: Vec2,
    // draggables: []Draggable,
    // dragger: ?*Dragger,

    pub fn init( self: *Model, allocator: *Allocator ) void {
        self.allocator = allocator;
        // self.axis = asdf;
        self.paintable.init( allocator );
    }

    pub fn deinit( self: *Model ) void {
        self.paintable.deinit( );
    }
};

fn onMotion( widget: *GtkWidget, ev: *GdkEventMotion, model: *Model ) callconv(.C) gboolean {
    print( "        MOTION: {}\n", .{ ev.* } );
    return 1;
}

fn onButtonPress( widget: *GtkWidget, ev: *GdkEventButton, model: *Model ) callconv(.C) gboolean {
    print( "  BUTTON_PRESS: {}\n", .{ ev.* } );
    return 1;
}

fn onButtonRelease( widget: *GtkWidget, ev: *GdkEventButton, model: *Model ) callconv(.C) gboolean {
    print( "BUTTON_RELEASE: {}\n", .{ ev.* } );
    return 1;
}

fn onWheel( widget: *GtkWidget, ev: *GdkEventScroll_WORKAROUND, model: *Model ) callconv(.C) gboolean {
    print( "         WHEEL: {}\n", .{ ev.* } );
    return 1;
}

fn onKeyPress( widget: *GtkWidget, ev: *GdkEventKey_WORKAROUND, model: *Model ) callconv(.C) gboolean {
    print( "     KEY_PRESS: keyval = {}, state = {}\n", .{ ev.keyval, ev.state } );
    return 1;
}

fn onKeyRelease( widget: *GtkWidget, ev: *GdkEventKey_WORKAROUND, model: *Model ) callconv(.C) gboolean {
    print( "   KEY_RELEASE: keyval = {}, state = {}\n", .{ ev.keyval, ev.state } );
    return 1;
}

fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, model: *Model ) callconv(.C) gboolean {
    // const viewport_PX: [4]c_int = &undefined;
    // glGetIntegerv( GL_VIEWPORT, viewport_PX, 0 );
    print( "        RENDER\n", .{} );
    model.paintable.painter.paint( ) catch {
        // FIXME: Don't panic
        panic( "Failed to paint", .{} );
    };
    return 0;
}

fn onActivate( app: *GtkApplication, model: *Model ) callconv(.C) void {
    const window = gtk_application_window_new( app );

    const glArea = gtk_gl_area_new( );
    gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, glArea ), 3, 2 );
    gtk_widget_set_events( @ptrCast( *GtkWidget, glArea ), GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK );
    gtk_widget_set_can_focus( @ptrCast( *GtkWidget, glArea ), 1 );
    gtk_container_add( @ptrCast( *GtkContainer, window ), glArea );

    const renderHandlerId = g_signal_connect_data( glArea, "render", @ptrCast( GCallback, onRender ), model, null, G_CONNECT_FLAGS_NONE );
    if ( renderHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'render' handler", .{} );
    }

    const motionHandlerId = g_signal_connect_data( glArea, "motion-notify-event", @ptrCast( GCallback, onMotion ), model, null, G_CONNECT_FLAGS_NONE );
    if ( motionHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'motion' handler", .{} );
    }

    const buttonPressHandlerId = g_signal_connect_data( glArea, "button-press-event", @ptrCast( GCallback, onButtonPress ), model, null, G_CONNECT_FLAGS_NONE );
    if ( buttonPressHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'button-press' handler", .{} );
    }

    const buttonReleaseHandlerId = g_signal_connect_data( glArea, "button-release-event", @ptrCast( GCallback, onButtonRelease ), model, null, G_CONNECT_FLAGS_NONE );
    if ( buttonReleaseHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'button-release' handler", .{} );
    }

    const wheelHandlerId = g_signal_connect_data( glArea, "scroll-event", @ptrCast( GCallback, onWheel ), model, null, G_CONNECT_FLAGS_NONE );
    if ( wheelHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'wheel' handler", .{} );
    }

    const keyPressHandlerId = g_signal_connect_data( glArea, "key-press-event", @ptrCast( GCallback, onKeyPress ), model, null, G_CONNECT_FLAGS_NONE );
    if ( keyPressHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'key-press' handler", .{} );
    }

    const keyReleaseHandlerId = g_signal_connect_data( glArea, "key-release-event", @ptrCast( GCallback, onKeyRelease ), model, null, G_CONNECT_FLAGS_NONE );
    if ( keyReleaseHandlerId == 0 ) {
        // FIXME: Don't panic
        panic( "Failed to connect 'key-release' handler", .{} );
    }

    gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Dummy" );
    gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 800, 600 );
    gtk_widget_show_all( window );
}

pub fn main( ) !void {
    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};

    var model = try gpa.allocator.create( Model );
    model.init( &gpa.allocator );
    var dummyPaintable = try model.paintable.addChild( DummyPaintable );
    dummyPaintable.init( );

    // FIXME: What all do we need to dispose of at the end?
    // FIXME: Pass a destroy_data closure?
    // FIXME: model.deinit( ), gpa.allocator.destroy( model )

    var app = gtk_application_new( "net.hogye.dummy", .G_APPLICATION_FLAGS_NONE );
    defer g_object_unref( app );

    const activateHandlerId = g_signal_connect_data( app, "activate", @ptrCast( GCallback, onActivate ), model, null, G_CONNECT_FLAGS_NONE );
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
