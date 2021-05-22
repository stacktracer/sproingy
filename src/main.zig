const std = @import( "std" );
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const pow = std.math.pow;
usingnamespace @import( "util/axis.zig" );
usingnamespace @import( "util/drag.zig" );
usingnamespace @import( "util/glz.zig" );
usingnamespace @import( "util/gtkz.zig" );
usingnamespace @import( "util/misc.zig" );
usingnamespace @import( "util/paint.zig" );
usingnamespace @import( "dots.zig" );

const Model = struct {
    allocator: *Allocator,
    axis: *Axis2,
    rootPaintable: MultiPaintable,
    draggers: ArrayList( *Dragger ),
    activeDragger: ?*Dragger,
    widgetsToRepaint: ArrayList( *GtkWidget ),
    windowsToClose: ArrayList( *GtkWindow ),
    handlersToDisconnect: ArrayList( GtkzSignalConnection ),

    pub fn create( axis: *Axis2, allocator: *Allocator ) Model {
        return Model {
            .allocator = allocator,
            .axis = axis,
            .rootPaintable = MultiPaintable.create( "root", allocator ),
            .draggers = ArrayList( *Dragger ).init( allocator ),
            .activeDragger = null,
            .widgetsToRepaint = ArrayList( *GtkWidget ).init( allocator ),
            .windowsToClose = ArrayList( *GtkWindow ).init( allocator ),
            .handlersToDisconnect = ArrayList( GtkzSignalConnection ).init( allocator ),
        };
    }

    pub fn fireRepaint( self: *Model ) void {
        for ( self.widgetsToRepaint.items ) |widget| {
            gtk_widget_queue_draw( widget );
        }
    }

    pub fn fireQuit( self: *Model ) void {
        for ( self.windowsToClose.items ) |window| {
            gtk_window_close( window );
        }
    }

    pub fn disconnectHandlers( self: *Model ) void {
        for ( self.handlersToDisconnect.items ) |handler| {
            g_signal_handler_disconnect( handler.instance, handler.handlerId );
        }
        self.handlersToDisconnect.items.len = 0;
    }

    pub fn deinit( self: *Model ) void {
        if ( glzHasCurrentContext( ) ) {
            self.rootPaintable.painter.glDeinit( );
        }
        self.disconnectHandlers( );
        self.handlersToDisconnect.deinit( );
        self.widgetsToRepaint.deinit( );
        self.windowsToClose.deinit( );
        self.activeDragger = null;
        self.draggers.deinit( );
        self.rootPaintable.deinit( );
    }
};

fn onButtonPress( widget: *GtkWidget, ev: *GdkEventButton, model: *Model ) callconv(.C) gboolean {
    if ( model.activeDragger == null and ev.button == 1 ) {
        // Add 0.5 to get pixel center
        const mouse_PX = xy( ev.x + 0.5, ev.y + 0.5 );
        model.activeDragger = findDragger( model.draggers.items, mouse_PX );
        if ( model.activeDragger != null ) {
            model.activeDragger.?.handlePress( mouse_PX );
            model.fireRepaint( );
        }
    }
    return 1;
}

fn onMotion( widget: *GtkWidget, ev: *GdkEventMotion, model: *Model ) callconv(.C) gboolean {
    if ( model.activeDragger != null ) {
        // Add 0.5 to get pixel center
        const mouse_PX = xy( ev.x + 0.5, ev.y + 0.5 );
        model.activeDragger.?.handleDrag( mouse_PX );
        model.fireRepaint( );
    }
    return 1;
}

fn onButtonRelease( widget: *GtkWidget, ev: *GdkEventButton, model: *Model ) callconv(.C) gboolean {
    if ( model.activeDragger != null and ev.button == 1 ) {
        // Add 0.5 to get pixel center
        const mouse_PX = xy( ev.x + 0.5, ev.y + 0.5 );
        model.activeDragger.?.handleRelease( mouse_PX );
        model.activeDragger = null;
        model.fireRepaint( );
    }
    return 1;
}

fn onWheel( widget: *GtkWidget, ev: *GdkEventScroll, model: *Model ) callconv(.C) gboolean {
    const mouse_PX = xy( ev.x + 0.5, ev.y + 0.5 );
    const mouse_FRAC = pxToAxisFrac( model.axis, mouse_PX );
    const mouse_XY = model.axis.getBounds( ).fracToValue( mouse_FRAC );

    const zoomStepFactor = 1.12;
    const zoomSteps = getZoomSteps( ev );
    const zoomFactor = pow( f64, zoomStepFactor, -zoomSteps );
    const scale = xy( zoomFactor*model.axis.x.scale, zoomFactor*model.axis.y.scale );

    model.axis.set( mouse_FRAC, mouse_XY, scale );
    model.fireRepaint( );

    return 1;
}

fn getZoomSteps( ev: *GdkEventScroll ) f64 {
    var direction: GdkScrollDirection = undefined;
    if ( gdk_event_get_scroll_direction( @ptrCast( *GdkEvent, ev ), &direction ) != 0 ) {
        return switch ( direction ) {
            .GDK_SCROLL_UP => 1.0,
            .GDK_SCROLL_DOWN => -1.0,
            else => 0.0,
        };
    }

    var xDelta: f64 = undefined;
    var yDelta: f64 = undefined;
    if ( gdk_event_get_scroll_deltas( @ptrCast( *GdkEvent, ev ), &xDelta, &yDelta ) != 0 ) {
        return yDelta;
    }

    return 0.0;
}

fn onKeyPress( widget: *GtkWidget, ev: *GdkEventKey, model: *Model ) callconv(.C) gboolean {
    switch ( ev.keyval ) {
        GDK_KEY_Escape => model.fireQuit( ),
        else => {
            // std.debug.print( "  KEY_PRESS: keyval = {}, state = {}\n", .{ ev.keyval, ev.state } );
        },
    }
    return 1;
}

fn onKeyRelease( widget: *GtkWidget, ev: *GdkEventKey, model: *Model ) callconv(.C) gboolean {
    switch ( ev.keyval ) {
        else => {
            // std.debug.print( "KEY_RELEASE: keyval = {}, state = {}\n", .{ ev.keyval, ev.state } );
        },
    }
    return 1;
}

fn onRender( glArea_: *GtkGLArea, glContext_: *GdkGLContext, model_: *Model ) callconv(.C) gboolean {
    return struct {
        fn run( glArea: *GtkGLArea, glContext: *GdkGLContext, model: *Model ) !gboolean {
            const viewport_PX = glzGetViewport_PX( );
            model.axis.setViewport_PX( viewport_PX );
            try model.rootPaintable.painter.glPaint( viewport_PX );
            return 0;
        }
    }.run( glArea_, glContext_, model_ ) catch |e| {
        std.debug.print( "Failed to render: {}\n", .{ e } );
        if ( @errorReturnTrace( ) ) |trace| {
            std.debug.dumpStackTrace( trace.* );
        }
        return 0;
    };
}

fn onWindowClosing( window: *GtkWindow, ev: *GdkEvent, model: *Model ) callconv(.C) gboolean {
    model.deinit( );
    return 0;
}

fn onActivate( app_: *GtkApplication, model_: *Model ) callconv(.C) void {
    struct {
        fn run( app: *GtkApplication, model: *Model ) !void {
            const glArea = gtk_gl_area_new( );
            gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, glArea ), 3, 2 );
            gtk_widget_set_events( glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK );
            gtk_widget_set_can_focus( glArea, 1 );
            try model.widgetsToRepaint.append( glArea );

            const window = gtk_application_window_new( app );
            gtk_container_add( @ptrCast( *GtkContainer, window ), glArea );
            gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Dots" );
            gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 800, 600 );
            gtk_widget_show_all( window );
            try model.windowsToClose.append( @ptrCast( *GtkWindow, window ) );
            // FIXME: g_object_unref( window )?

            gtk_application_add_window( app, @ptrCast( *GtkWindow, window ) );

            const handlers = [_]GtkzSignalConnection {
                try gtkzConnect( glArea,               "render", @ptrCast( GCallback, onRender        ), model ),
                try gtkzConnect( glArea,  "motion-notify-event", @ptrCast( GCallback, onMotion        ), model ),
                try gtkzConnect( glArea,   "button-press-event", @ptrCast( GCallback, onButtonPress   ), model ),
                try gtkzConnect( glArea, "button-release-event", @ptrCast( GCallback, onButtonRelease ), model ),
                try gtkzConnect( glArea,         "scroll-event", @ptrCast( GCallback, onWheel         ), model ),
                try gtkzConnect( glArea,      "key-press-event", @ptrCast( GCallback, onKeyPress      ), model ),
                try gtkzConnect( glArea,    "key-release-event", @ptrCast( GCallback, onKeyRelease    ), model ),
                try gtkzConnect( window,         "delete-event", @ptrCast( GCallback, onWindowClosing ), model ),
            };
            try model.handlersToDisconnect.appendSlice( &handlers );
        }
    }.run( app_, model_ ) catch |e| {
        std.debug.warn( "Failed to activate: {}\n", .{ e } );
        if ( @errorReturnTrace( ) ) |trace| {
            std.debug.dumpStackTrace( trace.* );
        }
        model_.fireQuit( );
        model_.deinit( );
    };
}

pub fn main( ) !void {
    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};


    var axis = Axis2.create( xywh( 0, 0, 500, 500 ) );
    axis.set( xy( 0.5, 0.5 ), xy( 0, 0 ), xy( 200, 200 ) );

    var bgPaintable = ClearPaintable.create( "bg", GL_COLOR_BUFFER_BIT );
    bgPaintable.rgba = [_]GLfloat { 0.0, 0.0, 0.0, 1.0 };

    var dotsPaintable = DotsPaintable.create( "dots", &axis, &gpa.allocator );
    var dotsCoords = [_]GLfloat { 0.0,0.0, 1.0,1.0, -0.5,0.5, -0.1,0.0, 0.7,-0.1 };
    try dotsPaintable.vCoords.appendSlice( &dotsCoords );

    var model = Model.create( &axis, &gpa.allocator );
    try model.rootPaintable.childPainters.append( &bgPaintable.painter );
    try model.rootPaintable.childPainters.append( &dotsPaintable.painter );
    try model.draggers.append( &axis.dragger );


    var app = gtk_application_new( "net.hogye.dots", .G_APPLICATION_FLAGS_NONE );
    defer g_object_unref( app );

    const handlers = [_]GtkzSignalConnection {
        try gtkzConnect( app, "activate", @ptrCast( GCallback, onActivate ), &model ),
    };
    try model.handlersToDisconnect.appendSlice( &handlers );

    // FIXME: Pass argc and argv somehow
    const runResult = g_application_run( @ptrCast( *GApplication, app ), 0, null );
    if ( runResult != 0 ) {
        std.debug.warn( "Application exited with code {}", .{ runResult } );
    }
}
