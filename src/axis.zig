const std = @import( "std" );
const nan = std.math.nan;
const u = @import( "util.zig" );
const Vec2 = u.Vec2;
const xy = u.xy;
const Interval1 = u.Interval1;
const Interval2 = u.Interval2;

pub const Dragger = struct {
    handlePressFn: fn ( self: *Dragger, mouse_PX: Vec2 ) void,
    handleDragFn: fn ( self: *Dragger, mouse_PX: Vec2 ) void,
    handleReleaseFn: fn ( self: *Dragger, mouse_PX: Vec2 ) void,

    pub fn handlePress( self: *Dragger, mouse_PX: Vec2 ) void {
        self.handlePressFn( self, mouse_PX );
    }

    pub fn handleDrag( self: *Dragger, mouse_PX: Vec2 ) void {
        self.handleDragFn( self, mouse_PX );
    }

    pub fn handleRelease( self: *Dragger, mouse_PX: Vec2 ) void {
        self.handleReleaseFn( self, mouse_PX );
    }
};

pub const Draggable = struct {
    getDraggerFn: fn ( self: *Draggable, mouse_PX: Vec2 ) ?*Dragger,

    pub fn getDragger( self: *Draggable, mouse_PX: Vec2 ) ?*Dragger {
        return self.getDraggerFn( self, mouse_PX );
    }
};

pub fn findDragger( draggables: []const *Draggable, mouse_PX: Vec2 ) ?*Dragger {
    for ( draggables ) |draggable| {
        const dragger = draggable.getDragger( mouse_PX );
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

pub const Axis2 = struct {
    x: Axis1,
    y: Axis1,

    // FIXME: Try moving these back out of Axis2
    grabCoord: Vec2,
    dragger: Dragger,
    draggable: Draggable,

    pub fn create( viewport_PX: Interval2 ) Axis2 {
        return Axis2 {
            .x = Axis1.create( viewport_PX.x ),
            .y = Axis1.create( viewport_PX.y ),
            .grabCoord = undefined,
            .dragger = Dragger {
                .handlePressFn = handlePress,
                .handleDragFn = handleDrag,
                .handleReleaseFn = handleRelease,
            },
            .draggable = Draggable {
                .getDraggerFn = getDragger,
            },
        };
    }

    /// Pass this same axis to ensuing handleDrag and handleRelease calls
    fn handlePress( dragger: *Dragger, mouse_PX: Vec2 ) void {
        const self = @fieldParentPtr( Axis2, "dragger", dragger );
        const mouse_FRAC = pxToAxisFrac( self, mouse_PX );
        self.grabCoord = self.getBounds( ).fracToValue( mouse_FRAC );
    }

    /// Pass the same axis that was passed to the preceding handlePress call
    fn handleDrag( dragger: *Dragger, mouse_PX: Vec2 ) void {
        const self = @fieldParentPtr( Axis2, "dragger", dragger );
        const mouse_FRAC = pxToAxisFrac( self, mouse_PX );
        self.pan( mouse_FRAC, self.grabCoord );
    }

    /// Pass the same axis that was passed to the preceding handlePress call
    fn handleRelease( dragger: *Dragger, mouse_PX: Vec2 ) void {
        const self = @fieldParentPtr( Axis2, "dragger", dragger );
        const mouse_FRAC = pxToAxisFrac( self, mouse_PX );
        self.pan( mouse_FRAC, self.grabCoord );
    }

    fn getDragger( draggable: *Draggable, mouse_PX: Vec2 ) ?*Dragger {
        const self = @fieldParentPtr( Axis2, "draggable", draggable );
        return &self.dragger;
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

// TODO: Test with hidpi (https://wiki.gnome.org/HowDoI/HiDpi/)
pub fn pxToAxisFrac( axis: *const Axis2, xy_PX: Vec2 ) Vec2 {
    // Invert y so it increases upward
    var frac = axis.getViewport_PX( ).valueToFrac( xy_PX );
    frac.y = 1.0 - frac.y;
    return frac;
}
