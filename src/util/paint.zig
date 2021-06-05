const std = @import( "std" );
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
usingnamespace @import( "gtkz.zig" );
usingnamespace @import( "glz.zig" );
usingnamespace @import( "c.zig" );
usingnamespace @import( "axis.zig" );

pub const PainterContext = struct {
    viewport_PX: [2]Interval,
    lpxToPx: f64,
};

pub const Painter = struct {
    name: []const u8,

    glResourcesAreSet: bool = false,

    /// Called while the GL context is current, and before the first paint.
    glInitFn: fn ( self: *Painter, pc: *const PainterContext ) anyerror!void,

    // Called while the GL context is current.
    glPaintFn: fn ( self: *Painter, pc: *const PainterContext ) anyerror!void,

    // Called while the GL context is current.
    glDeinitFn: fn ( self: *Painter ) void,

    pub fn glPaint( self: *Painter, pc: *const PainterContext ) !void {
        if ( !self.glResourcesAreSet ) {
            try self.glInitFn( self, pc );
            self.glResourcesAreSet = true;
        }
        return self.glPaintFn( self, pc );
    }

    pub fn glDeinit( self: *Painter ) void {
        if ( self.glResourcesAreSet ) {
            self.glDeinitFn( self );
            self.glResourcesAreSet = false;
        }
    }
};

pub const PaintingHandler = struct {
    painters: []const *Painter,

    pub fn init( painters: []const *Painter ) PaintingHandler {
        return PaintingHandler {
            .painters = painters,
        };
    }

    pub fn onRender( glArea: *GtkGLArea, glContext: *GdkGLContext, self: *PaintingHandler ) callconv(.C) gboolean {
        const pc = PainterContext {
            .viewport_PX = glzGetViewport_PX( ),
            .lpxToPx = gtkzScaleFactor( @ptrCast( *GtkWidget, glArea ) ),
        };
        for ( self.painters ) |painter| {
            painter.glPaint( &pc ) catch |e| {
                std.debug.warn( "Failed to paint: painter = {}, error = {}\n", .{ painter.name, e } );
            };
        }
        return 0;
    }

    pub fn onWindowClosing( window: *GtkWindow, ev: *GdkEvent, self: *PaintingHandler ) callconv(.C) gboolean {
        if ( glzHasCurrentContext( ) ) {
            for ( self.painters ) |painter| {
                painter.glDeinit( );
            }
        }
        else {
            std.debug.warn( "Failed to deinit painters; no current GL Context\n", .{} );
        }
        return 0;
    }
};

pub const MultiPaintable = struct {
    childPainters: ArrayList( *Painter ),
    painter: Painter,

    pub fn init( name: []const u8, allocator: *Allocator ) MultiPaintable {
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

    fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
        // Do nothing
    }

    fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
        const self = @fieldParentPtr( MultiPaintable, "painter", painter );
        for ( self.childPainters.items ) |childPainter| {
            childPainter.glPaint( pc ) catch |e| {
                std.debug.warn( "Failed to paint: painter = {}, error = {}\n", .{ childPainter.name, e } );
                if ( @errorReturnTrace( ) ) |trace| {
                    std.debug.dumpStackTrace( trace.* );
                }
            };
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
            if ( childPainter.glResourcesAreSet ) {
                std.debug.warn( "glDeinit was never called for painter \"{}\"\n", .{ childPainter.name } );
            }
        }
        self.childPainters.deinit( );
    }
};

pub const ClearPaintable = struct {
    mask: GLbitfield,
    rgba: [4]GLfloat,
    depth: GLfloat,
    stencil: GLint,
    painter: Painter,

    pub fn init( name: []const u8, mask: GLbitfield ) ClearPaintable {
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

    fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
        // Do nothing
    }

    fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
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
