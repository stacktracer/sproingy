usingnamespace @import( "misc.zig" );

pub const Draggable = struct {
    getDraggerFn: fn ( self: *Draggable, mouse_PX: Vec2 ) ?*Dragger,

    pub fn getDragger( self: *Draggable, mouse_PX: Vec2 ) ?*Dragger {
        return self.getDraggerFn( self, mouse_PX );
    }
};

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

pub fn findDragger( draggables: []const *Draggable, mouse_PX: Vec2 ) ?*Dragger {
    for ( draggables ) |draggable| {
        const dragger = draggable.getDragger( mouse_PX );
        if ( dragger != null ) {
            return dragger;
        }
    }
    return null;
}
