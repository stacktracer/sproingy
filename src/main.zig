const std = @import( "std" );
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const pow = std.math.pow;
const sqrt = std.math.sqrt;
usingnamespace @import( "util/axis.zig" );
usingnamespace @import( "util/drag.zig" );
usingnamespace @import( "util/glz.zig" );
usingnamespace @import( "util/gtkz.zig" );
usingnamespace @import( "util/misc.zig" );
usingnamespace @import( "util/paint.zig" );
usingnamespace @import( "drawarrays.zig" );
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
    boxPaintable: *DrawArraysPaintable,
    dotsPaintable: *DotsPaintable,

    pub fn init( allocator: *Allocator, axis: *Axis2, boxPaintable: *DrawArraysPaintable, dotsPaintable: *DotsPaintable ) Model {
        return Model {
            .allocator = allocator,
            .rootPaintable = MultiPaintable.init( "root", allocator ),
            .draggers = ArrayList( *Dragger ).init( allocator ),
            .activeDragger = null,
            .handlersToDisconnect = ArrayList( GtkzHandlerConnection ).init( allocator ),
            .widgetsToRepaint = ArrayList( *GtkWidget ).init( allocator ),
            .windowsToClose = ArrayList( *GtkWindow ).init( allocator ),

            .axis = axis,
            .boxPaintable = boxPaintable,
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

fn onButtonPress( widget: *GtkWidget, ev: *GdkEventButton, modelPtr: *?*Model ) callconv(.C) gboolean {
    if ( modelPtr.* ) |model| {
        if ( model.activeDragger == null and ev.button == 1 ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            model.activeDragger = findDragger( model.draggers.items, mouse_PX );
            if ( model.activeDragger != null ) {
                model.activeDragger.?.handlePress( mouse_PX );
                gtkzDrawWidgets( model.widgetsToRepaint.items );
            }
        }
    }
    return 1;
}

fn onMotion( widget: *GtkWidget, ev: *GdkEventMotion, modelPtr: *?*Model ) callconv(.C) gboolean {
    if ( modelPtr.* ) |model| {
        if ( model.activeDragger != null ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            model.activeDragger.?.handleDrag( mouse_PX );
            gtkzDrawWidgets( model.widgetsToRepaint.items );
        }
    }
    return 1;
}

fn onButtonRelease( widget: *GtkWidget, ev: *GdkEventButton, modelPtr: *?*Model ) callconv(.C) gboolean {
    if ( modelPtr.* ) |model| {
        if ( model.activeDragger != null and ev.button == 1 ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            model.activeDragger.?.handleRelease( mouse_PX );
            model.activeDragger = null;
            gtkzDrawWidgets( model.widgetsToRepaint.items );
        }
    }
    return 1;
}

fn onWheel( widget: *GtkWidget, ev: *GdkEventScroll, modelPtr: *?*Model ) callconv(.C) gboolean {
    if ( modelPtr.* ) |model| {
        const mouse_PX = gtkzMousePos_PX( widget, ev );
        const mouse_FRAC = pxToAxisFrac( model.axis, mouse_PX );
        const mouse_XY = model.axis.getBounds( ).fracToValue( mouse_FRAC );

        const zoomStepFactor = 1.12;
        const zoomSteps = getZoomSteps( ev );
        const zoomFactor = pow( f64, zoomStepFactor, -zoomSteps );
        const scale = xy( zoomFactor*model.axis.x.scale, zoomFactor*model.axis.y.scale );

        model.axis.set( mouse_FRAC, mouse_XY, scale );
        gtkzDrawWidgets( model.widgetsToRepaint.items );
    }
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

fn onKeyPress( widget: *GtkWidget, ev: *GdkEventKey, modelPtr: *?*Model ) callconv(.C) gboolean {
    if ( modelPtr.* ) |model| {
        switch ( ev.keyval ) {
            GDK_KEY_Escape => gtkzCloseWindows( model.windowsToClose.items ),
            else => {
                // std.debug.print( "  KEY_PRESS: keyval = {}, state = {}\n", .{ ev.keyval, ev.state } );
            },
        }
    }
    return 1;
}

fn onKeyRelease( widget: *GtkWidget, ev: *GdkEventKey, modelPtr: *?*Model ) callconv(.C) gboolean {
    if ( modelPtr.* ) |model| {
        switch ( ev.keyval ) {
            else => {
                // std.debug.print( "KEY_RELEASE: keyval = {}, state = {}\n", .{ ev.keyval, ev.state } );
            },
        }
    }
    return 1;
}

fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, modelPtr: *?*Model ) callconv(.C) gboolean {
    if ( modelPtr.* ) |model| {
        const pc = PainterContext {
            .viewport_PX = glzGetViewport_PX( ),
            .lpxToPx = gtkzScaleFactor( @ptrCast( *GtkWidget, glArea ) ),
        };

        model.axis.setViewport_PX( pc.viewport_PX );

        model.rootPaintable.painter.glPaint( &pc ) catch |e| {
            // MultiPaintable shouldn't ever return an error
            std.debug.warn( "Failed to paint root: painter = {}, error = {}", .{ model.rootPaintable.painter.name, e } );
        };
    }
    return 0;
}

fn onWindowClosing( window: *GtkWindow, ev: *GdkEvent, modelPtr: *?*Model ) callconv(.C) gboolean {
    if ( modelPtr.* ) |model| {
        model.widgetsToRepaint.items.len = 0;

        gtkzDisconnectHandlers( model.handlersToDisconnect.items );
        model.handlersToDisconnect.items.len = 0;

        if ( glzHasCurrentContext( ) ) {
            model.rootPaintable.painter.glDeinit( );
        }
    }
    return 0;
}

fn onActivate( app_: *GtkApplication, modelPtr_: *?*Model ) callconv(.C) void {
    struct {
        fn run( app: *GtkApplication, modelPtr: *?*Model ) !void {
            if ( modelPtr.* ) |model| {
                const glArea = gtk_gl_area_new( );
                gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, glArea ), 3, 2 );
                gtk_widget_set_events( glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK );
                gtk_widget_set_can_focus( glArea, 1 );
                try model.widgetsToRepaint.append( glArea );

                const window = gtk_application_window_new( app );
                gtk_container_add( @ptrCast( *GtkContainer, window ), glArea );
                gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Sproingy" );
                gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 480, 360 );
                gtk_widget_show_all( window );
                try model.windowsToClose.append( @ptrCast( *GtkWindow, window ) );

                gtk_application_add_window( app, @ptrCast( *GtkWindow, window ) );

                try model.handlersToDisconnect.appendSlice( &[_]GtkzHandlerConnection {
                    try gtkzConnectHandler( glArea,               "render", @ptrCast( GCallback, onRender        ), modelPtr ),
                    try gtkzConnectHandler( glArea,  "motion-notify-event", @ptrCast( GCallback, onMotion        ), modelPtr ),
                    try gtkzConnectHandler( glArea,   "button-press-event", @ptrCast( GCallback, onButtonPress   ), modelPtr ),
                    try gtkzConnectHandler( glArea, "button-release-event", @ptrCast( GCallback, onButtonRelease ), modelPtr ),
                    try gtkzConnectHandler( glArea,         "scroll-event", @ptrCast( GCallback, onWheel         ), modelPtr ),
                    try gtkzConnectHandler( glArea,      "key-press-event", @ptrCast( GCallback, onKeyPress      ), modelPtr ),
                    try gtkzConnectHandler( glArea,    "key-release-event", @ptrCast( GCallback, onKeyRelease    ), modelPtr ),
                    try gtkzConnectHandler( window,         "delete-event", @ptrCast( GCallback, onWindowClosing ), modelPtr ),
                } );
            }

            // TODO: Maybe let simulation thread terminate when the UI closes?
            const thread = try std.Thread.spawn( modelPtr, runSimulation );
        }
    }.run( app_, modelPtr_ ) catch |e| {
        std.debug.warn( "Failed to activate: {}\n", .{ e } );
        if ( @errorReturnTrace( ) ) |trace| {
            std.debug.dumpStackTrace( trace.* );
        }
        if ( modelPtr_.* ) |model| {
            gtkzCloseWindows( model.windowsToClose.items );
        }
    };
}







const Accelerator = struct {
    pub fn add( self: *const Accelerator, xsCurr: []f64, dotIndex: usize, a: *[2]f64 ) void {

    }
};

pub fn swapPtrs( comptime T: type, a: *[]T, b: *[]T ) void {
    const temp = a.ptr;
    a.ptr = b.ptr;
    b.ptr = temp;
}

fn runSimulation( modelPtr: *?*Model ) !void {
    comptime const n = 2;

    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};
    const allocator = &gpa.allocator;

    const xsStart = [_]f64 { -6.0,-3.0, -6.5,-3.0, -6.1,-3.2 };
    const coordCount = xsStart.len;
    const vsStart = [ coordCount ]f64 { 7.0,13.0,  2.0,14.0,  5.0,6.0 };

    const accelerator = Accelerator {};

    // Pre-compute dots' start indices, for easy iteration later
    const dotCount = @divTrunc( coordCount, n );
    var dotIndices = [_]usize { undefined } ** dotCount; {
        var dotIndex = @as( usize, 0 );
        while ( dotIndex < dotCount ) : ( dotIndex += 1 ) {
            dotIndices[ dotIndex ] = dotIndex;
        }
    }

    // TODO: Use SIMD Vectors

    const tFull = 2e-7;
    const tHalf = 0.5*tFull;

    var coordArrays: [7][coordCount]f64 = undefined;
    var xsCurr = @as( []f64, &coordArrays[0] );
    var xsNext = @as( []f64, &coordArrays[1] );
    var vsCurr = @as( []f64, &coordArrays[2] );
    var vsHalf = @as( []f64, &coordArrays[3] );
    var vsNext = @as( []f64, &coordArrays[4] );
    var asCurr = @as( []f64, &coordArrays[5] );
    var asNext = @as( []f64, &coordArrays[6] );

    xsCurr[ 0..coordCount ].* = xsStart;
    vsCurr[ 0..coordCount ].* = vsStart;
    for ( dotIndices ) |_,dotIndex| {
        var aCurr = asCurr[ dotIndex*n.. ][ 0..n ];
        aCurr.* = [_]f64 { 0.0 } ** n;
        accelerator.add( xsCurr, dotIndex, aCurr );
    }

    const frameInterval_MILLIS = 15;
    var nextFrame_PMILLIS = @as( i64, std.math.minInt( i64 ) );
    while ( true ) {
        // Send dot coords to the UI periodically
        if ( std.time.milliTimestamp( ) >= nextFrame_PMILLIS ) {
            var dotsUpdater = try DotsUpdater.createAndInit( allocator, modelPtr, xsCurr );
            gtkzInvokeOnce( &dotsUpdater.runnable );
            nextFrame_PMILLIS = std.time.milliTimestamp( ) + 15;
        }

        for ( vsCurr ) |vCurr,coordIndex| {
            vsHalf[ coordIndex ] = vCurr + asCurr[ coordIndex ]*tHalf;
        }

        for ( xsCurr ) |xCurr,coordIndex| {
            xsNext[ coordIndex ] = xCurr + vsHalf[ coordIndex ]*tFull;
        }

        for ( dotIndices ) |_,dotIndex| {
            var aNext = asNext[ dotIndex*n.. ][ 0..n ];
            aNext.* = [_]f64 { 0.0 } ** n;
            accelerator.add( xsNext, dotIndex, aNext );
        }

        for ( vsHalf ) |vHalf,coordIndex| {
            vsNext[ coordIndex ] = vHalf + asNext[ coordIndex ]*tHalf;
        }

        // Rotate slices
        swapPtrs( f64, &asCurr, &asNext );
        swapPtrs( f64, &vsCurr, &vsNext );
        swapPtrs( f64, &xsCurr, &xsNext );
    }
}











fn runSimulation_OLD( modelPtr: *?*Model ) !void {
    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};
    const allocator = &gpa.allocator;

    const tStart = 0.0;
    const xsStart = [_]f64 { -6.0,-3.0, -6.5,-3.0, -6.1,-3.2 };
    const coordCount = xsStart.len;
    const vsStart = [ coordCount ]f64 { 7.0,13.0,  2.0,14.0,  5.0,6.0 };

    const aConstant = [2]f64 { 0.0, -9.80665 };
    const xMins = [2]f64 { -8.0, -6.0 };
    const xMaxs = [2]f64 {  8.0,  6.0 };

    const springStiffness = 300.0;
    const springRestLength = 0.6;
    const dotMass = 10.0;
    const dotMassRecip = 1.0 / dotMass;

    // Send box coords to the UI
    var boxCoords = [_]f64 { xMins[0],xMaxs[1], xMins[0],xMins[1], xMaxs[0],xMaxs[1], xMaxs[0],xMins[1] };
    var boxUpdater = try BoxUpdater.createAndInit( allocator, modelPtr, &boxCoords );
    gtkzInvokeOnce( &boxUpdater.runnable );

    // Pre-compute dots' start indices, for easy iteration later
    const dotCount = @divTrunc( coordCount, 2 );
    var dotIndices = range( 0, dotCount, 1 );
    var dotFirstCoordIndices = try allocator.alloc( usize, dotCount );
    while ( dotIndices.next( ) ) |dotIndex| {
        dotFirstCoordIndices[ dotIndex ] = 2 * dotIndex;
    }

    // Previous
    var tPrev = @as( f64, tStart - 2e-7 );
    var xsPrev = try allocator.alloc( f64, coordCount );
    {
        const dt = tStart - tPrev;
        const dtSquared = dt*dt;

        for ( dotFirstCoordIndices ) |dotFirstCoordIndex| {
            const xB = xsStart[ dotFirstCoordIndex.. ][ 0..2 ].*;
            const vB = vsStart[ dotFirstCoordIndex.. ][ 0..2 ].*;
            var aB = aConstant; // FIXME: Compute full acceleration at xB

            var xA: [2]f64 = undefined;
            for ( xB ) |xBi,i| {
                // Don't know vA/aA, but vB/aB are good enough for init
                xA[i] = xBi - vB[i]*dt - aB[i]*dtSquared;
            }
            xsPrev[ dotFirstCoordIndex.. ][ 0..2 ].* = xA;
        }
    }

    // Current
    var tCurr = @as( f64, tStart );
    var xsCurr = try allocator.alloc( f64, coordCount );
    xsCurr[ 0..coordCount ].* = xsStart;

    // Next
    var xsNext = try allocator.alloc( f64, coordCount );

    // TODO: Exit condition?
    while ( true ) {
        // Send current dot coords to the UI
        var dotsUpdater = try DotsUpdater.createAndInit( allocator, modelPtr, xsCurr );
        gtkzInvokeOnce( &dotsUpdater.runnable );

        // Compute new dot positions
        var timeIndices = range( 0, 1000, 1 );
        while ( timeIndices.next( ) ) |_| {
            // TODO: Dynamic timestep?
            const tNext = tCurr + 2e-7;
            const dt = tNext - tCurr;
            const dtPrev = tCurr - tPrev;
            const dtRatio = dt / dtPrev;
            const dtSquared = dt * dt;

            // TODO: Multi-thread; avoid false sharing of xsNext
            for ( dotFirstCoordIndices ) |dotFirstCoordIndex| {
                const xA = xsPrev[ dotFirstCoordIndex.. ][ 0..2 ].*;
                const xB = xsCurr[ dotFirstCoordIndex.. ][ 0..2 ].*;

                var aB = aConstant;
                for ( dotFirstCoordIndices ) |dotFirstCoordIndex2| {
                    if ( dotFirstCoordIndex2 != dotFirstCoordIndex ) {
                        const xB2 = xsCurr[ dotFirstCoordIndex2.. ][ 0..2 ].*;

                        var ds: [2]f64 = undefined;
                        var dSquared = @as( f64, 0.0 );
                        for ( xB2 ) |xB2i,i| {
                            const di = xB2i - xB[i];
                            ds[i] = di;
                            dSquared += di * di;
                        }
                        const d = sqrt( dSquared );

                        const offset = d - springRestLength;
                        const dRecip = 1.0 / d;
                        for ( ds ) |di,i| {
                            const fi = springStiffness * offset * di*dRecip;
                            aB[i] += fi * dotMassRecip;
                        }
                    }
                }

                var xC: [2]f64 = undefined;
                for ( xB ) |xBi,i| {
                    xC[i] = xBi + ( xBi - xA[i] )*dtRatio + aB[i]*dtSquared;
                }

                for ( xC ) |xCi,i| {
                    const vBi = ( xB[i] - xA[i] ) / dtPrev;

                    if ( xCi <= xMins[i] ) {
                        // The dt at which we hit the wall, i.e. x[i] - xMin[i] = 0
                        const A = aB[i];
                        const B = vBi;
                        const C = xB[i] - xMins[i];
                        const D = B*B - 4.0*A*C;
                        if ( D >= 0.0 ) {
                            const sqrtD = sqrt( D );
                            const oneOverTwoA = 0.5 / A;
                            const dtWiPlus = ( -B + sqrtD )*oneOverTwoA;
                            if ( 0 <= dtWiPlus and dtWiPlus < dt ) {
                                const xWiPlus = xB[i] + vBi*dtWiPlus + aB[i]*dtWiPlus*dtWiPlus;
                                std.debug.print( "dot = {}, i = {}, dt = {d:7.3} ns,  xWiPlus = {d}\n", .{ @divTrunc( dotFirstCoordIndex, 2 ), i, dtWiPlus*1e9, xWiPlus } );
                            }
                            const dtWiMinus = ( -B - sqrtD )*oneOverTwoA;
                            if ( 0 <= dtWiMinus and dtWiMinus < dt ) {
                                const xWiMinus = xB[i] + vBi*dtWiMinus + aB[i]*dtWiMinus*dtWiMinus;
                                std.debug.print( "dot = {}, i = {}, dt = {d:7.3} ns, xWiMinus = {d}\n", .{ @divTrunc( dotFirstCoordIndex, 2 ), i, dtWiMinus*1e9, xWiMinus } );
                            }
                        }
                    }
                    else if ( xCi >= xMaxs[i] ) {
                        // The dt at which we hit the wall, i.e. x[i] - xMax[i] = 0
                        const A = aB[i];
                        const B = vBi;
                        const C = xB[i] - xMaxs[i];
                        const D = B*B - 4.0*A*C;
                        if ( D >= 0.0 ) {
                            const sqrtD = sqrt( D );
                            const oneOverTwoA = 0.5 / A;
                            const dtWiPlus = ( -B + sqrtD )*oneOverTwoA;
                            if ( 0 <= dtWiPlus and dtWiPlus < dt ) {
                                const xWiPlus = xB[i] + vBi*dtWiPlus + aB[i]*dtWiPlus*dtWiPlus;
                                std.debug.print( "dot = {}, i = {}, dt = {d:7.3} ns,  xWiPlus = {d}\n", .{ @divTrunc( dotFirstCoordIndex, 2 ), i, dtWiPlus*1e9, xWiPlus } );
                            }
                            const dtWiMinus = ( -B - sqrtD )*oneOverTwoA;
                            if ( 0 <= dtWiMinus and dtWiMinus < dt ) {
                                const xWiMinus = xB[i] + vBi*dtWiMinus + aB[i]*dtWiMinus*dtWiMinus;
                                std.debug.print( "dot = {}, i = {}, dt = {d:7.3} ns, xWiMinus = {d}\n", .{ @divTrunc( dotFirstCoordIndex, 2 ), i, dtWiMinus*1e9, xWiMinus } );
                            }
                        }
                    }

                    // The dt at which x[i] is stationary, i.e. d(xi)/d(dt) = 0
                    const dtSi = vBi / ( -2.0 * aB[i] );
                    if ( 0 <= dtSi and dtSi < dt ) {
                        const xSi = xB[i] + vBi*dtSi + aB[i]*dtSi*dtSi;
                        if ( xSi <= xMins[i] ) {
                            std.debug.print( "dot = {}, i = {}, dt = {d:7.3} ns, xSi = {d}\n", .{ @divTrunc( dotFirstCoordIndex, 2 ), i, dtSi*1e9, xSi } );
                        }
                        else if ( xSi >= xMaxs[i] ) {
                            std.debug.print( "dot = {}, i = {}, dt = {d:7.3} ns, xSi = {d}\n", .{ @divTrunc( dotFirstCoordIndex, 2 ), i, dtSi*1e9, xSi } );
                        }
                    }
                }


                // FIXME: Bounce here, accelerating properly on each segment
                //
                // Assume we start the timestep NOT in a wall. Check whether
                // we're in a wall at the end of the timestep. Also, find the
                // time at which the derivative of the parabola is zero, and
                // if that time is before the end of the timestep, then check
                // whether we're in a wall at that time. These checks should
                // both be computationally cheap -- the expensive part will
                // be handling dots that have hit a wall, but we'll assume
                // there won't be many of those on a given timestep.
                //
                // Quadratic formula should be enough to find the intersection
                // of the path with the wall.
                //
                // This will require keeping an unmodified copy of xsCurr, for
                // computing the forces that apply on the current timestep,
                // and also a munged copy of xsCurr, to be used as xsPrev on
                // the next timestep. Maybe it's time to read up on "velocity
                // verlet."

                xsNext[ dotFirstCoordIndex.. ][ 0..2 ].* = xC;
            }

            // FIXME: Reflect off walls -- assumes acceleration is symmetric about the wall, which generally isn't true
            // NOTE: This may modify xCurr!
            for ( dotFirstCoordIndices ) |dotFirstCoordIndex| {
                const xC = xsNext[ dotFirstCoordIndex.. ][ 0..2 ].*;
                for ( xC ) |xCi,i| {
                    if ( xCi <= xMins[i] ) {
                        xsCurr[ dotFirstCoordIndex + i ] = 2.0*xMins[i] - xsCurr[ dotFirstCoordIndex + i ];
                        xsNext[ dotFirstCoordIndex + i ] = 2.0*xMins[i] - xCi;
                    }
                    else if ( xCi >= xMaxs[i] ) {
                        xsCurr[ dotFirstCoordIndex + i ] = 2.0*xMaxs[i] - xsCurr[ dotFirstCoordIndex + i ];
                        xsNext[ dotFirstCoordIndex + i ] = 2.0*xMaxs[i] - xCi;
                    }
                }
            }

            // Rotate times
            tPrev = tCurr;
            tCurr = tNext;

            // Rotate position slices, recycling the oldest
            const xsPtrTemp = xsPrev.ptr;
            xsPrev.ptr = xsCurr.ptr;
            xsCurr.ptr = xsNext.ptr;
            xsNext.ptr = xsPtrTemp;
        }
    }
}

const BoxUpdater = struct {
    allocator: *Allocator,
    modelPtr: *?*Model,
    boxCoords: []GLfloat,
    runnable: Runnable,

    pub fn createAndInit( allocator: *Allocator, modelPtr: *?*Model, boxCoords: []f64 ) !*BoxUpdater {
        var boxCoordsCopy = try allocator.alloc( GLfloat, boxCoords.len );
        for ( boxCoords ) |coord,i| {
            boxCoordsCopy[ i ] = @floatCast( GLfloat, coord );
        }

        const self = try allocator.create( BoxUpdater );
        self.* = .{
            .allocator = allocator,
            .modelPtr = modelPtr,
            .boxCoords = boxCoordsCopy,
            .runnable = .{
                .runFn = runAndDestroySelf,
            },
        };
        return self;
    }

    fn runAndDestroySelf( runnable: *Runnable ) !void {
        const self = @fieldParentPtr( BoxUpdater, "runnable", runnable );
        if ( self.modelPtr.* ) |model| {
            try model.boxPaintable.coords.resize( self.boxCoords.len );
            try model.boxPaintable.coords.replaceRange( 0, self.boxCoords.len, self.boxCoords );
            model.boxPaintable.coordsModified = true;
            gtkzDrawWidgets( model.widgetsToRepaint.items );
        }

        // TODO: If we ever allow simulation thread to end, this allocator may not be around anymore
        self.allocator.free( self.boxCoords );
        self.allocator.destroy( self );
    }
};

const DotsUpdater = struct {
    allocator: *Allocator,
    modelPtr: *?*Model,
    dotCoords: []GLfloat,
    runnable: Runnable,

    pub fn createAndInit( allocator: *Allocator, modelPtr: *?*Model, dotCoords: []f64 ) !*DotsUpdater {
        var dotCoordsCopy = try allocator.alloc( GLfloat, dotCoords.len );
        for ( dotCoords ) |coord,i| {
            dotCoordsCopy[ i ] = @floatCast( GLfloat, coord );
        }

        const self = try allocator.create( DotsUpdater );
        self.* = .{
            .allocator = allocator,
            .modelPtr = modelPtr,
            .dotCoords = dotCoordsCopy,
            .runnable = .{
                .runFn = runAndDestroySelf,
            },
        };
        return self;
    }

    fn runAndDestroySelf( runnable: *Runnable ) !void {
        const self = @fieldParentPtr( DotsUpdater, "runnable", runnable );
        if ( self.modelPtr.* ) |model| {
            try model.dotsPaintable.coords.resize( self.dotCoords.len );
            try model.dotsPaintable.coords.replaceRange( 0, self.dotCoords.len, self.dotCoords );
            model.dotsPaintable.coordsModified = true;
            gtkzDrawWidgets( model.widgetsToRepaint.items );
        }

        // TODO: If we ever allow simulation thread to end, this allocator may not be around anymore
        self.allocator.free( self.dotCoords );
        self.allocator.destroy( self );
    }
};


pub fn main( ) !void {
    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};
    const allocator = &gpa.allocator;


    var axis = Axis2.init( xywh( 0, 0, 480, 360 ) );
    axis.set( xy( 0.5, 0.5 ), xy( 0, 0 ), xy( 28.2, 28.2 ) );

    var bgPaintable = ClearPaintable.init( "bg", GL_COLOR_BUFFER_BIT );
    bgPaintable.rgba = [_]GLfloat { 0.4, 0.4, 0.4, 1.0 };

    var boxPaintable = DrawArraysPaintable.init( "box", &axis, GL_TRIANGLE_STRIP, allocator );
    defer boxPaintable.deinit( );
    boxPaintable.rgba = [_]GLfloat { 0.0, 0.0, 0.0, 1.0 };

    var dotsPaintable = DotsPaintable.init( "dots", &axis, allocator );
    defer dotsPaintable.deinit( );
    dotsPaintable.rgba = [_]GLfloat { 1.0, 0.0, 0.0, 1.0 };

    var model = Model.init( allocator, &axis, &boxPaintable, &dotsPaintable );
    var modelPtr = @as( ?*Model, &model );
    defer modelPtr = null;
    defer model.deinit( );
    try model.rootPaintable.childPainters.append( &bgPaintable.painter );
    try model.rootPaintable.childPainters.append( &boxPaintable.painter );
    try model.rootPaintable.childPainters.append( &dotsPaintable.painter );
    try model.draggers.append( &axis.dragger );


    var app = gtk_application_new( "net.hogye.sproingy", .G_APPLICATION_FLAGS_NONE );
    defer g_object_unref( app );

    try model.handlersToDisconnect.appendSlice( &[_]GtkzHandlerConnection {
        try gtkzConnectHandler( app, "activate", @ptrCast( GCallback, onActivate ), &modelPtr ),
    } );

    var args = try ProcessArgs.init( allocator );
    defer args.deinit( );
    const runResult = g_application_run( @ptrCast( *GApplication, app ), args.argc, args.argv );
    if ( runResult != 0 ) {
        std.debug.warn( "Application exited with code {}", .{ runResult } );
    }
}
