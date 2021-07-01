usingnamespace @import( "../core/core.zig" );
usingnamespace @import( "../core/glz.zig" );

pub fn StaticPaintable( comptime vCapacity: usize ) type {
    return struct {
        const Self = @This();

        axes: [2]*const Axis,

        mode: GLenum,
        rgba: [4]GLfloat,
        vCoords: [2*vCapacity]GLfloat,
        vCount: GLsizei,
        vModified: bool,

        prog: StaticProgram,
        vbo: GLuint,
        vao: GLuint,

        painter: Painter,

        pub fn init( name: []const u8, axes: [2]*const Axis, mode: GLenum ) Self {
            return Self {
                .axes = axes,

                .mode = mode,
                .rgba = [4]GLfloat { 0.0, 0.0, 0.0, 1.0 },
                .vCoords = [1]GLfloat { 0.0 } ** ( 2*vCapacity ),
                .vCount = 0,
                .vModified = true,

                .prog = undefined,
                .vbo = 0,
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
            const self = @fieldParentPtr( Self, "painter", painter );

            self.prog = try StaticProgram.glCreate( );

            glGenBuffers( 1, &self.vbo );
            glBindBuffer( GL_ARRAY_BUFFER, self.vbo );

            glGenVertexArrays( 1, &self.vao );
            glBindVertexArray( self.vao );
            glEnableVertexAttribArray( self.prog.inCoords );
            glVertexAttribPointer( self.prog.inCoords, 2, GL_FLOAT, GL_FALSE, 0, null );
        }

        fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
            const self = @fieldParentPtr( Self, "painter", painter );

            if ( self.vModified ) {
                if ( self.vCount > 0 ) {
                    glBufferData( GL_ARRAY_BUFFER, 2*self.vCount*@sizeOf( GLfloat ), @ptrCast( *const c_void, &self.vCoords ), GL_STATIC_DRAW );
                }
                else {
                    // FIXME: glBufferData with null?
                }
                self.vModified = false;
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
            const self = @fieldParentPtr( Self, "painter", painter );
            glDeleteProgram( self.prog.program );
            glDeleteVertexArrays( 1, &self.vao );
            glDeleteBuffers( 1, &self.vbo );
        }
    };
}

const StaticProgram = struct {
    program: GLuint,

    XY_BOUNDS: GLint,
    RGBA: GLint,

    /// x_XAXIS, y_YAXIS
    inCoords: GLuint,

    pub fn glCreate( ) !StaticProgram {
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
        return StaticProgram {
            .program = program,
            .XY_BOUNDS = glGetUniformLocation( program, "XY_BOUNDS" ),
            .RGBA = glGetUniformLocation( program, "RGBA" ),
            .inCoords = @intCast( GLuint, glGetAttribLocation( program, "inCoords" ) ),
        };
    }
};
