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

        // TODO: Feels weird to call a fn with a global side effect here
        gtk_main_quit( );
    }
    return 0;
}


const Accelerator = struct {
    addAccelerationFn: fn ( self: *const Accelerator, dotIndex: usize, mass: f64, x: [2]f64, aSum_OUT: *[2]f64 ) void,

    pub fn addAcceleration( self: *const Accelerator, dotIndex: usize, mass: f64, x: [2]f64, aSum_OUT: *[2]f64 ) void {
        return self.addAccelerationFn( self, dotIndex, mass, x, aSum_OUT );
    }
};

const ConstantAcceleration = struct {
    acceleration: [2]f64,
    accelerator: Accelerator,

    pub fn init( acceleration: [2]f64 ) ConstantAcceleration {
        return ConstantAcceleration {
            .acceleration = acceleration,
            .accelerator = Accelerator {
                .addAccelerationFn = addAcceleration,
            },
        };
    }

    fn addAcceleration( accelerator: *const Accelerator, dotIndex: usize, mass: f64, x: [2]f64, aSum_OUT: *[2]f64 ) void {
        const self = @fieldParentPtr( ConstantAcceleration, "accelerator", accelerator );
        for ( self.acceleration ) |ai,i| {
            aSum_OUT[ i ] += ai;
        }
    }
};

const SpringsAcceleration = struct {
    restLength: f64,
    stiffness: f64,
    allDotCoords: *[]f64,
    accelerator: Accelerator,

    pub fn init( restLength: f64, stiffness: f64, allDotCoords: *[]f64 ) SpringsAcceleration {
        return SpringsAcceleration {
            .restLength = restLength,
            .stiffness = stiffness,
            .allDotCoords = allDotCoords,
            .accelerator = Accelerator {
                .addAccelerationFn = addAcceleration,
            },
        };
    }

    fn addAcceleration( accelerator: *const Accelerator, dotIndex: usize, mass: f64, x: [2]f64, aSum_OUT: *[2]f64 ) void {
        const self = @fieldParentPtr( SpringsAcceleration, "accelerator", accelerator );
        const c1 = self.stiffness / mass;

        const dotFirstCoordIndex = dotIndex * 2;

        const allDotCoords = self.allDotCoords.*;
        var otherFirstCoordIndex = @as( usize, 0 );
        while ( otherFirstCoordIndex < allDotCoords.len ) : ( otherFirstCoordIndex += 2 ) {
            if ( otherFirstCoordIndex != dotFirstCoordIndex ) {
                const xOther = allDotCoords[ otherFirstCoordIndex.. ][ 0..2 ].*;

                var ds = [_]f64 { undefined } ** 2;
                var dSquared = @as( f64, 0.0 );
                for ( xOther ) |xOther_i,i| {
                    const di = xOther_i - x[i];
                    ds[i] = di;
                    dSquared += di*di;
                }
                const d = sqrt( dSquared );

                const offsetFromRest = d - self.restLength;
                const c2 = c1 * offsetFromRest / d;
                for ( ds ) |di,i| {
                    // a = ( stiffness * offsetFromRest * di/d ) / mass
                    aSum_OUT[i] += c2 * di;
                }
            }
        }
    }
};

fn runSimulation( modelPtr: *?*Model ) !void {
    // Coords per dot
    comptime const n = 2;

    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};
    const allocator = &gpa.allocator;

    const dotCount = 3;
    const coordCount = dotCount * n;
    const masses = [ dotCount ]f64 { 1.0, 1.0, 1.0 };
    const xsStart = [ coordCount ]f64 { -6.0,-3.0, -6.5,-3.0, -6.1,-3.2 };
    const vsStart = [ coordCount ]f64 { 7.0,13.0,  2.0,14.0,  5.0,6.0 };

    const xMins = [n]f64 { -8.0, -6.0 };
    const xMaxs = [n]f64 {  8.0,  6.0 };

    // Send box coords to the UI
    var boxCoords = [_]f64 { xMins[0],xMaxs[1], xMins[0],xMins[1], xMaxs[0],xMaxs[1], xMaxs[0],xMins[1] };
    var boxUpdater = try BoxUpdater.createAndInit( allocator, modelPtr, &boxCoords );
    gtkzInvokeOnce( &boxUpdater.runnable );

    // Pre-compute the first coord index of each dot, for easy iteration later
    var dotFirstCoordIndices = [_]usize { undefined } ** dotCount; {
        var dotIndex = @as( usize, 0 );
        while ( dotIndex < dotCount ) : ( dotIndex += 1 ) {
            dotFirstCoordIndices[ dotIndex ] = dotIndex * n;
        }
    }

    // TODO: Use SIMD Vectors?
    // TODO: Multi-thread? (If so, avoid false sharing)

    const tFull = @as( f64, 500e-9 );
    const tHalf = 0.5*tFull;

    var coordArrays: [7][coordCount]f64 = undefined;
    var xsCurr = @as( []f64, &coordArrays[0] );
    var xsNext = @as( []f64, &coordArrays[1] );
    var vsCurr = @as( []f64, &coordArrays[2] );
    var vsHalf = @as( []f64, &coordArrays[3] );
    var vsNext = @as( []f64, &coordArrays[4] );
    var asCurr = @as( []f64, &coordArrays[5] );
    var asNext = @as( []f64, &coordArrays[6] );

    var gravity = ConstantAcceleration.init( [_]f64 { 0.0, -9.80665 } );
    var springs = SpringsAcceleration.init( 0.6, 300.0, &xsCurr );
    const accelerators = [_]*Accelerator { &gravity.accelerator, &springs.accelerator };

    xsCurr[ 0..coordCount ].* = xsStart;
    vsCurr[ 0..coordCount ].* = vsStart;
    for ( dotFirstCoordIndices ) |dotFirstCoordIndex,dotIndex| {
        const xCurr = xsCurr[ dotFirstCoordIndex.. ][ 0..n ];
        var aCurr = asCurr[ dotFirstCoordIndex.. ][ 0..n ];
        aCurr.* = [_]f64 { 0.0 } ** n;
        for ( accelerators ) |accelerator| {
            accelerator.addAcceleration( dotIndex, masses[ dotIndex ], xCurr.*, aCurr );
        }
    }

    // TODO: Exit condition?
    const frameInterval_MILLIS = 15;
    var nextFrame_PMILLIS = @as( i64, std.math.minInt( i64 ) );
    while ( true ) {
        // Send dot coords to the UI periodically
        if ( std.time.milliTimestamp( ) >= nextFrame_PMILLIS ) {
            var dotsUpdater = try DotsUpdater.createAndInit( allocator, modelPtr, xsCurr );
            gtkzInvokeOnce( &dotsUpdater.runnable );
            nextFrame_PMILLIS = std.time.milliTimestamp( ) + 15;
        }

        // Update dot coords, but without checking for bounces
        for ( vsCurr ) |vCurr,coordIndex| {
            vsHalf[ coordIndex ] = vCurr + asCurr[ coordIndex ]*tHalf;
        }
        for ( xsCurr ) |xCurr,coordIndex| {
            xsNext[ coordIndex ] = xCurr + vsHalf[ coordIndex ]*tFull;
        }
        for ( dotFirstCoordIndices ) |dotFirstCoordIndex,dotIndex| {
            var xNext = xsNext[ dotFirstCoordIndex.. ][ 0..n ];
            var aNext = asNext[ dotFirstCoordIndex.. ][ 0..n ];
            aNext.* = [_]f64 { 0.0 } ** n;
            for ( accelerators ) |accelerator| {
                accelerator.addAcceleration( dotIndex, masses[ dotIndex ], xNext.*, aNext );
            }
        }
        for ( vsHalf ) |vHalf,coordIndex| {
            vsNext[ coordIndex ] = vHalf + asNext[ coordIndex ]*tHalf;
        }

        // Handle bounces
        for ( dotFirstCoordIndices ) |dotFirstCoordIndex,dotIndex| {
            // TODO: Profile, speed up
            var xNext = xsNext[ dotFirstCoordIndex.. ][ 0..n ];

            // Bail immediately in the common case with no bounce
            var hasBounce = false;
            for ( xNext ) |xNext_i,i| {
                if ( xNext_i <= xMins[i] or xNext_i >= xMaxs[i] ) {
                    hasBounce = true;
                    break;
                }

                const aCurr_i = asCurr[ dotFirstCoordIndex + i ];
                const vCurr_i = vsCurr[ dotFirstCoordIndex + i ];
                const tTip_i = vCurr_i / ( -2.0 * aCurr_i );
                if ( 0 <= tTip_i and tTip_i < tFull ) {
                    const xCurr_i = xsCurr[ dotFirstCoordIndex + i ];
                    const xTip_i = xCurr_i + vCurr_i*tTip_i + 0.5*aCurr_i*tTip_i*tTip_i;
                    if ( xTip_i <= xMins[i] or xTip_i >= xMaxs[i] ) {
                        hasBounce = true;
                        break;
                    }
                }
            }
            if ( !hasBounce ) {
                continue;
            }

            const mass = masses[ dotIndex ];

            var aNext = asNext[ dotFirstCoordIndex.. ][ 0..n ];
            var vNext = vsNext[ dotFirstCoordIndex.. ][ 0..n ];
            var vHalf = vsHalf[ dotFirstCoordIndex.. ][ 0..n ];

            var aCurr = [_]f64 { undefined } ** n;
            var vCurr = [_]f64 { undefined } ** n;
            var xCurr = [_]f64 { undefined } ** n;
            aCurr = asCurr[ dotFirstCoordIndex.. ][ 0..n ].*;
            vCurr = vsCurr[ dotFirstCoordIndex.. ][ 0..n ].*;
            xCurr = xsCurr[ dotFirstCoordIndex.. ][ 0..n ].*;

            while ( true ) {
                // Time of soonest bounce, and what to multiply each velocity coord by at that time
                var tBounce = std.math.inf( f64 );
                var vBounceFactor = [_]f64 { 1.0 } ** n;
                for ( xNext ) |xNext_i,i| {
                    var hasMinBounce = false;
                    var hasMaxBounce = false;

                    if ( xNext_i <= xMins[i] ) {
                        hasMinBounce = true;
                    }
                    else if ( xNext_i >= xMaxs[i] ) {
                        hasMaxBounce = true;
                    }

                    const tTip_i = vCurr[i] / ( -2.0 * aCurr[i] );
                    if ( 0 <= tTip_i and tTip_i < tFull ) {
                        const xTip_i = xCurr[i] + vCurr[i]*tTip_i + 0.5*aCurr[i]*tTip_i*tTip_i;
                        if ( xTip_i <= xMins[i] ) {
                            hasMinBounce = true;
                        }
                        else if ( xTip_i >= xMaxs[i] ) {
                            hasMaxBounce = true;
                        }
                    }

                    var tsBounce_i_ = [_]f64{ undefined } ** 4;
                    var tsBounce_i = Buffer.init( &tsBounce_i_ );
                    if ( hasMinBounce ) {
                        appendBounceTimes( xCurr[i], vCurr[i], aCurr[i], xMins[i], &tsBounce_i );
                    }
                    if ( hasMaxBounce ) {
                        appendBounceTimes( xCurr[i], vCurr[i], aCurr[i], xMaxs[i], &tsBounce_i );
                    }
                    for ( tsBounce_i.items[ 0..tsBounce_i.size ] ) |tBounce_i| {
                        if ( 0 <= tBounce_i and tBounce_i < tFull ) {
                            if ( tBounce_i < tBounce ) {
                                tBounce = tBounce_i;
                                vBounceFactor = [_]f64 { 1.0 } ** n;
                                vBounceFactor[i] = -1.0;
                            }
                            else if ( tBounce_i == tBounce ) {
                                vBounceFactor[i] = -1.0;
                            }
                        }
                    }
                }

                // If soonest bounce is after timestep end, then bounce update is done
                if ( tBounce > tFull ) {
                    break;
                }

                // Update from 0 to tBounce
                {
                    var tFull_ = tBounce;
                    var tHalf_ = 0.5 * tFull_;
                    var aNext_ = [_]f64 { undefined } ** n;
                    var vNext_ = [_]f64 { undefined } ** n;
                    var xNext_ = [_]f64 { undefined } ** n;
                    for ( vCurr ) |vCurr_i,i| {
                        vHalf[i] = vCurr_i + aCurr[i]*tHalf_;
                    }
                    for ( xCurr ) |xCurr_i,i| {
                        xNext_[i] = xCurr_i + vHalf[i]*tFull_;
                    }
                    aNext_ = [_]f64 { 0.0 } ** n;
                    for ( accelerators ) |accelerator| {
                        accelerator.addAcceleration( dotIndex, mass, xNext_, &aNext_ );
                    }
                    for ( vHalf ) |vHalf_i,i| {
                        vNext_[i] = vHalf_i + aNext_[i]*tHalf_;
                    }

                    aCurr = aNext_;
                    for ( vNext_ ) |vNext_i,i| {
                        vCurr[i] = vBounceFactor[i] * vNext_i;
                    }
                    xCurr = xNext_;
                }

                // Update from tBounce to tFull
                {
                    var tFull_ = tFull - tBounce;
                    var tHalf_ = 0.5 * tFull_;
                    for ( vCurr ) |vCurr_i,i| {
                        vHalf[i] = vCurr_i + aCurr[i]*tHalf_;
                    }
                    for ( xCurr ) |xCurr_i,i| {
                        xNext[i] = xCurr_i + vHalf[i]*tFull_;
                    }
                    aNext.* = [_]f64 { 0.0 } ** n;
                    for ( accelerators ) |accelerator| {
                        accelerator.addAcceleration( dotIndex, mass, xNext.*, aNext );
                    }
                    for ( vHalf ) |vHalf_i,i| {
                        vNext[i] = vHalf_i + aNext[i]*tHalf_;
                    }
                }
            }
        }

        // Rotate slices
        swapPtrs( f64, &asCurr, &asNext );
        swapPtrs( f64, &vsCurr, &vsNext );
        swapPtrs( f64, &xsCurr, &xsNext );
    }
}

const Buffer = struct {
    items: []f64,
    size: usize,

    pub fn init( items: []f64 ) Buffer {
        return Buffer {
            .items = items,
            .size = 0,
        };
    }

    pub fn append( self: *Buffer, item: f64 ) void {
        if ( self.size < 0 or self.size >= self.items.len ) {
            std.debug.panic( "Failed to append to buffer: capacity = {d}, size = {d}", .{ self.items.len, self.size } );
        }
        self.items[ self.size ] = item;
        self.size += 1;
    }
};

/// May append up to 2 values to tsWall_OUT.
fn appendBounceTimes( x: f64, v: f64, a: f64, xWall: f64, tsWall_OUT: *Buffer ) void {
    const A = 0.5*a;
    const B = v;
    const C = x - xWall;
    if ( A == 0.0 ) {
        // Bt + C = 0
        const tWall = -C / B;
        tsWall_OUT.append( tWall );
    }
    else {
        // At² + Bt + C = 0
        const D = B*B - 4.0*A*C;
        if ( D >= 0.0 ) {
            const sqrtD = sqrt( D );
            const oneOverTwoA = 0.5 / A;
            const tWallPlus = ( -B + sqrtD )*oneOverTwoA;
            const tWallMinus = ( -B - sqrtD )*oneOverTwoA;
            tsWall_OUT.append( tWallPlus );
            tsWall_OUT.append( tWallMinus );
        }
    }
}

// TODO: Infer T
fn swapPtrs( comptime T: type, a: *[]T, b: *[]T ) void {
    const temp = a.ptr;
    a.ptr = b.ptr;
    b.ptr = temp;
}

const BoxUpdater = struct {
    allocator: *Allocator,
    modelPtr: *?*Model,
    boxCoords: []GLfloat,
    runnable: Runnable = .{
        .runFn = runAndDestroySelf,
    },

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
    runnable: Runnable = .{
        .runFn = runAndDestroySelf,
    },

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

    var args = try ProcessArgs.init( allocator );
    defer args.deinit( );
    gtk_init( &args.argc, &args.argv );

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

    const glArea = gtk_gl_area_new( );
    gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, glArea ), 3, 2 );
    gtk_widget_set_events( glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK );
    gtk_widget_set_can_focus( glArea, 1 );
    try model.widgetsToRepaint.append( glArea );

    const window = gtk_window_new( .GTK_WINDOW_TOPLEVEL );
    gtk_container_add( @ptrCast( *GtkContainer, window ), glArea );
    gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Sproingy" );
    gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 480, 360 );
    try model.windowsToClose.append( @ptrCast( *GtkWindow, window ) );

    try model.handlersToDisconnect.appendSlice( &[_]GtkzHandlerConnection {
        try gtkzConnectHandler( glArea,               "render", @ptrCast( GCallback, onRender        ), &modelPtr ),
        try gtkzConnectHandler( glArea,  "motion-notify-event", @ptrCast( GCallback, onMotion        ), &modelPtr ),
        try gtkzConnectHandler( glArea,   "button-press-event", @ptrCast( GCallback, onButtonPress   ), &modelPtr ),
        try gtkzConnectHandler( glArea, "button-release-event", @ptrCast( GCallback, onButtonRelease ), &modelPtr ),
        try gtkzConnectHandler( glArea,         "scroll-event", @ptrCast( GCallback, onWheel         ), &modelPtr ),
        try gtkzConnectHandler( glArea,      "key-press-event", @ptrCast( GCallback, onKeyPress      ), &modelPtr ),
        try gtkzConnectHandler( glArea,    "key-release-event", @ptrCast( GCallback, onKeyRelease    ), &modelPtr ),
        try gtkzConnectHandler( window,         "delete-event", @ptrCast( GCallback, onWindowClosing ), &modelPtr ),
    } );

    // TODO: Maybe let simulation thread terminate when the UI closes?
    const thread = try std.Thread.spawn( &modelPtr, runSimulation );

    gtk_widget_show_all( window );
    gtk_main( );
}
