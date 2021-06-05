const std = @import( "std" );
const pow = std.math.pow;
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
    tieFrac: f64 = 0.5,
    tieCoord: f64 = 0.0,
    scale: f64,

    pub fn init( viewport_PX: Interval, scale: f64 ) Axis {
        return Axis {
            .viewport_PX = viewport_PX,
            .scale = scale,
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
        prevScaleFactor: f64,

        pub fn init( axes: [n]*Axis, mouseCoordIndices: [n]u1 ) Self {
            return Self {
                .axes = axes,
                .mouseCoordIndices = mouseCoordIndices,
                .prevScaleFactor = 1.0,
            };
        }

        pub fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, self: *Self ) callconv(.C) gboolean {
            const oldScaleFactor = self.prevScaleFactor;
            const newScaleFactor = gtkzScaleFactor( @ptrCast( *GtkWidget, glArea ) );
            if ( newScaleFactor != oldScaleFactor ) {
                const scaleChangeFactor = newScaleFactor / oldScaleFactor;
                for ( self.axes ) |axis, i| {
                    axis.scale *= scaleChangeFactor;
                }
                self.prevScaleFactor = newScaleFactor;
            }

            const viewport_PX = glzGetViewport_PX( );
            for ( self.axes ) |axis, i| {
                axis.viewport_PX = viewport_PX[i];
            }

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
