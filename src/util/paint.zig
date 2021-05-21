const std = @import( "std" );
usingnamespace @import( "misc.zig" );
usingnamespace @import( "c.zig" );

pub const Paintable = opaque {};

pub const Painter = struct {
    needsInit: bool = true,

    initFn: fn ( self: *Painter, viewport_PX: Interval2 ) anyerror!void,
    paintFn: fn ( self: *Painter, viewport_PX: Interval2 ) anyerror!void,
    deinitFn: fn ( self: *Painter ) void,

    pub fn paint( self: *Painter, viewport_PX: Interval2 ) !void {
        if ( self.needsInit ) {
            try self.initFn( self, viewport_PX );
            self.needsInit = false;
        }
        return self.paintFn( self, viewport_PX );
    }

    pub fn deinit( self: *Painter ) void {
        return self.deinitFn( self );
    }
};

pub const MultiPaintable = struct {
    painter: Painter,

    allocator: *std.mem.Allocator,
    childPaintables: std.ArrayList( *Paintable ),
    childPainters: std.ArrayList( *Painter ),

    pub fn init( self: *MultiPaintable, allocator: *std.mem.Allocator ) void {
        self.allocator = allocator;
        self.childPaintables = std.ArrayList( *Paintable ).init( allocator );
        self.childPainters = std.ArrayList( *Painter ).init( allocator );
        self.painter = Painter {
            .initFn = painterInit,
            .paintFn = painterPaint,
            .deinitFn = painterDeinit,
        };
    }

    pub fn addChild( self: *MultiPaintable, comptime T: type ) !*T {
        var childPaintable = try self.allocator.create( T );
        try self.childPaintables.append( @ptrCast( *Paintable, childPaintable ) );
        try self.childPainters.append( &childPaintable.painter );
        return childPaintable;
    }

    fn painterInit( painter: *Painter, viewport_PX: Interval2 ) !void {
        // Do nothing
    }

    fn painterPaint( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            try childPainter.paint( viewport_PX );
        }
    }

    fn painterDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            childPainter.deinit( );
        }
        self.childPainters.deinit( );
    }

    // FIXME: Awkward
    pub fn deinit( self: *MultiPaintable ) void {
        for ( self.childPaintables.items ) |childPaintable| {
            self.allocator.destroy( childPaintable );
        }
        self.childPaintables.deinit( );
    }
};

pub const ClearPaintable = struct {
    painter: Painter,
    mask: GLbitfield,
    rgba: [4]GLfloat,
    depth: GLfloat,
    stencil: GLint,

    pub fn init( self: *ClearPaintable, mask: GLbitfield ) void {
        self.mask = mask;
        self.rgba = [_]GLfloat { 0.0, 0.0, 0.0, 0.0 };
        self.depth = 1.0;
        self.stencil = 0;
        self.painter = Painter {
            .initFn = painterInit,
            .paintFn = painterPaint,
            .deinitFn = painterDeinit,
        };
    }

    fn painterInit( painter: *Painter, viewport_PX: Interval2 ) !void {
        // Do nothing
    }

    fn painterPaint( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( ClearPaintable, "painter", painter );
        if ( self.mask & GL_COLOR_BUFFER_BIT != 0 ) {
            glClearColor( self.rgba[0], self.rgba[1], self.rgba[2], self.rgba[3] );
        }
        if ( self.mask & GL_DEPTH_BUFFER_BIT != 0 ) {
            glClearDepthf( self.depth );
        }
        if ( self.mask & GL_STENCIL_BUFFER_BIT != 0 ) {
            glClearStencil( self.stencil );
        }
        glClear( self.mask );
    }

    fn painterDeinit( painter: *Painter ) void {
        // Do nothing
    }
};
