const std = @import( "std" );
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

const SimControlImpl = struct {
    // Thread-safe
    allocator: *Allocator,

    // Accessed only on GTK thread
    boxPaintable: *DrawArraysPaintable,
    dotsPaintable: *DotsPaintable,
    glArea: *GtkWidget,

    // Protected by mutex
    mutex: Mutex = Mutex {},
    pendingBoxCoords: ?[]GLfloat = null,
    pendingDotCoords: ?[]GLfloat = null,

    simControl: SimControl = SimControl {
        .setBoxFn = setBox,
        .isRunningFn = isRunning,
        .getUpdateIntervalFn_MILLIS = getUpdateInterval_MILLIS,
        .setDotsFn = setDots,
    },

    /// Runs on simulator thread
    fn setBox( simControl: *SimControl, boxCoords: []const f64 ) !void {
        const self = @fieldParentPtr( SimControlImpl, "simControl", simControl );

        var newCoords = try self.allocator.alloc( GLfloat, boxCoords.len );
        for ( boxCoords ) |coord,i| {
            newCoords[ i ] = @floatCast( GLfloat, coord );
        }

        var oldCoords = sync: {
            const held = self.mutex.acquire( );
            defer held.release( );
            var oldCoords = self.pendingBoxCoords;
            self.pendingBoxCoords = newCoords;
            break :sync oldCoords;
        };

        if ( oldCoords != null ) {
            // TODO: Recycle?
            self.allocator.free( oldCoords.? );
        }

        // FIXME: Call g_source_remove() somewhere
        const source = g_timeout_add( 0, @ptrCast( GSourceFunc, doUpdateBox ), self );
    }

    /// Runs on GTK thread
    fn doUpdateBox( self_: *SimControlImpl ) callconv(.C) guint {
        struct {
            fn run( self: *SimControlImpl ) !void {
                const held = self.mutex.acquire( );
                defer held.release( );
                if ( self.pendingBoxCoords != null ) {
                    const pendingCoords = self.pendingBoxCoords.?;
                    defer self.pendingBoxCoords = null;
                    try self.boxPaintable.coords.resize( pendingCoords.len );
                    try self.boxPaintable.coords.replaceRange( 0, pendingCoords.len, pendingCoords );
                    self.boxPaintable.coordsModified = true;
                }
                gtk_widget_queue_draw( self.glArea );
            }
        }.run( self_ ) catch |e| {
            std.debug.warn( "Failed to update box: {}\n", .{ e } );
            if ( @errorReturnTrace( ) ) |trace| {
                std.debug.dumpStackTrace( trace.* );
            }
        };
        return G_SOURCE_REMOVE;
    }

    /// Runs on simulator thread
    fn isRunning( simControl: *SimControl ) bool {
        // TODO: Mutations must be thread-safe
        return true;
    }

    /// Runs on simulator thread
    fn getUpdateInterval_MILLIS( simControl: *SimControl ) i64 {
        // TODO: Mutations must be thread-safe
        return 15;
    }

    /// Runs on simulator thread
    fn setDots( simControl: *SimControl, dotCoords: []const f64 ) !void {
        const self = @fieldParentPtr( SimControlImpl, "simControl", simControl );

        var newCoords = try self.allocator.alloc( GLfloat, dotCoords.len );
        for ( dotCoords ) |coord,i| {
            newCoords[ i ] = @floatCast( GLfloat, coord );
        }

        var oldCoords = sync: {
            const held = self.mutex.acquire( );
            defer held.release( );
            var oldCoords = self.pendingDotCoords;
            self.pendingDotCoords = newCoords;
            break :sync oldCoords;
        };

        if ( oldCoords != null ) {
            // TODO: Recycle?
            self.allocator.free( oldCoords.? );
        }

        // FIXME: Call g_source_remove() somewhere
        const source = g_timeout_add( 0, @ptrCast( GSourceFunc, doUpdateDots ), self );
    }

    /// Runs on GTK thread
    fn doUpdateDots( self_: *SimControlImpl ) callconv(.C) guint {
        struct {
            fn run( self: *SimControlImpl ) !void {
                const held = self.mutex.acquire( );
                defer held.release( );
                if ( self.pendingDotCoords != null ) {
                    const pendingCoords = self.pendingDotCoords.?;
                    defer self.pendingDotCoords = null;
                    try self.dotsPaintable.coords.resize( pendingCoords.len );
                    try self.dotsPaintable.coords.replaceRange( 0, pendingCoords.len, pendingCoords );
                    self.dotsPaintable.coordsModified = true;
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

    /// Runs on GTK thread
    pub fn deinit( self: *SimControlImpl ) void {
        var oldCoords = sync: {
            const held = self.mutex.acquire( );
            defer held.release( );
            var oldCoords = self.pendingBoxCoords;
            self.pendingBoxCoords = null;
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

    var rootPaintable = MultiPaintable.init( "root", allocator );
    try rootPaintable.childPainters.append( &bgPaintable.painter );
    try rootPaintable.childPainters.append( &boxPaintable.painter );
    try rootPaintable.childPainters.append( &dotsPaintable.painter );

    const glArea = gtk_gl_area_new( );
    gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, glArea ), 3, 2 );
    gtk_widget_set_events( glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_KEY_PRESS_MASK );
    gtk_widget_set_can_focus( glArea, 1 );

    const window = gtk_window_new( .GTK_WINDOW_TOPLEVEL );
    gtk_container_add( @ptrCast( *GtkContainer, window ), glArea );
    gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Sproingy" );
    gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 480, 360 );

    const axes = [_]*Axis2 { &axis };
    var axisUpdatingHandler = AxisUpdatingHandler.init( &axes );
    _ = try gtkzConnectHandler( glArea, "render", AxisUpdatingHandler.onRender, &axisUpdatingHandler );
    _ = try gtkzConnectHandler( glArea, "scroll-event", AxisUpdatingHandler.onMouseWheel, &axisUpdatingHandler );

    const painters = [_]*Painter { &rootPaintable.painter };
    var paintingHandler = PaintingHandler.init( &painters );
    _ = try gtkzConnectHandler( glArea, "render", PaintingHandler.onRender, &paintingHandler );
    _ = try gtkzConnectHandler( window, "delete-event", PaintingHandler.onWindowClosing, &paintingHandler );

    const draggers = [_]*Dragger { &axis.dragger };
    var draggingHandler = DraggingHandler.init( glArea, &draggers );
    _ = try gtkzConnectHandler( glArea, "button-press-event", DraggingHandler.onMouseDown, &draggingHandler );
    _ = try gtkzConnectHandler( glArea, "motion-notify-event", DraggingHandler.onMouseMove, &draggingHandler );
    _ = try gtkzConnectHandler( glArea, "button-release-event", DraggingHandler.onMouseUp, &draggingHandler );

    const closeKeys = [_]guint { GDK_KEY_Escape };
    var closeKeysHandler = CloseKeysHandler.init( &closeKeys );
    _ = try gtkzConnectHandler( glArea, "key-press-event", CloseKeysHandler.onKeyDown, &closeKeysHandler );

    var quittingHandler = QuittingHandler.init( );
    _ = try gtkzConnectHandler( window, "delete-event", QuittingHandler.onWindowClosing, &quittingHandler );

    var simControlImpl = SimControlImpl {
        .allocator = allocator,
        .boxPaintable = &boxPaintable,
        .dotsPaintable = &dotsPaintable,
        .glArea = glArea,
    };
    defer simControlImpl.deinit( );

    const thread = try std.Thread.spawn( &simControlImpl.simControl, runSimulation );

    gtk_widget_show_all( window );
    gtk_main( );

    // FIXME: simControlImpl gets dropped here, but sim thread could still be using it
}
