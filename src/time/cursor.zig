const std = @import( "std" );
usingnamespace @import( "../core/core.zig" );
usingnamespace @import( "../core/glz.zig" );

pub const VerticalCursor = struct {
    axis: *const Axis,

    cursor: f64,
    thickness_LPX: f64,
    rgba: [4]GLfloat,
    coords: [8]GLfloat,

    prog: VerticalCursorProgram,
    vbo: GLuint,
    vCount: GLsizei,
    vao: GLuint,

    painter: Painter,

    dragOffset: f64,
    dragger: Dragger = .{
        .canHandlePressFn = canHandlePress,
        .handlePressFn = handlePress,
        .handleDragFn = handleDrag,
        .handleReleaseFn = handleRelease,
    },

    pub fn init( name: []const u8, axis: *const Axis ) VerticalCursor {
        return VerticalCursor {
            .axis = axis,

            .cursor = 0.0,
            .thickness_LPX = 3.0,
            .rgba = [4]GLfloat { 0.3, 0.4, 1.0, 1.0 },
            .coords = [8]GLfloat { -0.5,1.0, -0.5,-1.0, 0.5,1.0, 0.5,-1.0 },

            .prog = undefined,
            .vbo = 0,
            .vCount = 4,
            .vao = 0,

            .dragOffset = undefined,

            .painter = Painter {
                .name = name,
                .glInitFn = glInit,
                .glPaintFn = glPaint,
                .glDeinitFn = glDeinit,
            },
        };
    }

    fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
        const self = @fieldParentPtr( VerticalCursor, "painter", painter );

        self.prog = try VerticalCursorProgram.glCreate( );

        glGenBuffers( 1, &self.vbo );
        glBindBuffer( GL_ARRAY_BUFFER, self.vbo );
        glBufferData( GL_ARRAY_BUFFER, 2*self.vCount*@sizeOf( GLfloat ), @ptrCast( *const c_void, &self.coords ), GL_STATIC_DRAW );

        glGenVertexArrays( 1, &self.vao );
        glBindVertexArray( self.vao );
        glEnableVertexAttribArray( self.prog.inCoords );
        glVertexAttribPointer( self.prog.inCoords, 2, GL_FLOAT, GL_FALSE, 0, null );
    }

    fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
        const self = @fieldParentPtr( VerticalCursor, "painter", painter );

        const thickness_PX = @floatCast( GLfloat, self.thickness_LPX * pc.lpxToPx );

        const bounds = self.axis.bounds( );

        glzEnablePremultipliedAlphaBlending( );

        glUseProgram( self.prog.program );
        glzUniformInterval1( self.prog.VIEWPORT_PX, pc.viewport_PX[0] );
        glzUniformInterval1( self.prog.BOUNDS, bounds );
        glUniform1f( self.prog.CURSOR, @floatCast( GLfloat, self.cursor ) );
        glUniform1f( self.prog.THICKNESS_PX, thickness_PX );
        glUniform4fv( self.prog.RGBA, 1, &self.rgba );

        glBindVertexArray( self.vao );
        glDrawArrays( GL_TRIANGLE_STRIP, 0, self.vCount );
    }

    fn glDeinit( painter: *Painter ) void {
        const self = @fieldParentPtr( VerticalCursor, "painter", painter );
        glDeleteProgram( self.prog.program );
        glDeleteVertexArrays( 1, &self.vao );
        glDeleteBuffers( 1, &self.vbo );
    }

    fn canHandlePress( dragger: *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) bool {
        const self = @fieldParentPtr( VerticalCursor, "dragger", dragger );
        if ( clickCount > 1 ) {
            return true;
        }
        else {
            const mouseFrac = self.axis.viewport_PX.valueToFrac( mouse_PX[0] );
            const mouseCoord = self.axis.bounds( ).fracToValue( mouseFrac );
            const offset = self.cursor - mouseCoord;
            return ( @fabs( offset * self.axis.scale ) <= self.thickness_LPX * context.lpxToPx );
        }
    }

    fn handlePress( dragger: *Dragger, context: DraggerContext, mouse_PX: [2]f64, clickCount: u32 ) void {
        const self = @fieldParentPtr( VerticalCursor, "dragger", dragger );
        const mouseFrac = self.axis.viewport_PX.valueToFrac( mouse_PX[0] );
        const mouseCoord = self.axis.bounds( ).fracToValue( mouseFrac );
        if ( clickCount == 1 ) {
            self.dragOffset = self.cursor - mouseCoord;
        }
        else if ( clickCount > 1 ) {
            self.cursor = mouseCoord;
            self.dragOffset = 0;
        }
    }

    fn handleDrag( dragger: *Dragger, context: DraggerContext, mouse_PX: [2]f64 ) void {
        const self = @fieldParentPtr( VerticalCursor, "dragger", dragger );
        const mouseFrac = self.axis.viewport_PX.valueToFrac( mouse_PX[0] );
        const mouseCoord = self.axis.bounds( ).fracToValue( mouseFrac );
        self.cursor = mouseCoord - self.dragOffset;
    }

    fn handleRelease( dragger: *Dragger, context: DraggerContext, mouse_PX: [2]f64 ) void {
        const self = @fieldParentPtr( VerticalCursor, "dragger", dragger );
        const mouseFrac = self.axis.viewport_PX.valueToFrac( mouse_PX[0] );
        const mouseCoord = self.axis.bounds( ).fracToValue( mouseFrac );
        self.cursor = mouseCoord - self.dragOffset;
    }
};

const VerticalCursorProgram = struct {
    program: GLuint,

    VIEWPORT_PX: GLint,
    BOUNDS: GLint,
    CURSOR: GLint,
    THICKNESS_PX: GLint,
    RGBA: GLint,

    /// x_REL, y_NDC
    inCoords: GLuint,

    pub fn glCreate( ) !VerticalCursorProgram {
        const vertSource =
            \\#version 150 core
            \\
            \\float start1( vec2 interval1 ) {
            \\    return interval1.x;
            \\}
            \\
            \\float span1( vec2 interval1 ) {
            \\    return interval1.y;
            \\}
            \\
            \\float coordsToNdc1( float coord, vec2 bounds ) {
            \\    float frac = ( coord - start1( bounds ) ) / span1( bounds );
            \\    return ( -1.0 + 2.0*frac );
            \\}
            \\
            \\uniform vec2 VIEWPORT_PX;
            \\uniform vec2 BOUNDS;
            \\uniform float CURSOR;
            \\uniform float THICKNESS_PX;
            \\
            \\// dxOffset, y_NDC
            \\in vec2 inCoords;
            \\
            \\void main( void ) {
            \\    float xCenter_NDC = coordsToNdc1( CURSOR, BOUNDS );
            \\    float dxOffset_NDC = ( 2.0 * inCoords.x * THICKNESS_PX ) / VIEWPORT_PX.y;
            \\    float x_NDC = xCenter_NDC + dxOffset_NDC;
            \\    float y_NDC = inCoords.y;
            \\    gl_Position = vec4( x_NDC, y_NDC, 0.0, 1.0 );
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
        return VerticalCursorProgram {
            .program = program,
            .VIEWPORT_PX = glGetUniformLocation( program, "VIEWPORT_PX" ),
            .BOUNDS = glGetUniformLocation( program, "BOUNDS" ),
            .CURSOR = glGetUniformLocation( program, "CURSOR" ),
            .THICKNESS_PX = glGetUniformLocation( program, "THICKNESS_PX" ),
            .RGBA = glGetUniformLocation( program, "RGBA" ),
            .inCoords = @intCast( GLuint, glGetAttribLocation( program, "inCoords" ) ),
        };
    }
};
