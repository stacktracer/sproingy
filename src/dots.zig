const std = @import( "std" );
usingnamespace @import( "util/axis.zig" );
usingnamespace @import( "util/glz.zig" );
usingnamespace @import( "util/misc.zig" );
usingnamespace @import( "util/paint.zig" );

pub const DotsPaintable = struct {
    painter: Painter,

    axis: *Axis2,

    vCoords: std.ArrayList( GLfloat ),
    vCoordsModified: bool,

    prog: DotsProgram,
    vbo: GLuint,
    vCount: GLsizei,
    vao: GLuint,

    pub fn init( self: *DotsPaintable, axis: *Axis2, allocator: *std.mem.Allocator ) void {
        self.axis = axis;

        self.vCoords = std.ArrayList( GLfloat ).init( allocator );
        self.vCoordsModified = true;

        self.prog = undefined;
        self.vbo = 0;
        self.vCount = 0;
        self.vao = 0;

        self.painter = Painter {
            .initFn = painterInit,
            .paintFn = painterPaint,
            .deinitFn = painterDeinit,
        };
    }

    fn painterInit( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( DotsPaintable, "painter", painter );

        try self.prog.init( );

        glGenBuffers( 1, &self.vbo );
        glBindBuffer( GL_ARRAY_BUFFER, self.vbo );

        glGenVertexArrays( 1, &self.vao );
        glBindVertexArray( self.vao );
        glEnableVertexAttribArray( self.prog.inCoords );
        glVertexAttribPointer( self.prog.inCoords, 2, GL_FLOAT, GL_FALSE, 0, null );
    }

    fn painterPaint( painter: *Painter, viewport_PX: Interval2 ) !void {
        const self = @fieldParentPtr( DotsPaintable, "painter", painter );

        if ( self.vCoordsModified ) {
            self.vCount = @intCast( GLsizei, @divTrunc( self.vCoords.items.len, 2 ) );
            if ( self.vCount > 0 ) {
                glBufferData( GL_ARRAY_BUFFER, 2*self.vCount*@sizeOf( GLfloat ), @ptrCast( *const c_void, self.vCoords.items.ptr ), GL_STATIC_DRAW );
            }
            self.vCoordsModified = false;
        }

        if ( self.vCount > 0 ) {
            const bounds = self.axis.getBounds( );

            glzEnablePremultipliedAlphaBlending( );

            glEnable( GL_VERTEX_PROGRAM_POINT_SIZE );
            glUseProgram( self.prog.program );
            glzUniformInterval2( self.prog.XY_BOUNDS, bounds );
            glUniform1f( self.prog.SIZE_PX, 15 );
            glUniform4f( self.prog.RGBA, 1.0, 0.0, 0.0, 1.0 );

            glBindVertexArray( self.vao );
            glDrawArrays( GL_POINTS, 0, self.vCount );
        }
    }

    fn painterDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( DotsPaintable, "painter", painter );

        // FIXME: This doesn't currently get invoked
        std.debug.print( "  Dots DEINIT\n", .{} );

        self.vCoords.deinit( );
        glDeleteProgram( self.prog.program );
        glDeleteVertexArrays( 1, &self.vao );
        glDeleteBuffers( 1, &self.vbo );
    }
};

const DotsProgram = struct {
    program: GLuint,

    XY_BOUNDS: GLint,
    SIZE_PX: GLint,
    RGBA: GLint,

    /// x_XAXIS, y_YAXIS
    inCoords: GLuint,

    /// Must be called while the appropriate GL context is current
    pub fn init( self: *DotsProgram ) !void {
        const vertSource =
            \\#version 150 core
            \\
            \\vec2 min2D( vec4 interval2D )
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
            \\    vec2 frac = ( coords - min2D( bounds ) ) / span2D( bounds );
            \\    return ( -1.0 + 2.0*frac );
            \\}
            \\
            \\uniform vec4 XY_BOUNDS;
            \\uniform float SIZE_PX;
            \\
            \\// x_XAXIS, y_YAXIS
            \\in vec2 inCoords;
            \\
            \\void main( void ) {
            \\    vec2 xy_XYAXIS = inCoords.xy;
            \\    gl_Position = vec4( coordsToNdc2D( xy_XYAXIS, XY_BOUNDS ), 0.0, 1.0 );
            \\    gl_PointSize = SIZE_PX;
            \\}
        ;

        const fragSource =
            \\#version 150 core
            \\precision lowp float;
            \\
            \\const float FEATHER_PX = 0.9;
            \\
            \\uniform float SIZE_PX;
            \\uniform vec4 RGBA;
            \\
            \\out vec4 outRgba;
            \\
            \\void main( void ) {
            \\    vec2 xy_NPC = -1.0 + 2.0*gl_PointCoord;
            \\    float r_NPC = sqrt( dot( xy_NPC, xy_NPC ) );
            \\
            \\    float pxToNpc = 2.0 / SIZE_PX;
            \\    float rOuter_NPC = 1.0 - 0.5*pxToNpc;
            \\    float rInner_NPC = rOuter_NPC - FEATHER_PX*pxToNpc;
            \\    float mask = smoothstep( rOuter_NPC, rInner_NPC, r_NPC );
            \\
            \\    float alpha = mask * RGBA.a;
            \\    outRgba = vec4( alpha*RGBA.rgb, alpha );
            \\}
        ;

        self.program = try glzCreateProgram( vertSource, fragSource );
        self.XY_BOUNDS = glGetUniformLocation( self.program, "XY_BOUNDS" );
        self.SIZE_PX = glGetUniformLocation( self.program, "SIZE_PX" );
        self.RGBA = glGetUniformLocation( self.program, "RGBA" );
        self.inCoords = @intCast( GLuint, glGetAttribLocation( self.program, "inCoords" ) );
    }
};
