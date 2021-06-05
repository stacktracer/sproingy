const std = @import( "std" );
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
usingnamespace @import( "util/axis.zig" );
usingnamespace @import( "util/glz.zig" );
usingnamespace @import( "util/paint.zig" );

pub const DrawArraysPaintable = struct {
    axes: [2]*const Axis,

    mode: GLenum,
    rgba: [4]GLfloat,
    coords: ArrayList( GLfloat ),
    coordsModified: bool,

    prog: DrawArraysProgram,
    vbo: GLuint,
    vCount: GLsizei,
    vao: GLuint,

    painter: Painter,

    pub fn init( name: []const u8, axes: [2]*const Axis, mode: GLenum, allocator: *Allocator ) DrawArraysPaintable {
        return DrawArraysPaintable {
            .axes = axes,

            .mode = mode,
            .rgba = [4]GLfloat { 0.0, 0.0, 0.0, 1.0 },
            .coords = ArrayList( GLfloat ).init( allocator ),
            .coordsModified = true,

            .prog = undefined,
            .vbo = 0,
            .vCount = 0,
            .vao = 0,

            .painter = Painter {
                .name = name,
                .glInitFn = glInit,
                .glPaintFn = glPaint,
                .glDeinitFn = glDeinit,
            },
        };
    }

    fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
        const self = @fieldParentPtr( DrawArraysPaintable, "painter", painter );

        self.prog = try DrawArraysProgram.glCreate( );

        glGenBuffers( 1, &self.vbo );
        glBindBuffer( GL_ARRAY_BUFFER, self.vbo );

        glGenVertexArrays( 1, &self.vao );
        glBindVertexArray( self.vao );
        glEnableVertexAttribArray( self.prog.inCoords );
        glVertexAttribPointer( self.prog.inCoords, 2, GL_FLOAT, GL_FALSE, 0, null );
    }

    fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
        const self = @fieldParentPtr( DrawArraysPaintable, "painter", painter );

        if ( self.coordsModified ) {
            self.vCount = @intCast( GLsizei, @divTrunc( self.coords.items.len, 2 ) );
            if ( self.vCount > 0 ) {
                glBufferData( GL_ARRAY_BUFFER, 2*self.vCount*@sizeOf( GLfloat ), @ptrCast( *const c_void, self.coords.items.ptr ), GL_STATIC_DRAW );
            }
            self.coordsModified = false;
        }

        if ( self.vCount > 0 ) {
            const bounds = axisBounds( 2, self.axes );

            glzEnablePremultipliedAlphaBlending( );

            glUseProgram( self.prog.program );
            glzUniformInterval2( self.prog.XY_BOUNDS, bounds );
            glUniform4fv( self.prog.RGBA, 1, &self.rgba );

            glBindVertexArray( self.vao );
            glDrawArrays( self.mode, 0, self.vCount );
        }
    }

    fn glDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( DrawArraysPaintable, "painter", painter );
        glDeleteProgram( self.prog.program );
        glDeleteVertexArrays( 1, &self.vao );
        glDeleteBuffers( 1, &self.vbo );
    }

    pub fn deinit( self: *DrawArraysPaintable ) void {
        self.coords.deinit( );
    }
};

const DrawArraysProgram = struct {
    program: GLuint,

    XY_BOUNDS: GLint,
    RGBA: GLint,

    /// x_XAXIS, y_YAXIS
    inCoords: GLuint,

    pub fn glCreate( ) !DrawArraysProgram {
        const vertSource =
            \\#version 150 core
            \\
            \\vec2 start2D( vec4 interval2D )
            \\{
            \\    return interval2D.xy;
            \\}
            \\
            \\vec2 span2D( vec4 interval2D )
            \\{
            \\    return interval2D.zw;
            \\}
            \\
            \\vec2 coordsToNdc2D( vec2 coords, vec4 bounds )
            \\{
            \\    vec2 frac = ( coords - start2D( bounds ) ) / span2D( bounds );
            \\    return ( -1.0 + 2.0*frac );
            \\}
            \\
            \\uniform vec4 XY_BOUNDS;
            \\
            \\// x_XAXIS, y_YAXIS
            \\in vec2 inCoords;
            \\
            \\void main( void ) {
            \\    vec2 xy_XYAXIS = inCoords.xy;
            \\    gl_Position = vec4( coordsToNdc2D( xy_XYAXIS, XY_BOUNDS ), 0.0, 1.0 );
            \\}
        ;

        const fragSource =
            \\#version 150 core
            \\precision lowp float;
            \\
            \\uniform vec4 RGBA;
            \\
            \\out vec4 outRgba;
            \\
            \\void main( void ) {
            \\    float alpha = RGBA.a;
            \\    outRgba = vec4( alpha*RGBA.rgb, alpha );
            \\}
        ;

        const program = try glzCreateProgram( vertSource, fragSource );
        return DrawArraysProgram {
            .program = program,
            .XY_BOUNDS = glGetUniformLocation( program, "XY_BOUNDS" ),
            .RGBA = glGetUniformLocation( program, "RGBA" ),
            .inCoords = @intCast( GLuint, glGetAttribLocation( program, "inCoords" ) ),
        };
    }
};
