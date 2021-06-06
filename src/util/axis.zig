const std = @import( "std" );
const min = std.math.min;
const pow = std.math.pow;
const inf = std.math.inf;
const nan = std.math.nan;
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

    pub fn init( start: f64, end: f64, size_PX: f64 ) Axis {
        const span = end - start;
        const tieFrac = 0.5;
        return Axis {
            .viewport_PX = Interval.init( 0, size_PX ),
            .tieFrac = tieFrac,
            .tieCoord = start + tieFrac*span,
            .scale = size_PX / span,
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

        // Axis scales and viewport sizes from the most recent time
        // one of their scales was explicitly changed; used below
        // to implicitly rescale when widget size or hidpi scaling
        // changes
        sizesFromLastRealRescale_PX: [n]f64,
        scalesFromLastRealRescale: [n]f64,

        // Axis scales, explicit or not, from the most recent render
        scalesFromLastRender: [n]f64,

        pub fn init( axes: [n]*Axis, mouseCoordIndices: [n]u1, forceRescale: bool ) Self {
            return Self {
                .axes = axes,
                .mouseCoordIndices = mouseCoordIndices,
                .sizesFromLastRealRescale_PX = axisSizes_PX( axes ),
                .scalesFromLastRealRescale = axisScales( axes ),
                .scalesFromLastRender = if ( forceRescale ) [1]f64 { nan( f64 ) } ** n else axisScales( axes ),
            };
        }

        pub fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, self: *Self ) callconv(.C) gboolean {
            const viewport_PX = glzGetViewport_PX( );
            for ( self.mouseCoordIndices ) |m, i| {
                const axis = self.axes[i];
                axis.viewport_PX = viewport_PX[m];
            }

            var isRealRescale = false;
            for ( self.axes ) |axis, i| {
                if ( axis.scale != self.scalesFromLastRender[i] ) {
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
                for ( self.axes ) |axis, i| {
                    const maxRescaleFactor = axis.viewport_PX.span / self.sizesFromLastRealRescale_PX[i];
                    autoRescaleFactor = min( autoRescaleFactor, maxRescaleFactor );
                }
                for ( self.axes ) |axis, i| {
                    axis.scale = autoRescaleFactor * self.scalesFromLastRealRescale[i];
                }
            }

            self.scalesFromLastRender = axisScales( self.axes );

            return 0;
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
