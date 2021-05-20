const std = @import( "std" );
const print = std.debug.print;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const u = @import( "util.zig" );
const Interval2 = u.Interval2;
const xy = u.xy;
const xywh = u.xywh;
const a = @import( "axis.zig" );
const Axis2 = a.Axis2;
const Draggable = a.Draggable;
const Dragger = a.Dragger;
const findDragger = a.findDragger;
const pxToAxisFrac = a.pxToAxisFrac;
usingnamespace @import( "glz.zig" );
usingnamespace @cImport( {
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

    initFn: fn ( self: *Painter, viewport_PX: Interval2 ) anyerror!void,
    paintFn: fn ( self: *Painter, viewport_PX: Interval2 ) anyerror!void,
    deinitFn: fn ( self: *Painter ) void,

    pub fn paint( self: *Painter, viewport_PX: Interval2 ) !void {
        if ( self.needsInit ) {
            try self.initFn( self, viewport_PX );
            self.needsInit = false;
        }
        return self.paintFn( self, viewport_PX );
    }

    pub fn deinit( self: *Painter ) void {
        return self.deinitFn( self );
    }
};

pub const Paintable = opaque {};

pub const MultiPaintable = struct {
    painter: Painter,

    allocator: *Allocator,
    childPaintables: ArrayList( *Paintable ),
    childPainters: ArrayList( *Painter ),

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

    fn painterInit( painter: *Painter, viewport_PX: Interval2 ) !void {
        // Do nothing
    }

    fn painterPaint( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            try childPainter.paint( viewport_PX );
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


pub const ClearPaintable = struct {
    painter: Painter,
    mask: GLbitfield,
    rgba: [4]GLfloat,

    pub fn init( self: *ClearPaintable ) void {
        self.mask = GL_COLOR_BUFFER_BIT;
        self.rgba = [_]GLfloat { 0.0, 0.0, 0.0, 1.0 };
        self.painter = Painter {
            .initFn = painterInit,
            .paintFn = painterPaint,
            .deinitFn = painterDeinit,
        };
    }

    fn painterInit( painter: *Painter, viewport_PX: Interval2 ) !void {
        // Do nothing
    }

    fn painterPaint( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( ClearPaintable, "painter", painter );
        glClearColor( self.rgba[0], self.rgba[1], self.rgba[2], self.rgba[3] );
        glClear( self.mask );
    }

    fn painterDeinit( painter: *Painter ) void {
        // Do nothing
    }
};

const DummyProgram = struct {
    program: GLuint,

    XY_BOUNDS: GLint,
    SIZE_PX: GLint,
    RGBA: GLint,

    /// x_XAXIS, y_YAXIS
    inCoords: GLuint,

    /// Must be called while the appropriate GL context is current
    pub fn init( self: *DummyProgram ) !void {
        const vertSource =
            \\#version 150 core
            \\
            \\vec2 min2D( vec4 interval2D )
            \\{
            \\    return interval2D.xy;
            \\}
            \\
            \\vec2 span2D( vec4 interval2D )
            \\{
            \\    return interval2D.zw;
            \\}
            \\
            \\vec2 coordsToNdc2D( vec2 coords, vec4 bounds )
            \\{
            \\    vec2 frac = ( coords - min2D( bounds ) ) / span2D( bounds );
            \\    return ( -1.0 + 2.0*frac );
            \\}
            \\
            \\uniform vec4 XY_BOUNDS;
            \\uniform float SIZE_PX;
            \\
            \\// x_XAXIS, y_YAXIS
            \\in vec2 inCoords;
            \\
            \\void main( void ) {
            \\    vec2 xy_XYAXIS = inCoords.xy;
            \\    gl_Position = vec4( coordsToNdc2D( xy_XYAXIS, XY_BOUNDS ), 0.0, 1.0 );
            \\    gl_PointSize = SIZE_PX;
            \\}
        ;

        const fragSource =
            \\#version 150 core
            \\precision lowp float;
            \\
            \\const float FEATHER_PX = 0.9;
            \\
            \\uniform float SIZE_PX;
            \\uniform vec4 RGBA;
            \\
            \\out vec4 outRgba;
            \\
            \\void main( void ) {
            \\    vec2 xy_NPC = -1.0 + 2.0*gl_PointCoord;
            \\    float r_NPC = sqrt( dot( xy_NPC, xy_NPC ) );
            \\
            \\    float pxToNpc = 2.0 / SIZE_PX;
            \\    float rOuter_NPC = 1.0 - 0.5*pxToNpc;
            \\    float rInner_NPC = rOuter_NPC - FEATHER_PX*pxToNpc;
            \\    float mask = smoothstep( rOuter_NPC, rInner_NPC, r_NPC );
            \\
            \\    float alpha = mask * RGBA.a;
            \\    outRgba = vec4( alpha*RGBA.rgb, alpha );
            \\}
        ;

        self.program = try glzCreateProgram( vertSource, fragSource );
        self.XY_BOUNDS = glGetUniformLocation( self.program, "XY_BOUNDS" );
        self.SIZE_PX = glGetUniformLocation( self.program, "SIZE_PX" );
        self.RGBA = glGetUniformLocation( self.program, "RGBA" );
        self.inCoords = @intCast( GLuint, glGetAttribLocation( self.program, "inCoords" ) );
    }
};

pub const DummyPaintable = struct {
    painter: Painter,

    axis: *Axis2,

    vCoords: ArrayList( GLfloat ),
    vCoordsModified: bool,

    prog: DummyProgram,
    vbo: GLuint,
    vCount: GLsizei,
    vao: GLuint,

    pub fn init( self: *DummyPaintable, allocator: *Allocator, axis: *Axis2 ) void {
        self.axis = axis;

        self.vCoords = ArrayList( GLfloat ).init( allocator );
        self.vCoordsModified = true;

        self.prog = undefined;
        self.vbo = 0;
        self.vCount = 0;
        self.vao = 0;

        self.painter = Painter {
            .initFn = painterInit,
            .paintFn = painterPaint,
            .deinitFn = painterDeinit,
        };
    }

    fn painterInit( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( DummyPaintable, "painter", painter );

        try self.prog.init( );

        glGenBuffers( 1, &self.vbo );
        glBindBuffer( GL_ARRAY_BUFFER, self.vbo );

        glGenVertexArrays( 1, &self.vao );
        glBindVertexArray( self.vao );
        glEnableVertexAttribArray( self.prog.inCoords );
        glVertexAttribPointer( self.prog.inCoords, 2, GL_FLOAT, GL_FALSE, 0, null );
    }

    fn painterPaint( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( DummyPaintable, "painter", painter );

        if ( self.vCoordsModified ) {
            self.vCount = @intCast( GLsizei, @divTrunc( self.vCoords.items.len, 2 ) );
            if ( self.vCount > 0 ) {
                glBufferData( GL_ARRAY_BUFFER, 2*self.vCount*@sizeOf( GLfloat ), @ptrCast( *const c_void, self.vCoords.items.ptr ), GL_STATIC_DRAW );
            }
            self.vCoordsModified = false;
        }

        if ( self.vCount > 0 ) {
            const bounds = self.axis.getBounds( );

            glzEnablePremultipliedAlphaBlending( );

            glEnable( GL_VERTEX_PROGRAM_POINT_SIZE );
            glUseProgram( self.prog.program );
            glzUniformInterval2( self.prog.XY_BOUNDS, bounds );
            glUniform1f( self.prog.SIZE_PX, 15 );
            glUniform4f( self.prog.RGBA, 1.0, 0.0, 0.0, 1.0 );

            glBindVertexArray( self.vao );
            glDrawArrays( GL_POINTS, 0, self.vCount );
        }
    }

    fn painterDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( DummyPaintable, "painter", painter );
        print( "  Dummy DEINIT\n", .{} );
        self.vCoords.deinit( );
        glDeleteProgram( self.prog.program );
        glDeleteVertexArrays( 1, &self.vao );
        glDeleteBuffers( 1, &self.vbo );
    }
};

const Model = struct {
    allocator: *Allocator,
    paintable: MultiPaintable,
    draggables: ArrayList( *Draggable ),
    dragger: ?*Dragger,
    axis: Axis2,

    // TODO: Would be nice to have a listenable here instead
    widgetsToRepaint: ArrayList( *GtkWidget ),

    pub fn init( self: *Model, allocator: *Allocator ) void {
        self.allocator = allocator;
        self.paintable.init( allocator );
        self.draggables = ArrayList( *Draggable ).init( allocator );
        self.dragger = null;
        self.axis = Axis2.create( xywh( 0, 0, 500, 500 ) );
        self.widgetsToRepaint = ArrayList( *GtkWidget ).init( allocator );
    }

    pub fn deinit( self: *Model ) void {
        self.paintable.deinit( );
        self.dragger = null;
        self.draggables.deinit( );
        self.widgetsToRepaint.deinit( );
    }

    pub fn fireRepaint( self: *Model ) void {
        for ( self.widgetsToRepaint.items ) |widget| {
            gtk_widget_queue_draw( widget );
        }
    }
};

fn onButtonPress( widget: *GtkWidget, ev: *GdkEventButton, model: *Model ) callconv(.C) gboolean {
    if ( model.dragger == null and ev.button == 1 ) {
        // Add 0.5 to get pixel center
        const mouse_PX = xy( ev.x + 0.5, ev.y + 0.5 );
        model.dragger = findDragger( model.draggables.items, mouse_PX );
        if ( model.dragger != null ) {
            model.dragger.?.handlePress( mouse_PX );
            model.fireRepaint( );
        }
    }
    return 1;
}

fn onMotion( widget: *GtkWidget, ev: *GdkEventMotion, model: *Model ) callconv(.C) gboolean {
    if ( model.dragger != null ) {
        // Add 0.5 to get pixel center
        const mouse_PX = xy( ev.x + 0.5, ev.y + 0.5 );
        model.dragger.?.handleDrag( mouse_PX );
        model.fireRepaint( );
    }
    return 1;
}

fn onButtonRelease( widget: *GtkWidget, ev: *GdkEventButton, model: *Model ) callconv(.C) gboolean {
    if ( model.dragger != null and ev.button == 1 ) {
        // Add 0.5 to get pixel center
        const mouse_PX = xy( ev.x + 0.5, ev.y + 0.5 );
        model.dragger.?.handleDrag( mouse_PX );
        model.dragger = null;
        model.fireRepaint( );
    }
    return 1;
}

fn onWheel( widget: *GtkWidget, ev: *GdkEventScroll_WORKAROUND, model: *Model ) callconv(.C) gboolean {
    const zoomStepFactor = 1.12;
    const zoomFactor: f64 = switch ( ev.direction ) {
        .GDK_SCROLL_UP => zoomStepFactor,
        .GDK_SCROLL_DOWN => 1.0 / zoomStepFactor,
        else => 0.0,
    };
    const mouse_PX = xy( ev.x + 0.5, ev.y + 0.5 );
    const mouse_FRAC = pxToAxisFrac( &model.axis, mouse_PX );
    const mouse_XY = model.axis.getBounds( ).fracToValue( mouse_FRAC );
    const scale = xy( zoomFactor*model.axis.x.scale, zoomFactor*model.axis.y.scale );
    model.axis.set( mouse_FRAC, mouse_XY, scale );
    model.fireRepaint( );
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
    const viewport_PX = glzGetViewport_PX( );
    model.axis.setViewport_PX( viewport_PX );
    model.paintable.painter.paint( viewport_PX ) catch {
        // FIXME: Don't panic
        panic( "Failed to paint", .{} );
    };
    return 0;
}

fn onActivate( app: *GtkApplication, model: *Model ) callconv(.C) void {
    const glArea = gtk_gl_area_new( );
    gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, glArea ), 3, 2 );
    gtk_widget_set_events( glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK );
    gtk_widget_set_can_focus( glArea, 1 );

    model.widgetsToRepaint.append( glArea ) catch {
        // FIXME: Don't panic
        panic( "Failed to connect 'render' handler", .{} );
    };

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

    const window = gtk_application_window_new( app );
    gtk_container_add( @ptrCast( *GtkContainer, window ), glArea );
    gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Dummy" );
    gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 800, 600 );
    gtk_widget_show_all( window );
}

pub fn main( ) !void {
    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};

    var model = try gpa.allocator.create( Model );
    model.init( &gpa.allocator );
    model.axis.set( xy( 0.5, 0.5 ), xy( 0, 0 ), xy( 200, 200 ) );
    try model.draggables.append( &model.axis.draggable );

    var bgPaintable = try model.paintable.addChild( ClearPaintable );
    bgPaintable.init( );
    bgPaintable.mask = GL_COLOR_BUFFER_BIT;
    bgPaintable.rgba = [_]GLfloat { 0.0, 0.0, 0.0, 1.0 };

    var dummyPaintable = try model.paintable.addChild( DummyPaintable );
    dummyPaintable.init( &gpa.allocator, &model.axis );
    var dummyCoords = [_]GLfloat { 0.0,0.0, 1.0,1.0, -0.5,0.5, -0.1,0.0, 0.7,-0.1 };
    try dummyPaintable.vCoords.appendSlice( &dummyCoords );
    dummyPaintable.vCoordsModified = true;

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

    // TODO: Pass argc and argv somehow?
    const runResult = g_application_run( @ptrCast( *GApplication, app ), 0, null );
    if ( runResult != 0 ) {
        // FIXME: Don't panic
        panic( "Application exited with code {}", .{ runResult } );
    }
}
