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
    rootPaintable: MultiPaintable,
    draggers: ArrayList( *Dragger ),
    activeDragger: ?*Dragger,
    handlersToDisconnect: ArrayList( GtkzHandlerConnection ),
    widgetsToRepaint: ArrayList( *GtkWidget ),
    windowsToClose: ArrayList( *GtkWindow ),

    axis: *Axis2,
    dotsPaintable: *DotsPaintable,

    pub fn create( allocator: *Allocator, axis: *Axis2, dotsPaintable: *DotsPaintable ) Model {
        return Model {
            .allocator = allocator,
            .rootPaintable = MultiPaintable.create( "root", allocator ),
            .draggers = ArrayList( *Dragger ).init( allocator ),
            .activeDragger = null,
            .handlersToDisconnect = ArrayList( GtkzHandlerConnection ).init( allocator ),
            .widgetsToRepaint = ArrayList( *GtkWidget ).init( allocator ),
            .windowsToClose = ArrayList( *GtkWindow ).init( allocator ),

            .axis = axis,
            .dotsPaintable = dotsPaintable,
        };
    }

    pub fn deinit( self: *Model ) void {
        self.rootPaintable.deinit( );
        self.draggers.deinit( );
        self.activeDragger = null;
        if ( self.handlersToDisconnect.items.len > 0 ) {
            std.debug.warn( "Some signal handlers may not have been disconnected: {} remaining\n", .{ self.handlersToDisconnect.items.len } );
        }
        self.handlersToDisconnect.deinit( );
        self.widgetsToRepaint.deinit( );
        self.windowsToClose.deinit( );
    }
};

fn onButtonPress( widget: *GtkWidget, ev: *GdkEventButton, model: *Model ) callconv(.C) gboolean {
    if ( model.activeDragger == null and ev.button == 1 ) {
        const mouse_PX = gtkzMousePos_PX( widget, ev );
        model.activeDragger = findDragger( model.draggers.items, mouse_PX );
        if ( model.activeDragger != null ) {
            model.activeDragger.?.handlePress( mouse_PX );
            gtkzDrawWidgets( model.widgetsToRepaint.items );
        }
    }
    return 1;
}

fn onMotion( widget: *GtkWidget, ev: *GdkEventMotion, model: *Model ) callconv(.C) gboolean {
    if ( model.activeDragger != null ) {
        const mouse_PX = gtkzMousePos_PX( widget, ev );
        model.activeDragger.?.handleDrag( mouse_PX );
        gtkzDrawWidgets( model.widgetsToRepaint.items );
    }
    return 1;
}

fn onButtonRelease( widget: *GtkWidget, ev: *GdkEventButton, model: *Model ) callconv(.C) gboolean {
    if ( model.activeDragger != null and ev.button == 1 ) {
        const mouse_PX = gtkzMousePos_PX( widget, ev );
        model.activeDragger.?.handleRelease( mouse_PX );
        model.activeDragger = null;
        gtkzDrawWidgets( model.widgetsToRepaint.items );
    }
    return 1;
}

fn onWheel( widget: *GtkWidget, ev: *GdkEventScroll, model: *Model ) callconv(.C) gboolean {
    const mouse_PX = gtkzMousePos_PX( widget, ev );
    const mouse_FRAC = pxToAxisFrac( model.axis, mouse_PX );
    const mouse_XY = model.axis.getBounds( ).fracToValue( mouse_FRAC );

    const zoomStepFactor = 1.12;
    const zoomSteps = getZoomSteps( ev );
    const zoomFactor = pow( f64, zoomStepFactor, -zoomSteps );
    const scale = xy( zoomFactor*model.axis.x.scale, zoomFactor*model.axis.y.scale );

    model.axis.set( mouse_FRAC, mouse_XY, scale );
    gtkzDrawWidgets( model.widgetsToRepaint.items );

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
        GDK_KEY_Escape => gtkzCloseWindows( model.windowsToClose.items ),
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

fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, model: *Model ) callconv(.C) gboolean {
    const pc = PainterContext {
        .viewport_PX = glzGetViewport_PX( ),
        .lpxToPx = gtkzScaleFactor( @ptrCast( *GtkWidget, glArea ) ),
    };

    model.axis.setViewport_PX( pc.viewport_PX );

    model.rootPaintable.painter.glPaint( &pc ) catch |e| {
        // MultiPaintable shouldn't ever return an error
        std.debug.warn( "Failed to paint root: painter = {}, error = {}", .{ model.rootPaintable.painter.name, e } );
    };

    return 0;
}

fn onWindowClosing( window: *GtkWindow, ev: *GdkEvent, model: *Model ) callconv(.C) gboolean {
    gtkzDisconnectHandlers( model.handlersToDisconnect.items );
    model.handlersToDisconnect.items.len = 0;

    if ( glzHasCurrentContext( ) ) {
        model.rootPaintable.painter.glDeinit( );
    }

    return 0;
}



fn runSimulation( model: *Model ) !void {
    // FIXME: Model isn't thread-safe
    const allocator = model.allocator;

    var xyA_ = [_]f64 { -1.0,-2.0 };
    var xyB_ = [_]f64 { 0.0,0.0 };
    std.debug.assert( xyA_.len == xyB_.len );
    var coordCount = xyA_.len;
    var dotCount = @divTrunc( coordCount, 2 );
    var dotIndices = try allocator.alloc( usize, dotCount );
    var dotIndicesRange = range( 0, dotCount, 2 );
    while ( dotIndicesRange.next( ) ) |dotIndex| {
        dotIndices[ dotIndex ] = dotIndex;
    }

    // Previous
    var tA = @as( f64, -1.0 );
    var xyA = try allocator.alloc( f64, coordCount );
    std.mem.copy( f64, xyA, &xyA_ );

    // Current
    var tB = @as( f64, 0.0 );
    var xyB = try allocator.alloc( f64, coordCount );
    std.mem.copy( f64, xyB, &xyB_ );

    // Next
    var xyC = try allocator.alloc( f64, coordCount );

    while ( true ) {
        std.time.sleep( 250000 );

        var dotsUpdater = try DotsUpdater.createAndInit( model.allocator, model, xyB );
        gtkzInvokeOnce( &dotsUpdater.runnable );



        var i = @as( i32, 0 );
        while ( i < 1000 ) {



            // FIXME
            const tC = tB + 1e-7;
            const dtAB = tB - tA;
            const dtBC = tC - tB;
            const dtRatio = dtBC / dtAB;
            const dtBCSquared = dtBC * dtBC;

            for ( dotIndices ) |dotIndex| {
                const xA = xyA[ dotIndex + 0 ];
                const yA = xyA[ dotIndex + 1 ];
                const xB = xyB[ dotIndex + 0 ];
                const yB = xyB[ dotIndex + 1 ];

                const ax = 0.0;
                const ay = -9.80665; // m/s^2
                const xC = xB + ( xB - xA )*dtRatio + ax*dtBCSquared;
                const yC = yB + ( yB - yA )*dtRatio + ay*dtBCSquared;

                xyC[ dotIndex + 0 ] = xC;
                xyC[ dotIndex + 1 ] = yC;
            }

            tA = tB;
            tB = tC;
            const ptrTemp = xyA.ptr;
            xyA.ptr = xyB.ptr;
            xyB.ptr = xyC.ptr;
            xyC.ptr = ptrTemp;



            i += 1;
        }

    }
}

const DotsUpdater = struct {
    allocator: *Allocator,
    model: *Model,
    dots: []GLfloat,
    runnable: Runnable,

    pub fn createAndInit( allocator: *Allocator, model: *Model, dots: []f64 ) !*DotsUpdater {
        var dotsCopy = try allocator.alloc( GLfloat, dots.len );
        for ( dots ) |coord,i| {
            dotsCopy[ i ] = @floatCast( GLfloat, coord );
        }

        const self = try allocator.create( DotsUpdater );
        self.* = .{
            .allocator = allocator,
            .model = model,
            .dots = dotsCopy,
            .runnable = .{
                .runFn = runAndDestroySelf,
            },
        };
        return self;
    }

    fn runAndDestroySelf( runnable: *Runnable ) !void {
        const self = @fieldParentPtr( DotsUpdater, "runnable", runnable );

        // FIXME: Don't do any of this if the model has been deinited
        try self.model.dotsPaintable.dotCoords.resize( self.dots.len );
        try self.model.dotsPaintable.dotCoords.replaceRange( 0, self.dots.len, self.dots );
        self.model.dotsPaintable.dotCoordsModified = true;
        gtkzDrawWidgets( self.model.widgetsToRepaint.items );

        self.allocator.destroy( self );
    }
};

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

            gtk_application_add_window( app, @ptrCast( *GtkWindow, window ) );

            try model.handlersToDisconnect.appendSlice( &[_]GtkzHandlerConnection {
                try gtkzConnectHandler( glArea,               "render", @ptrCast( GCallback, onRender        ), model ),
                try gtkzConnectHandler( glArea,  "motion-notify-event", @ptrCast( GCallback, onMotion        ), model ),
                try gtkzConnectHandler( glArea,   "button-press-event", @ptrCast( GCallback, onButtonPress   ), model ),
                try gtkzConnectHandler( glArea, "button-release-event", @ptrCast( GCallback, onButtonRelease ), model ),
                try gtkzConnectHandler( glArea,         "scroll-event", @ptrCast( GCallback, onWheel         ), model ),
                try gtkzConnectHandler( glArea,      "key-press-event", @ptrCast( GCallback, onKeyPress      ), model ),
                try gtkzConnectHandler( glArea,    "key-release-event", @ptrCast( GCallback, onKeyRelease    ), model ),
                try gtkzConnectHandler( window,         "delete-event", @ptrCast( GCallback, onWindowClosing ), model ),
            } );

            // FIXME: Dispose of thread somehow -- maybe "running" flag in model, and thread.wait() somewhere
            const thread = try std.Thread.spawn( model, runSimulation );

        }
    }.run( app_, model_ ) catch |e| {
        std.debug.warn( "Failed to activate: {}\n", .{ e } );
        if ( @errorReturnTrace( ) ) |trace| {
            std.debug.dumpStackTrace( trace.* );
        }
        gtkzCloseWindows( model_.windowsToClose.items );
    };
}

pub fn main( ) !void {
    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};
    const allocator = &gpa.allocator;


    var axis = Axis2.create( xywh( 0, 0, 500, 500 ) );
    axis.set( xy( 0.5, 0.5 ), xy( 0, 0 ), xy( 600, 600 ) );

    var bgPaintable = ClearPaintable.create( "bg", GL_COLOR_BUFFER_BIT );
    bgPaintable.rgba = [_]GLfloat { 0.0, 0.0, 0.0, 1.0 };

    var dotsPaintable = DotsPaintable.create( "dots", &axis, allocator );
    defer dotsPaintable.deinit( );

    var model = Model.create( allocator, &axis, &dotsPaintable );
    defer model.deinit( );
    try model.rootPaintable.childPainters.append( &bgPaintable.painter );
    try model.rootPaintable.childPainters.append( &dotsPaintable.painter );
    try model.draggers.append( &axis.dragger );


    var app = gtk_application_new( "net.hogye.dots", .G_APPLICATION_FLAGS_NONE );
    defer g_object_unref( app );

    try model.handlersToDisconnect.appendSlice( &[_]GtkzHandlerConnection {
        try gtkzConnectHandler( app, "activate", @ptrCast( GCallback, onActivate ), &model ),
    } );

    var args = try ProcessArgs.create( allocator );
    defer args.deinit( );
    const runResult = g_application_run( @ptrCast( *GApplication, app ), args.argc, args.argv );
    if ( runResult != 0 ) {
        std.debug.warn( "Application exited with code {}", .{ runResult } );
    }
}
