const std = @import( "std" );
const nan = std.math.nan;
const u = @import( "util.zig" );
const Vec2 = u.Vec2;
const xy = u.xy;
const Interval1 = u.Interval1;
const Interval2 = u.Interval2;

pub const Dragger = struct {
    handlePressImpl: fn ( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void,
    handleDragImpl: fn ( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void,
    handleReleaseImpl: fn ( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void,

    pub fn handlePress( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        self.handlePressImpl( self, axis, mouseFrac );
    }

    pub fn handleDrag( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        self.handleDragImpl( self, axis, mouseFrac );
    }

    pub fn handleRelease( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        self.handleReleaseImpl( self, axis, mouseFrac );
    }
};

pub const Draggable = struct {
    getDraggerImpl: fn ( self: *Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger,

    pub fn getDragger( self: *Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger {
        return self.getDraggerImpl( self, axis, mouseFrac );
    }
};

pub fn findDragger( draggables: []*Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger {
    for ( draggables ) |draggable| {
        const dragger = draggable.getDragger( axis, mouseFrac );
        if ( dragger != null ) {
            return dragger;
        }
    }
    return null;
}

pub const Axis1 = struct {
    viewport_PX: Interval1,
    tieFrac: f64 = 0.5,
    tieCoord: f64 = 0.0,
    scale: f64 = 1000,

    pub fn create( viewport_PX: Interval1 ) Axis1 {
        return Axis1 {
            .viewport_PX = viewport_PX,
        };
    }

    pub fn pan( self: *Axis1, frac: f64, coord: f64 ) void {
        const scale = self.scale;
        self.set( frac, coord, scale );
    }

    pub fn set( self: *Axis1, frac: f64, coord: f64, scale: f64 ) void {
        // TODO: Apply constraints
        const span = self.viewport_PX.span / scale;
        self.tieCoord = coord + ( self.tieFrac - frac )*span;
        self.scale = scale;
    }

    pub fn getBounds( self: *const Axis1 ) Interval1 {
        const span = self.viewport_PX.span / self.scale;
        const min = self.tieCoord - self.tieFrac*span;
        return Interval1 {
            .min = min,
            .span = span,
        };
    }
};

pub const Axis2Panner = struct {
    dragger: Dragger,
    grabCoord: Vec2,

    /// Pass this same axis to ensuing handleDrag and handleRelease calls
    pub fn handlePress( dragger: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        const self = @fieldParentPtr( Axis2Panner, "dragger", dragger );
        self.grabCoord = axis.getBounds( ).fracToValue( mouseFrac );
    }

    /// Pass the same axis that was passed to the preceding handlePress call
    pub fn handleDrag( dragger: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        const self = @fieldParentPtr( Axis2Panner, "dragger", dragger );
        axis.pan( mouseFrac, self.grabCoord );
    }

    /// Pass the same axis that was passed to the preceding handlePress call
    pub fn handleRelease( dragger: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        const self = @fieldParentPtr( Axis2Panner, "dragger", dragger );
        axis.pan( mouseFrac, self.grabCoord );
    }

    pub fn create( ) Axis2Panner {
        return Axis2Panner {
            .grabCoord = xy( nan( f64 ), nan( f64 ) ),
            .dragger = Dragger {
                .handlePressImpl = handlePress,
                .handleDragImpl = handleDrag,
                .handleReleaseImpl = handleRelease,
            },
        };
    }
};

pub const Axis2 = struct {
    x: Axis1,
    y: Axis1,
    panner: Axis2Panner,
    draggable: Draggable,

    pub fn create( viewport_PX: Interval2 ) Axis2 {
        return Axis2 {
            .x = Axis1.create( viewport_PX.x ),
            .y = Axis1.create( viewport_PX.y ),
            .panner = Axis2Panner.create( ),
            .draggable = Draggable {
                .getDraggerImpl = getDragger,
            },
        };
    }

    fn getDragger( draggable: *Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger {
        const self = @fieldParentPtr( Axis2, "draggable", draggable );
        return &self.panner.dragger;
    }

    pub fn setViewport_PX( self: *Axis2, viewport_PX: Interval2 ) void {
        self.x.viewport_PX = viewport_PX.x;
        self.y.viewport_PX = viewport_PX.y;
    }

    // TODO: Maybe don't return by value?
    pub fn getViewport_PX( self: *const Axis2 ) Interval2 {
        return Interval2 {
            .x = self.x.viewport_PX,
            .y = self.y.viewport_PX,
        };
    }

    pub fn pan( self: *Axis2, frac: Vec2, coord: Vec2 ) void {
        // TODO: Not sure this will work well with axis constraints
        self.x.pan( frac.x, coord.x );
        self.y.pan( frac.y, coord.y );
    }

    pub fn set( self: *Axis2, frac: Vec2, coord: Vec2, scale: Vec2 ) void {
        // TODO: Not sure this will work well with axis constraints
        self.x.set( frac.x, coord.x, scale.x );
        self.y.set( frac.y, coord.y, scale.y );
    }

    // TODO: Maybe don't return by value?
    pub fn getBounds( self: *const Axis2 ) Interval2 {
        return Interval2 {
            .x = self.x.getBounds( ),
            .y = self.y.getBounds( ),
        };
    }
};

/// Convert from pixel coordinates to axis-frac coordinates.
pub fn lpxToAxisFrac( axis: *const Axis2, x_LPX: c_int, y_LPX: c_int, xDpr: f64, yDpr: f64 ) Vec2 {
    // Adjust coords for Device Pixel Ratio
    // TODO: Is there a way to test this without a hidpi monitor?
    const x_PX = @intToFloat( f64, x_LPX ) * xDpr;
    const y_PX = @intToFloat( f64, y_LPX ) * yDpr;

    // Add 0.5 to get the center of the pixel
    const coord_PX = xy( x_PX + 0.5, y_PX + 0.5 );

    // Convert to axis-frac
    var frac = axis.getViewport_PX( ).valueToFrac( coord_PX );

    // Invert y so it increases upward
    frac.y = 1.0 - frac.y;

    return frac;
}
