usingnamespace @import( "drag.zig" );
usingnamespace @import( "misc.zig" );

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

    grabCoord: Vec2,
    dragger: Dragger,

    pub fn create( viewport_PX: Interval2 ) Axis2 {
        return Axis2 {
            .x = Axis1.create( viewport_PX.x ),
            .y = Axis1.create( viewport_PX.y ),
            .grabCoord = undefined,
            .dragger = Dragger {
                .canHandlePressFn = canHandlePress,
                .handlePressFn = handlePress,
                .handleDragFn = handleDrag,
                .handleReleaseFn = handleRelease,
            },
        };
    }

    fn canHandlePress( dragger: *Dragger, mouse_PX: Vec2 ) bool {
        const self = @fieldParentPtr( Axis2, "dragger", dragger );
        const mouse_FRAC = pxToAxisFrac( self, mouse_PX );
        return ( 0 <= mouse_FRAC.x and mouse_FRAC.x <= 1 and 0 <= mouse_FRAC.y and mouse_FRAC.y <= 1 );
    }

    fn handlePress( dragger: *Dragger, mouse_PX: Vec2 ) void {
        const self = @fieldParentPtr( Axis2, "dragger", dragger );
        const mouse_FRAC = pxToAxisFrac( self, mouse_PX );
        self.grabCoord = self.getBounds( ).fracToValue( mouse_FRAC );
    }

    fn handleDrag( dragger: *Dragger, mouse_PX: Vec2 ) void {
        const self = @fieldParentPtr( Axis2, "dragger", dragger );
        const mouse_FRAC = pxToAxisFrac( self, mouse_PX );
        self.pan( mouse_FRAC, self.grabCoord );
    }

    fn handleRelease( dragger: *Dragger, mouse_PX: Vec2 ) void {
        const self = @fieldParentPtr( Axis2, "dragger", dragger );
        const mouse_FRAC = pxToAxisFrac( self, mouse_PX );
        self.pan( mouse_FRAC, self.grabCoord );
    }

    pub fn setViewport_PX( self: *Axis2, viewport_PX: Interval2 ) void {
        self.x.viewport_PX = viewport_PX.x;
        self.y.viewport_PX = viewport_PX.y;
    }

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

    pub fn getBounds( self: *const Axis2 ) Interval2 {
        return Interval2 {
            .x = self.x.getBounds( ),
            .y = self.y.getBounds( ),
        };
    }
};

pub fn pxToAxisFrac( axis: *const Axis2, xy_PX: Vec2 ) Vec2 {
    // Flip y so it increases upward
    return Vec2 {
        .x = axis.x.viewport_PX.valueToFrac( xy_PX.x ),
        .y = 1.0 - axis.y.viewport_PX.valueToFrac( xy_PX.y ),
    };
}
