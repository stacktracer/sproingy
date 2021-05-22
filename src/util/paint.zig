const std = @import( "std" );
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
usingnamespace @import( "misc.zig" );
usingnamespace @import( "c.zig" );

pub const Painter = struct {
    name: []const u8,

    glResourcesSet: bool = false,

    /// Called while the GL context is current, and before the first paint.
    glInitFn: fn ( self: *Painter, viewport_PX: Interval2 ) anyerror!void,

    // Called while the GL context is current.
    glPaintFn: fn ( self: *Painter, viewport_PX: Interval2 ) anyerror!void,

    // Called while the GL context is current.
    glDeinitFn: fn ( self: *Painter ) void,

    pub fn glPaint( self: *Painter, viewport_PX: Interval2 ) !void {
        if ( !self.glResourcesSet ) {
            try self.glInitFn( self, viewport_PX );
            self.glResourcesSet = true;
        }
        return self.glPaintFn( self, viewport_PX );
    }

    pub fn glDeinit( self: *Painter ) void {
        if ( self.glResourcesSet ) {
            self.glDeinitFn( self );
            self.glResourcesSet = false;
        }
    }
};

pub const MultiPaintable = struct {
    painter: Painter,
    childPainters: ArrayList( *Painter ),

    pub fn create( name: []const u8, allocator: *Allocator ) MultiPaintable {
        return MultiPaintable {
            .childPainters = ArrayList( *Painter ).init( allocator ),
            .painter = Painter {
                .name = name,
                .glInitFn = glInit,
                .glPaintFn = glPaint,
                .glDeinitFn = glDeinit,
            },
        };
    }

    fn glInit( painter: *Painter, viewport_PX: Interval2 ) !void {
        // Do nothing
    }

    fn glPaint( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            try childPainter.glPaint( viewport_PX );
        }
    }

    fn glDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            childPainter.glDeinit( );
        }
        self.childPainters.items.len = 0;
    }

    pub fn deinit( self: *MultiPaintable ) void {
        for ( self.childPainters.items ) |childPainter| {
            if ( childPainter.glResourcesSet ) {
                std.debug.warn( "glDeinit was never called for painter \"{}\"\n", .{ childPainter.name } );
            }
        }
        self.childPainters.deinit( );
    }
};

pub const ClearPaintable = struct {
    painter: Painter,
    mask: GLbitfield,
    rgba: [4]GLfloat,
    depth: GLfloat,
    stencil: GLint,

    pub fn create( name: []const u8, mask: GLbitfield ) ClearPaintable {
        return ClearPaintable {
            .mask = mask,
            .rgba = [_]GLfloat { 0.0, 0.0, 0.0, 0.0 },
            .depth = 1.0,
            .stencil = 0,
            .painter = Painter {
                .name = name,
                .glInitFn = glInit,
                .glPaintFn = glPaint,
                .glDeinitFn = glDeinit,
            },
        };
    }

    fn glInit( painter: *Painter, viewport_PX: Interval2 ) !void {
        // Do nothing
    }

    fn glPaint( painter: *Painter, viewport_PX: Interval2 ) !void {
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

    fn glDeinit( painter: *Painter ) void {
        // Do nothing
    }
};
