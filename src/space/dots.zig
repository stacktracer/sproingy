const std = @import( "std" );
const Mutex = std.Thread.Mutex;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
usingnamespace @import( "../core/core.zig" );
usingnamespace @import( "../core/glz.zig" );
usingnamespace @import( "../time/cursor.zig" );
usingnamespace @import( "../sim.zig" );

pub fn DotsPaintable( comptime N: usize, comptime P: usize ) type {
    return struct {
        const Self = @This();

        axes: [2]*const Axis,
        tCursor: *const VerticalCursor,

        size_LPX: f64,
        rgba: [4]GLfloat,

        pendingFramesMutex: Mutex,
        pendingFrames: ArrayList( *DotsFrame(P) ),
        frames: ArrayList( *DotsFrame(P) ),
        allocator: *Allocator,

        prog: DotsProgram,
        vao: GLuint,

        painter: Painter,
        simListener: SimListener(N,P) = SimListener(N,P) {
            .handleFrameFn = handleFrame,
        },

        pub fn init( name: []const u8, axes: [2]*const Axis, tCursor: *const VerticalCursor, allocator: *Allocator ) Self {
            return Self {
                .axes = axes,
                .tCursor = tCursor,

                .size_LPX = 15,
                .rgba = [4]GLfloat { 1.0, 0.0, 0.0, 1.0 },

                .pendingFramesMutex = Mutex {},
                .pendingFrames = ArrayList( *DotsFrame(P) ).init( allocator ),
                .frames = ArrayList( *DotsFrame(P) ).init( allocator ),
                .allocator = allocator,

                .prog = undefined,
                .vao = 0,

                .painter = Painter {
                    .name = name,
                    .glInitFn = glInit,
                    .glPaintFn = glPaint,
                    .glDeinitFn = glDeinit,
                },
            };
        }

        /// Called on simulator thread
        fn handleFrame( simListener: *SimListener(N,P), simFrame: *const SimFrame(N,P) ) !void {
            const self = @fieldParentPtr( Self, "simListener", simListener );

            var frame = try self.allocator.create( DotsFrame(P) );
            frame.t = simFrame.t;

            // TODO: Check that N >= 2
            var p = @as( usize, 0 );
            while ( p < P ) : ( p += 1 ) {
                frame.xs[ p*2 + 0 ] = @floatCast( GLfloat, simFrame.xs[ p*N + 0 ] );
                frame.xs[ p*2 + 1 ] = @floatCast( GLfloat, simFrame.xs[ p*N + 1 ] );
            }

            {
                const held = self.pendingFramesMutex.acquire( );
                defer held.release( );
                try self.pendingFrames.append( frame );
            }
        }

        fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
            const self = @fieldParentPtr( Self, "painter", painter );

            self.prog = try DotsProgram.glCreate( );

            glGenVertexArrays( 1, &self.vao );
            glBindVertexArray( self.vao );
            if ( self.prog.inCoords >= 0 ) {
                const inCoords = @intCast( GLuint, self.prog.inCoords );
                glEnableVertexAttribArray( inCoords );
                glVertexAttribPointer( inCoords, 2, GL_FLOAT, GL_FALSE, 0, null );
            }
        }

        fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
            const self = @fieldParentPtr( Self, "painter", painter );

            {
                const held = self.pendingFramesMutex.acquire( );
                defer held.release( );
                for ( self.pendingFrames.items ) |frame| {
                    const frameIndex = findFrameIndexAfter( self.frames.items, frame.t );
                    try self.frames.insert( frameIndex, frame );
                }
                self.pendingFrames.items.len = 0;
            }

            if ( P > 0 ) {
                const frameIndexAfter = findFrameIndexAfter( self.frames.items, self.tCursor.cursor );
                if ( frameIndexAfter >= 1 ) {
                    const frameIndexAtOrBefore = frameIndexAfter - 1;
                    var frame = self.frames.items[ frameIndexAtOrBefore ];

                    const size_PX = @floatCast( f32, self.size_LPX * pc.lpxToPx );
                    const bounds = axisBounds( 2, self.axes );

                    glzEnablePremultipliedAlphaBlending( );

                    glEnable( GL_VERTEX_PROGRAM_POINT_SIZE );
                    glUseProgram( self.prog.program );
                    glzUniformInterval2( self.prog.XY_BOUNDS, bounds );
                    glUniform1f( self.prog.SIZE_PX, size_PX );
                    glUniform4fv( self.prog.RGBA, 1, &self.rgba );

                    glBindVertexArray( self.vao );
                    if ( self.prog.inCoords >= 0 ) {
                        // TODO: What's the point of a VAO if we have to do this every time?
                        // TODO: Maybe separate VAO for each frame?
                        const inCoords = @intCast( GLuint, self.prog.inCoords );
                        glBindBuffer( GL_ARRAY_BUFFER, frame.glBuffer( ) );
                        glEnableVertexAttribArray( inCoords );
                        glVertexAttribPointer( inCoords, 2, GL_FLOAT, GL_FALSE, 0, null );
                    }
                    glDrawArrays( GL_POINTS, 0, P );
                }
            }
        }

        fn findFrameIndexAfter( frames: []const *DotsFrame(P), t: f64 ) usize {
            var lo = @as( usize, 0 );
            var hi = frames.len;
            while ( lo < hi ) {
                const mid = @divTrunc( lo + hi, 2 );
                if ( frames[ mid ].t > t ) {
                    hi = mid;
                }
                else {
                    lo = mid + 1;
                }
            }
            return hi;
        }

        fn glDeinit( painter: *Painter ) void {
            const self = @fieldParentPtr( Self, "painter", painter );
            glDeleteProgram( self.prog.program );
            glDeleteVertexArrays( 1, &self.vao );

            {
                const held = self.pendingFramesMutex.acquire( );
                defer held.release( );
                for ( self.pendingFrames.items ) |frame, i| {
                    // TODO: Not sure why the compiler complains here
                    // frame.glDeinit( );
                    self.pendingFrames.items[i].glDeinit( );
                }
            }

            for ( self.frames.items ) |frame, i| {
                // TODO: Not sure why the compiler complains here
                // frame.glDeinit( );
                self.frames.items[i].glDeinit( );
            }
        }

        pub fn deinit( self: *Self ) void {
            {
                const held = self.pendingFramesMutex.acquire( );
                defer held.release( );
                for ( self.pendingFrames.items ) |frame| {
                    self.allocator.destroy( frame );
                }
                self.pendingFrames.deinit( );
            }

            for ( self.frames.items ) |frame| {
                self.allocator.destroy( frame );
            }
            self.frames.deinit( );
        }
    };
}

fn DotsFrame( comptime P: usize ) type {
    return struct {
        const Self = @This();

        t: f64,
        xs: [2*P]GLfloat,
        _glBuffer: GLuint = 0,
        _glValid: bool = false,

        pub fn glBuffer( self: *Self ) GLuint {
            // FIXME: No idea why "if valid else" works but "if !valid" doesn't
            if ( self._glValid ) {
            }
            else {
                glGenBuffers( 1, &self._glBuffer );
                glBindBuffer( GL_ARRAY_BUFFER, self._glBuffer );
                glzBufferData( GL_ARRAY_BUFFER, GLfloat, &self.xs, GL_STATIC_DRAW );
                self._glValid = true;
            }
            return self._glBuffer;
        }

        pub fn glDeinit( self: *Self ) void {
            if ( self._glValid ) {
                glDeleteBuffers( 1, &self._glBuffer );
                self._glBuffer = 0;
                self._glValid = false;
            }
        }
    };
}

const DotsProgram = struct {
    program: GLuint,

    XY_BOUNDS: GLint,
    SIZE_PX: GLint,
    RGBA: GLint,

    /// x_XAXIS, y_YAXIS
    inCoords: GLint,

    pub fn glCreate( ) !DotsProgram {
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

        const program = try glzCreateProgram( vertSource, fragSource );
        return DotsProgram {
            .program = program,
            .XY_BOUNDS = glGetUniformLocation( program, "XY_BOUNDS" ),
            .SIZE_PX = glGetUniformLocation( program, "SIZE_PX" ),
            .RGBA = glGetUniformLocation( program, "RGBA" ),
            .inCoords = glGetAttribLocation( program, "inCoords" ),
        };
    }
};
