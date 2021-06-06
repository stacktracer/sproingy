const std = @import( "std" );
const min = std.math.min;
const pow = std.math.pow;
const inf = std.math.inf;
usingnamespace @import( "gtkz.zig" );
usingnamespace @import( "glz.zig" );
usingnamespace @import( "drag.zig" );

pub const Interval = struct {
    /// Inclusive start point.
    start: f64,

    /// Difference between start and exclusive end.
    span: f64,

    pub fn init( start: f64, span: f64 ) Interval {
        return Interval {
            .start = start,
            .span = span,
        };
    }

    pub fn set( self: *Interval, start: f64, span: f64 ) void {
        self.start = start;
        self.span = span;
    }

    pub fn valueToFrac( self: *const Interval, value: f64 ) f64 {
        return ( ( value - self.start ) / self.span );
    }

    pub fn fracToValue( self: *const Interval, frac: f64 ) f64 {
        return ( self.start + frac*self.span );
    }
};

pub const Axis = struct {
    viewport_PX: Interval,
    tieFrac: f64,
    tieCoord: f64,
    scale: f64,

    pub fn init( start: f64, end: f64 ) Axis {
        const viewport_PX = Interval.init( 0, 1000 );
        const span = end - start;
        const tieFrac = 0.5;
        return Axis {
            .viewport_PX = viewport_PX,
            .tieFrac = tieFrac,
            .tieCoord = start + tieFrac*span,
            .scale = viewport_PX.span / span,
        };
    }

    pub fn bounds( self: *const Axis ) Interval {
        const span = self.viewport_PX.span / self.scale;
        const start = self.tieCoord - self.tieFrac*span;
        return Interval.init( start, span );
    }

    pub fn set( self: *Axis, frac: f64, coord: f64, scale: f64 ) void {
        // TODO: Apply constraints
        const span = self.viewport_PX.span / scale;
        self.tieCoord = coord + ( self.tieFrac - frac )*span;
        self.scale = scale;
    }
};

pub fn axisBounds( comptime n: usize, axes: [n]*const Axis ) [n]Interval {
    var bounds = @as( [n]Interval, undefined );
    for ( axes ) |axis, i| {
        bounds[i] = axis.bounds( );
    }
    return bounds;
}

pub fn AxisDraggable( comptime n: usize ) type {
    return struct {
        const Self = @This();

        axes: [n]*Axis,
        mouseCoordIndices: [n]u1,
        grabCoords: [n]f64,

        dragger: Dragger = .{
            .canHandlePressFn = canHandlePress,
            .handlePressFn = handlePress,
            .handleDragFn = handleDrag,
            .handleReleaseFn = handleRelease,
        },

        pub fn init( axes: [n]*Axis, mouseCoordIndices: [n]u1 ) Self {
            return Self {
                .axes = axes,
                .mouseCoordIndices = mouseCoordIndices,
                .grabCoords = undefined,
            };
        }

        fn canHandlePress( dragger: *Dragger, mouse_PX: [2]f64 ) bool {
            const self = @fieldParentPtr( Self, "dragger", dragger );
            for ( self.mouseCoordIndices ) |m, i| {
                const axis = self.axes[i];
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[m] );
                if ( mouseFrac < 0.0 or mouseFrac > 1.0 ) {
                    return false;
                }
            }
            return true;
        }

        fn handlePress( dragger: *Dragger, mouse_PX: [2]f64 ) void {
            const self = @fieldParentPtr( Self, "dragger", dragger );
            for ( self.mouseCoordIndices ) |m, i| {
                const axis = self.axes[i];
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[m] );
                self.grabCoords[i] = axis.bounds( ).fracToValue( mouseFrac );
            }
        }

        fn handleDrag( dragger: *Dragger, mouse_PX: [2]f64 ) void {
            const self = @fieldParentPtr( Self, "dragger", dragger );
            for ( self.mouseCoordIndices ) |m, i| {
                const axis = self.axes[i];
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[m] );
                axis.set( mouseFrac, self.grabCoords[i], axis.scale );
            }
        }

        fn handleRelease( dragger: *Dragger, mouse_PX: [2]f64 ) void {
            const self = @fieldParentPtr( Self, "dragger", dragger );
            for ( self.mouseCoordIndices ) |m, i| {
                const axis = self.axes[i];
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[m] );
                axis.set( mouseFrac, self.grabCoords[i], axis.scale );
            }
        }
    };
}

pub fn AxisUpdatingHandler( comptime n: usize ) type {
    return struct {
        const Self = @This();

        axes: [n]*Axis,
        mouseCoordIndices: [n]u1,

        // Axis scales and viewport sizes from the last time we're
        // sure there wasn't a viewport resize in progress
        sizesBeforeResize_PX: [n]f64,
        scalesBeforeResize: [n]f64,
        resizeInProgress: bool,

        pub fn init( axes: [n]*Axis, mouseCoordIndices: [n]u1 ) Self {
            return Self {
                .axes = axes,
                .mouseCoordIndices = mouseCoordIndices,
                .sizesBeforeResize_PX = axisSizes_PX( axes ),
                .scalesBeforeResize = axisScales( axes ),
                .resizeInProgress = false,
            };
        }

        fn axisSizes_PX( axes: [n]*const Axis ) [n]f64 {
            var sizes_PX = @as( [n]f64, undefined );
            for ( axes ) |axis, i| {
                sizes_PX[i] = axis.viewport_PX.span;
            }
            return sizes_PX;
        }

        fn axisScales( axes: [n]*const Axis ) [n]f64 {
            var scales = @as( [n]f64, undefined );
            for ( axes ) |axis, i| {
                scales[i] = axis.scale;
            }
            return scales;
        }

        pub fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, self: *Self ) callconv(.C) gboolean {
            const viewport_PX = glzGetViewport_PX( );
            for ( self.mouseCoordIndices ) |m, i| {
                const axis = self.axes[i];
                axis.viewport_PX = viewport_PX[m];
            }

            // If we're not already in the midst of a resize, check whether
            // one has started since the last render
            if ( !self.resizeInProgress ) {
                for ( self.axes ) |axis, i| {
                    if ( axis.viewport_PX.span != self.sizesBeforeResize_PX[i] ) {
                        self.resizeInProgress = true;
                        break;
                    }
                }
            }

            // If the axis viewports are changing size (due to a widget resize
            // or a hidpi scaling change), adjust the axis *scales* so that the
            // axis *bounds* stay as close as possible to what they were before
            // the resize started (assumes there won't be legit scale changes
            // during a viewport resize, which is a pretty safe assumption)
            if ( self.resizeInProgress ) {
                var rescaleFactor = inf( f64 );
                for ( self.axes ) |axis, i| {
                    const prefRescaleFactor = axis.viewport_PX.span / self.sizesBeforeResize_PX[i];
                    rescaleFactor = min( rescaleFactor, prefRescaleFactor );
                }
                for ( self.axes ) |axis, i| {
                    axis.scale = rescaleFactor * self.scalesBeforeResize[i];
                }
            }

            return 0;
        }

        pub fn onNotResizing( widget: *GtkWidget, ev: *GdkEvent, self: *Self ) callconv(.C) gboolean {
            self.sizesBeforeResize_PX = axisSizes_PX( self.axes );
            self.scalesBeforeResize = axisScales( self.axes );
            self.resizeInProgress = false;
            return 0;
        }

        pub fn onMouseWheel( widget: *GtkWidget, ev: *GdkEventScroll, self: *Self ) callconv(.C) gboolean {
            const zoomStepFactor = 1.12;
            const zoomSteps = glzWheelSteps( ev );
            const zoomFactor = pow( f64, zoomStepFactor, -zoomSteps );
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            for ( self.mouseCoordIndices ) |m, i| {
                const axis = self.axes[i];
                const mouseFrac = axis.viewport_PX.valueToFrac( mouse_PX[m] );
                const mouseCoord = axis.bounds( ).fracToValue( mouseFrac );
                const scale = zoomFactor*axis.scale;
                axis.set( mouseFrac, mouseCoord, scale );
            }
            gtk_widget_queue_draw( widget );

            return 1;
        }
    };
}
