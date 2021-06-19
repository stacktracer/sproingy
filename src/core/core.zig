const std = @import( "std" );
const nan = std.math.nan;
const isNan = std.math.isNan;
usingnamespace @import( "util.zig" );

pub const Axis = struct {
    tieFrac: f64,
    tieCoord: f64,
    scale: f64,

    /// Size may be Nan if this axis isn't visible yet!
    viewport_PX: Interval,

    /// If size is Nan, this will be used instead.
    defaultSpan: f64,

    /// If this axis will be managed by an AxisUpdatingHandler, the
    /// absolute value of initialScale doesn't matter. What matters
    /// is the ratio of initialScale to the initialScales of other
    /// axes managed by the same AxisUpdatingHandler.
    pub fn initBounds( start: f64, end: f64, initialScale: f64 ) Axis {
        const tieFrac = 0.5;
        return Axis {
            .tieFrac = tieFrac,
            .tieCoord = start + tieFrac*( end - start ),
            .scale = initialScale,
            .viewport_PX = Interval.init( 0, nan( f64 ) ),
            .defaultSpan = end - start,
        };
    }

    pub fn span( self: *const Axis ) f64 {
        return self.spanForScale( self.scale );
    }

    fn spanForScale( self: *const Axis, scale: f64 ) f64 {
        const size_PX = self.viewport_PX.span;
        if ( isNan( size_PX ) ) {
            return self.defaultSpan;
        }
        else {
            return ( size_PX / scale );
        }
    }

    pub fn bounds( self: *const Axis ) Interval {
        const span_ = self.span( );
        const start = self.tieCoord - self.tieFrac*span_;
        return Interval.init( start, span_ );
    }

    pub fn set( self: *Axis, frac: f64, coord: f64, scale: f64 ) void {
        // TODO: Apply constraints
        const span_ = self.spanForScale( scale );
        self.tieCoord = coord + ( self.tieFrac - frac )*span_;
        self.scale = scale;
    }
};

pub fn axisBounds( comptime N: usize, axes: [N]*const Axis ) [N]Interval {
    var bounds = @as( [N]Interval, undefined );
    for ( axes ) |axis, n| {
        bounds[n] = axis.bounds( );
    }
    return bounds;
}

pub fn AxisDraggable( comptime N: usize ) type {
    return struct {
        const Self = @This();

        axes: [N]*Axis,
        screenCoordIndices: [N]u1,
        grabCoords: [N]f64,

        dragger: Dragger = .{
            .canHandlePressFn = canHandlePress,
            .handlePressFn = handlePress,
            .handleDragFn = handleDrag,
            .handleReleaseFn = handleRelease,
        },

        pub fn init( axes: [N]*Axis, screenCoordIndices: [N]u1 ) Self {
            return Self {
                .axes = axes,
                .screenCoordIndices = screenCoordIndices,
                .grabCoords = undefined,
            };
        }

        fn canHandlePress( dragger: *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) bool {
            const self = @fieldParentPtr( Self, "dragger", dragger );
            for ( self.axes ) |axis, n| {
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[ self.screenCoordIndices[n] ] );
                if ( mouseFrac < 0.0 or mouseFrac > 1.0 ) {
                    return false;
                }
            }
            return true;
        }

        fn handlePress( dragger: *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) void {
            const self = @fieldParentPtr( Self, "dragger", dragger );
            for ( self.axes ) |axis, n| {
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[ self.screenCoordIndices[n] ] );
                self.grabCoords[n] = axis.bounds( ).fracToValue( mouseFrac );
            }
        }

        fn handleDrag( dragger: *Dragger, context: DraggerContext, mouse_PX: [2]f64 ) void {
            const self = @fieldParentPtr( Self, "dragger", dragger );
            for ( self.axes ) |axis, n| {
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[ self.screenCoordIndices[n] ] );
                axis.set( mouseFrac, self.grabCoords[n], axis.scale );
            }
        }

        fn handleRelease( dragger: *Dragger, context: DraggerContext, mouse_PX: [2]f64 ) void {
            const self = @fieldParentPtr( Self, "dragger", dragger );
            for ( self.axes ) |axis, n| {
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[ self.screenCoordIndices[n] ] );
                axis.set( mouseFrac, self.grabCoords[n], axis.scale );
            }
        }
    };
}

pub const DraggerContext = struct {
    lpxToPx: f64,
};

pub const Dragger = struct {
    canHandlePressFn: fn ( self: *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) bool,
    handlePressFn: fn ( self: *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) void,
    handleDragFn: fn ( self: *Dragger, context: DraggerContext, mouse_PX: [2]f64 ) void,
    handleReleaseFn: fn ( self: *Dragger, context: DraggerContext, mouse_PX: [2]f64 ) void,

    pub fn canHandlePress( self: *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) bool {
        return self.canHandlePressFn( self, context, mouse_PX, clickCount );
    }

    pub fn handlePress( self: *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) void {
        self.handlePressFn( self, context, mouse_PX, clickCount );
    }

    pub fn handleDrag( self: *Dragger, context: DraggerContext, mouse_PX: [2]f64 ) void {
        self.handleDragFn( self, context, mouse_PX );
    }

    pub fn handleRelease( self: *Dragger, context: DraggerContext, mouse_PX: [2]f64 ) void {
        self.handleReleaseFn( self, context, mouse_PX );
    }
};

pub const PainterContext = struct {
    viewport_PX: [2]Interval,
    lpxToPx: f64,
};

pub const Painter = struct {
    name: []const u8,

    glResourcesAreSet: bool = false,

    /// Called while the GL context is current, and before the first paint.
    glInitFn: fn ( self: *Painter, pc: *const PainterContext ) anyerror!void,

    // Called while the GL context is current.
    glPaintFn: fn ( self: *Painter, pc: *const PainterContext ) anyerror!void,

    // Called while the GL context is current.
    glDeinitFn: fn ( self: *Painter ) void,

    pub fn glPaint( self: *Painter, pc: *const PainterContext ) !void {
        if ( !self.glResourcesAreSet ) {
            try self.glInitFn( self, pc );
            self.glResourcesAreSet = true;
        }
        return self.glPaintFn( self, pc );
    }

    pub fn glDeinit( self: *Painter ) void {
        if ( self.glResourcesAreSet ) {
            self.glDeinitFn( self );
            self.glResourcesAreSet = false;
        }
    }
};
