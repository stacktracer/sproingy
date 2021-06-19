const std = @import( "std" );
const min = std.math.min;
const pow = std.math.pow;
const inf = std.math.inf;
const isNan = std.math.isNan;
usingnamespace @import( "util.zig" );
usingnamespace @import( "core.zig" );
usingnamespace @import( "glz.zig" );
usingnamespace @import( "gtkz.zig" );

pub fn AxisUpdatingHandler( comptime N: usize ) type {
    return struct {
        const Self = @This();

        axes: [N]*Axis,
        screenCoordIndices: [N]u1,

        // Axis scales and viewport sizes from the most recent time
        // one of their scales was explicitly changed; used below
        // to implicitly rescale when widget size or hidpi scaling
        // changes
        sizesFromLastRealRescale_PX: [N]f64,
        scalesFromLastRealRescale: [N]f64,

        // Axis scales, explicit or not, from the most recent render
        scalesFromLastRender: [N]f64,

        pub fn init( axes: [N]*Axis, screenCoordIndices: [N]u1 ) Self {
            return Self {
                .axes = axes,
                .screenCoordIndices = screenCoordIndices,
                .sizesFromLastRealRescale_PX = axisSizes_PX( axes ),
                .scalesFromLastRealRescale = axisScales( axes ),
                .scalesFromLastRender = axisScales( axes ),
            };
        }

        pub fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, self: *Self ) callconv(.C) gboolean {
            const viewport_PX = glzGetViewport_PX( );
            for ( self.axes ) |axis, n| {
                axis.viewport_PX = viewport_PX[ self.screenCoordIndices[n] ];
            }

            var isRealRescale = false;
            for ( self.axes ) |axis, n| {
                if ( axis.scale != self.scalesFromLastRender[n] ) {
                    isRealRescale = true;
                    break;
                }
            }

            if ( isRealRescale ) {
                self.sizesFromLastRealRescale_PX = axisSizes_PX( self.axes );
                self.scalesFromLastRealRescale = axisScales( self.axes );
            }
            else {
                // Auto-adjust axis *scales* so that the axis *bounds* stay as
                // close as possible to what they were the last time there was
                // a "real" scale change
                var autoRescaleFactor = inf( f64 );
                for ( self.axes ) |axis, n| {
                    // If this is the first time this axis has had a valid size,
                    // init its sizeFromLastRealRescale based on its defaultSpan
                    if ( isNan( self.sizesFromLastRealRescale_PX[n] ) ) {
                        const initialRescaleFactor = axis.span( ) / axis.defaultSpan;
                        self.sizesFromLastRealRescale_PX[n] = axis.viewport_PX.span / initialRescaleFactor;
                    }

                    // The highest factor we can multiply this axis scale by
                    // and still keep its previous bounds within its viewport
                    const maxRescaleFactor = axis.viewport_PX.span / self.sizesFromLastRealRescale_PX[n];

                    // We will rescale all axes by a single factor that keeps
                    // all their previous bounds within their viewports
                    autoRescaleFactor = min( autoRescaleFactor, maxRescaleFactor );
                }

                // Rescale all axes by a single factor
                for ( self.axes ) |axis, n| {
                    axis.scale = autoRescaleFactor * self.scalesFromLastRealRescale[n];
                }
            }

            self.scalesFromLastRender = axisScales( self.axes );

            return 0;
        }

        fn axisSizes_PX( axes: [N]*const Axis ) [N]f64 {
            var sizes_PX = @as( [N]f64, undefined );
            for ( axes ) |axis, n| {
                sizes_PX[n] = axis.viewport_PX.span;
            }
            return sizes_PX;
        }

        fn axisScales( axes: [N]*const Axis ) [N]f64 {
            var scales = @as( [N]f64, undefined );
            for ( axes ) |axis, n| {
                scales[n] = axis.scale;
            }
            return scales;
        }

        pub fn onMouseWheel( widget: *GtkWidget, ev: *GdkEventScroll, self: *Self ) callconv(.C) gboolean {
            const zoomStepFactor = 1.12;
            const zoomSteps = gtkzWheelSteps( ev );
            const zoomFactor = pow( f64, zoomStepFactor, -zoomSteps );
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            for ( self.axes ) |axis, n| {
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[ self.screenCoordIndices[n] ] );
                const mouseCoord = axis.bounds( ).fracToValue( mouseFrac );
                const scale = zoomFactor*axis.scale;
                axis.set( mouseFrac, mouseCoord, scale );
            }
            gtk_widget_queue_draw( widget );

            return 1;
        }
    };
}

pub const PaintingHandler = struct {
    painters: []const *Painter,

    pub fn init( painters: []const *Painter ) PaintingHandler {
        return PaintingHandler {
            .painters = painters,
        };
    }

    pub fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, self: *PaintingHandler ) callconv(.C) gboolean {
        const pc = PainterContext {
            .viewport_PX = glzGetViewport_PX( ),
            .lpxToPx = gtkzScaleFactor( @ptrCast( *GtkWidget, glArea ) ),
        };
        for ( self.painters ) |painter| {
            painter.glPaint( &pc ) catch |e| {
                std.debug.warn( "Failed to paint: painter = {s}, error = {}\n", .{ painter.name, e } );
            };
        }
        return 0;
    }

    pub fn onWindowClosing( window: *GtkWindow, ev: *GdkEvent, self: *PaintingHandler ) callconv(.C) gboolean {
        if ( glzHasCurrentContext( ) ) {
            for ( self.painters ) |painter| {
                painter.glDeinit( );
            }
        }
        else {
            std.debug.warn( "Failed to deinit painters; no current GL Context\n", .{} );
        }
        return 0;
    }
};

pub const DraggingHandler = struct {
    draggers: []const *Dragger,
    activeDragger: ?*Dragger = null,

    pub fn init( widget: gpointer, draggers: []const *Dragger ) !DraggingHandler {
        return DraggingHandler {
            .draggers = draggers,
        };
    }

    pub fn onMouseDown( widget: *GtkWidget, ev: *GdkEventButton, self: *DraggingHandler ) callconv(.C) gboolean {
        const clickCount = gtkzClickCount( ev );
        if ( ev.button == 1 and clickCount >= 1 ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            const context = DraggerContext {
                .lpxToPx = gtkzScaleFactor( widget ),
            };
            const newDragger = findDragger( self.draggers, context, mouse_PX, clickCount );
            if ( newDragger != null and newDragger != self.activeDragger ) {
                if ( self.activeDragger != null ) {
                    self.activeDragger.?.handleRelease( context, mouse_PX );
                }
                self.activeDragger = newDragger;
                self.activeDragger.?.handlePress( context, mouse_PX, clickCount );
                gtk_widget_queue_draw( widget );
            }
        }
        return 1;
    }

    pub fn onMouseMove( widget: *GtkWidget, ev: *GdkEventMotion, self: *DraggingHandler ) callconv(.C) gboolean {
        if ( self.activeDragger != null ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            const context = DraggerContext {
                .lpxToPx = gtkzScaleFactor( widget ),
            };
            self.activeDragger.?.handleDrag( context, mouse_PX );
            gtk_widget_queue_draw( widget );
        }
        return 1;
    }

    pub fn onMouseUp( widget: *GtkWidget, ev: *GdkEventButton, self: *DraggingHandler ) callconv(.C) gboolean {
        if ( self.activeDragger != null and ev.button == 1 ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            const context = DraggerContext {
                .lpxToPx = gtkzScaleFactor( widget ),
            };
            self.activeDragger.?.handleRelease( context, mouse_PX );
            self.activeDragger = null;
            gtk_widget_queue_draw( widget );
        }
        return 1;
    }

    fn findDragger( draggers: []const *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) ?*Dragger {
        for ( draggers ) |dragger| {
            if ( dragger.canHandlePress( context, mouse_PX, clickCount ) ) {
                return dragger;
            }
        }
        return null;
    }
};

pub const MultiPaintable = struct {
    childPainters: ArrayList( *Painter ),
    painter: Painter,

    pub fn init( name: []const u8, allocator: *Allocator ) MultiPaintable {
        return MultiPaintable {
            .childPainters = ArrayList( *Painter ).init( allocator ),
            .painter = Painter {
                .name = name,
                .glInitFn = glInit,
                .glPaintFn = glPaint,
                .glDeinitFn = glDeinit,
            },
        };
    }

    fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
        // Do nothing
    }

    fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            childPainter.glPaint( pc ) catch |e| {
                std.debug.warn( "Failed to paint: painter = {s}, error = {}\n", .{ childPainter.name, e } );
                if ( @errorReturnTrace( ) ) |trace| {
                    std.debug.dumpStackTrace( trace.* );
                }
            };
        }
    }

    fn glDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            childPainter.glDeinit( );
        }
        self.childPainters.items.len = 0;
    }

    pub fn deinit( self: *MultiPaintable ) void {
        for ( self.childPainters.items ) |childPainter| {
            if ( childPainter.glResourcesAreSet ) {
                std.debug.warn( "glDeinit was never called for painter \"{}\"\n", .{ childPainter.name } );
            }
        }
        self.childPainters.deinit( );
    }
};

pub const ClearPaintable = struct {
    mask: GLbitfield,
    rgba: [4]GLfloat,
    depth: GLfloat,
    stencil: GLint,
    painter: Painter,

    pub fn init( name: []const u8, mask: GLbitfield ) ClearPaintable {
        return ClearPaintable {
            .mask = mask,
            .rgba = [_]GLfloat { 0.0, 0.0, 0.0, 0.0 },
            .depth = 1.0,
            .stencil = 0,
            .painter = Painter {
                .name = name,
                .glInitFn = glInit,
                .glPaintFn = glPaint,
                .glDeinitFn = glDeinit,
            },
        };
    }

    fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
        // Do nothing
    }

    fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
        const self = @fieldParentPtr( ClearPaintable, "painter", painter );
        if ( self.mask & GL_COLOR_BUFFER_BIT != 0 ) {
            glClearColor( self.rgba[0], self.rgba[1], self.rgba[2], self.rgba[3] );
        }
        if ( self.mask & GL_DEPTH_BUFFER_BIT != 0 ) {
            glClearDepthf( self.depth );
        }
        if ( self.mask & GL_STENCIL_BUFFER_BIT != 0 ) {
            glClearStencil( self.stencil );
        }
        glClear( self.mask );
    }

    fn glDeinit( painter: *Painter ) void {
        // Do nothing
    }
};
