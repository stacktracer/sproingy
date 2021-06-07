const std = @import( "std" );
const inf = std.math.inf;
const min = std.math.min;
const Mutex = std.Mutex;
const Allocator = std.mem.Allocator;
usingnamespace @import( "sim.zig" );
usingnamespace @import( "util/axis.zig" );
usingnamespace @import( "util/drag.zig" );
usingnamespace @import( "util/glz.zig" );
usingnamespace @import( "util/gtkz.zig" );
usingnamespace @import( "util/misc.zig" );
usingnamespace @import( "util/paint.zig" );
usingnamespace @import( "drawarrays.zig" );
usingnamespace @import( "dots.zig" );

// TODO: Understand why this magic makes async/await work sensibly
pub const io_mode = .evented;

const SimListenerImpl = struct {
    // Thread-safe
    allocator: *Allocator,

    // Accessed only on GTK thread
    paintable: *DotsPaintable,
    glArea: *GtkWidget,

    // Protected by mutex
    mutex: Mutex = Mutex {},
    pendingCoords: ?[]GLfloat = null,

    listener: SimListener = SimListener {
        .setParticleCoordsFn = setParticleCoords,
    },

    /// Called on simulator thread
    fn setParticleCoords( listener: *SimListener, xs: []const f64 ) !void {
        const self = @fieldParentPtr( SimListenerImpl, "listener", listener );

        var newCoords = try self.allocator.alloc( GLfloat, xs.len );
        for ( xs ) |x, c| {
            newCoords[c] = @floatCast( GLfloat, x );
        }

        var oldCoords = sync: {
            const held = self.mutex.acquire( );
            defer held.release( );
            var oldCoords = self.pendingCoords;
            self.pendingCoords = newCoords;
            break :sync oldCoords;
        };

        if ( oldCoords != null ) {
            // We could recycle old coord slices, but it would require either
            // moving the copy loop inside the mutex block, or complicating
            // the mutex patern ... neither of which seems worth the trouble
            self.allocator.free( oldCoords.? );
        }

        // We never call g_source_remove(), so the callback could stay in
        // the queue indefinitely, which feels sloppy ... however, calling
        // g_source_remove() later is no good, because the callback might
        // already have run (and removed itself by returning REMOVE)
        _ = g_timeout_add( 0, @ptrCast( GSourceFunc, updatePaintable ), self );
    }

    /// Called on GTK thread
    fn updatePaintable( self_: *SimListenerImpl ) callconv(.C) guint {
        struct {
            fn run( self: *SimListenerImpl ) !void {
                const held = self.mutex.acquire( );
                defer held.release( );
                if ( self.pendingCoords != null ) {
                    const newCoords = self.pendingCoords.?;
                    defer self.pendingCoords = null;
                    try self.paintable.coords.resize( newCoords.len );
                    try self.paintable.coords.replaceRange( 0, newCoords.len, newCoords );
                    self.paintable.coordsModified = true;
                }
                gtk_widget_queue_draw( self.glArea );
            }
        }.run( self_ ) catch |e| {
            std.debug.warn( "Failed to update dots: {}\n", .{ e } );
            if ( @errorReturnTrace( ) ) |trace| {
                std.debug.dumpStackTrace( trace.* );
            }
        };
        return G_SOURCE_REMOVE;
    }

    /// Called on GTK thread, after simulator thread has exited
    pub fn deinit( self: *SimListenerImpl ) void {
        var oldCoords = sync: {
            const held = self.mutex.acquire( );
            defer held.release( );
            var oldCoords = self.pendingCoords;
            self.pendingCoords = null;
            break :sync oldCoords;
        };

        if ( oldCoords != null ) {
            self.allocator.free( oldCoords.? );
        }
    }
};

pub fn main( ) !void {
    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};
    const allocator = &gpa.allocator;

    const N = 2;
    const P = 3;
    const simConfig = SimConfig( N, P ) {
        .updateInterval_MILLIS = 15,
        .timestep = 500e-9,
        .xLimits = [N]Interval {
            Interval.initStartEnd( -8, 8 ),
            Interval.initStartEnd( -6, 6 ),
        },
        .particles = [P]Particle(N) {
            Particle(N).init( 1, [N]f64{ -6.0, -3.0 }, [N]f64{ 7.0, 13.0 } ),
            Particle(N).init( 1, [N]f64{ -6.5, -3.0 }, [N]f64{ 2.0, 14.0 } ),
            Particle(N).init( 1, [N]f64{ -6.1, -3.2 }, [N]f64{ 5.0,  6.0 } ),
        },
    };

    var args = try ProcessArgs.init( allocator );
    defer args.deinit( );
    gtk_init( &args.argc, &args.argv );

    const glArea = gtk_gl_area_new( );
    gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, glArea ), 3, 2 );
    gtk_widget_set_events( glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_KEY_PRESS_MASK );
    gtk_widget_set_can_focus( glArea, 1 );

    const window = gtk_window_new( .GTK_WINDOW_TOPLEVEL );
    gtk_container_add( @ptrCast( *GtkContainer, window ), glArea );
    gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Sproingy" );
    gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 480, 360 );

    var axis0 = Axis.initBounds( -8.4, 8.4, 1 );
    var axis1 = Axis.initBounds( -6.4, 6.4, 1 );
    var axes = [N]*Axis { &axis0, &axis1 };

    // TODO: Replace with aspect-ratio locking
    var axesScale = inf( f64 );
    for ( axes ) |axis| {
        axesScale = min( axesScale, axis.scale );
    }
    for ( axes ) |axis| {
        axis.scale = axesScale;
    }

    var bgPaintable = ClearPaintable.init( "bg", GL_COLOR_BUFFER_BIT );
    bgPaintable.rgba = [_]GLfloat { 0.4, 0.4, 0.4, 1.0 };

    var boxPaintable = DrawArraysPaintable.init( "box", axes, GL_TRIANGLE_STRIP, allocator );
    defer boxPaintable.deinit( );
    boxPaintable.rgba = [_]GLfloat { 0.0, 0.0, 0.0, 1.0 };
    const xMin0 = @floatCast( GLfloat, simConfig.xLimits[0].lowerBound( ).coord );
    const xMax0 = @floatCast( GLfloat, simConfig.xLimits[0].upperBound( ).coord );
    const xMin1 = @floatCast( GLfloat, simConfig.xLimits[1].lowerBound( ).coord );
    const xMax1 = @floatCast( GLfloat, simConfig.xLimits[1].upperBound( ).coord );
    var boxCoords = [_]GLfloat { xMin0,xMax1, xMin0,xMin1, xMax0,xMax1, xMax0,xMin1 };
    try boxPaintable.coords.appendSlice( &boxCoords );

    var dotsPaintable = DotsPaintable.init( "dots", axes, allocator );
    defer dotsPaintable.deinit( );
    dotsPaintable.rgba = [_]GLfloat { 1.0, 0.0, 0.0, 1.0 };

    var rootPaintable = MultiPaintable.init( "root", allocator );
    try rootPaintable.childPainters.append( &bgPaintable.painter );
    try rootPaintable.childPainters.append( &boxPaintable.painter );
    try rootPaintable.childPainters.append( &dotsPaintable.painter );

    var axisUpdatingHandler = AxisUpdatingHandler(N).init( axes, [N]u1 { 0, 1 } );
    _ = try gtkzConnectHandler( glArea, "render", AxisUpdatingHandler(2).onRender, &axisUpdatingHandler );
    _ = try gtkzConnectHandler( glArea, "scroll-event", AxisUpdatingHandler(2).onMouseWheel, &axisUpdatingHandler );

    const painters = [_]*Painter { &rootPaintable.painter };
    var paintingHandler = PaintingHandler.init( &painters );
    _ = try gtkzConnectHandler( glArea, "render", PaintingHandler.onRender, &paintingHandler );
    _ = try gtkzConnectHandler( window, "delete-event", PaintingHandler.onWindowClosing, &paintingHandler );

    var axisDraggable = AxisDraggable(N).init( axes, [N]u1 { 0, 1 } );
    const draggers = [_]*Dragger { &axisDraggable.dragger };
    var draggingHandler = DraggingHandler.init( glArea, &draggers );
    _ = try gtkzConnectHandler( glArea, "button-press-event", DraggingHandler.onMouseDown, &draggingHandler );
    _ = try gtkzConnectHandler( glArea, "motion-notify-event", DraggingHandler.onMouseMove, &draggingHandler );
    _ = try gtkzConnectHandler( glArea, "button-release-event", DraggingHandler.onMouseUp, &draggingHandler );

    const closeKeys = [_]guint { GDK_KEY_Escape };
    var closeKeysHandler = CloseKeysHandler.init( &closeKeys );
    _ = try gtkzConnectHandler( glArea, "key-press-event", CloseKeysHandler.onKeyDown, &closeKeysHandler );

    var quittingHandler = QuittingHandler.init( );
    _ = try gtkzConnectHandler( window, "delete-event", QuittingHandler.onWindowClosing, &quittingHandler );

    var simListener = SimListenerImpl {
        .allocator = allocator,
        .paintable = &dotsPaintable,
        .glArea = glArea,
    };
    defer simListener.deinit( );

    var simRunning = Atomic( bool ).init( true );
    var simFrame = async runSimulation( N, P, &simConfig, &simListener.listener, &simRunning );

    gtk_widget_show_all( window );
    gtk_main( );

    // Main-thread stack needs to stay valid until sim-thread exits
    simRunning.set( false );
    try await simFrame;
}
