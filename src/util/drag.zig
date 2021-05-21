usingnamespace @import( "misc.zig" );

pub const Dragger = struct {
    canHandlePressFn: fn ( self: *Dragger, mouse_PX: Vec2 ) bool,
    handlePressFn: fn ( self: *Dragger, mouse_PX: Vec2 ) void,
    handleDragFn: fn ( self: *Dragger, mouse_PX: Vec2 ) void,
    handleReleaseFn: fn ( self: *Dragger, mouse_PX: Vec2 ) void,

    pub fn canHandlePress( self: *Dragger, mouse_PX: Vec2 ) bool {
        return self.canHandlePressFn( self, mouse_PX );
    }

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

pub fn findDragger( draggers: []const *Dragger, mouse_PX: Vec2 ) ?*Dragger {
    for ( draggers ) |dragger| {
        if ( dragger.canHandlePress( mouse_PX ) ) {
            return dragger;
        }
    }
    return null;
}
