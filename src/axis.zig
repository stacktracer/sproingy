const std = @import( "std" );
const nan = std.math.nan;

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

pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub fn create( x: f64, y: f64 ) Vec2 {
        return Vec2 {
            .x = x,
            .y = y,
        };
    }

    pub fn set( self: *Vec2, x: f64, y: f64 ) void {
        self.x = x;
        self.y = y;
    }
};

pub const Interval1 = struct {
    /// Inclusive lower bound.
    min: f64,

    /// Difference between min and exclusive upper bound.
    span: f64,

    pub fn create( min: f64, span: f64 ) Interval1 {
        return Interval1 {
            .min = min,
            .span = span,
        };
    }

    pub fn createWithMinMax( min: f64, max: f64 ) Interval1 {
        return Interval1.create( min, max - min );
    }

    pub fn set( self: *Interval1, min: f64, span: f64 ) void {
        self.min = min;
        self.span = span;
    }

    pub fn valueToFrac( self: *const Interval1, value: f64 ) f64 {
        return ( ( value - self.min ) / self.span );
    }

    pub fn fracToValue( self: *const Interval1, frac: f64 ) f64 {
        return ( self.min + frac*self.span );
    }
};

pub const Axis1 = struct {
    viewport_PX: Interval1,

    // TODO: Any way to make tieFrac const?
    tieFrac: f64,
    tieCoord: f64,
    scale: f64,

    pub fn create( min: f64, span: f64 ) Axis1 {
        var axis = Axis1 {
            .viewport_PX = Interval1.createWithMinMax( 0, 1000 ),
            .tieFrac = 0.5,
            .tieCoord = 0.0,
            .scale = 1000,
        };
        axis.setBounds( Interval1.create( min, span ) );
        return axis;
    }

    pub fn createWithMinMax( min: f64, max: f64 ) Axis1 {
        return Axis1.create( min, max - min );
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

    pub fn setBounds( self: *Axis1, bounds: Interval1 ) void {
        // TODO: Apply constraints
        self.tieCoord = bounds.fracToValue( self.tieFrac );
        self.scale = self.viewport_PX.span / bounds.span;
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

pub const Interval2 = struct {
    x: Interval1,
    y: Interval1,

    pub fn create( xMin: f64, yMin: f64, xSpan: f64, ySpan: f64 ) Interval2 {
        return Interval2 {
            .x = Interval1.create( xMin, xSpan ),
            .y = Interval1.create( yMin, ySpan ),
        };
    }

    pub fn valueToFrac( self: *const Interval2, value: Vec2 ) Vec2 {
        return Vec2 {
            .x = self.x.valueToFrac( value.x ),
            .y = self.y.valueToFrac( value.y ),
        };
    }

    pub fn fracToValue( self: *const Interval2, frac: Vec2 ) Vec2 {
        return Vec2 {
            .x = self.x.fracToValue( frac.x ),
            .y = self.y.fracToValue( frac.y ),
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
            .grabCoord = Vec2.create( nan( f64 ), nan( f64 ) ),
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

    pub fn getDragger( draggable: *Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger {
        const self = @fieldParentPtr( Axis2, "draggable", draggable );
        return &self.panner.dragger;
    }

    pub fn create( xMin: f64, yMin: f64, xSpan: f64, ySpan: f64 ) Axis2 {
        return Axis2 {
            .x = Axis1.create( xMin, xSpan ),
            .y = Axis1.create( yMin, ySpan ),
            .panner = Axis2Panner.create( ),
            .draggable = Draggable {
                .getDraggerImpl = getDragger,
            },
        };
    }

    pub fn createWithMinMax( xMin: f64, yMin: f64, xMax: f64, yMax: f64 ) Axis2 {
        return Axis2.create( xMin, yMin, xMax - xMin, yMax - yMin );
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

pub fn getPixelFrac( axis: *const Axis2, x: c_int, y: c_int ) Vec2 {
    // TODO: Adjust coords for HiDPI
    // Add 0.5 to get the center of the pixel
    const coord_PX = Vec2.create( @intToFloat( f64, x ) + 0.5, @intToFloat( f64, y ) + 0.5 );
    var frac = axis.getViewport_PX( ).valueToFrac( coord_PX );
    // Invert so y increases upward
    frac.y = 1.0 - frac.y;
    return frac;
}
