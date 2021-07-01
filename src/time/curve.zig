const std = @import( "std" );
const Mutex = std.Thread.Mutex;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
usingnamespace @import( "../core/core.zig" );
usingnamespace @import( "../core/glz.zig" );
usingnamespace @import( "../sim.zig" );

pub fn CurvePaintable( comptime N: usize, comptime P: usize ) type {
    return struct {
        const Self = @This();

        axes: [2]*const Axis,

        rgbKinetic: [3]GLfloat,
        rgbPotential: [3]GLfloat,

        hMutex: Mutex,
        hCoords: ArrayList(GLfloat),
        hIndices: ArrayList(GLuint),
        hDirty: bool,

        vao: GLuint,
        prog: CurveProgram,
        dCoords: GLuint,
        dIndices: GLuint,
        dCount: GLsizei,

        painter: Painter,
        simListener: SimListener(N,P) = SimListener(N,P) {
            .handleFrameFn = handleFrame,
        },

        pub fn init( name: []const u8, axes: [2]*const Axis, allocator: *Allocator ) !Self {
            return Self {
                .axes = axes,

                .rgbKinetic = [3]GLfloat { 1.0, 0.0, 0.0 },
                .rgbPotential = [3]GLfloat { 1.0, 0.5, 0.0 },

                .hMutex = Mutex {},
                .hCoords = ArrayList(GLfloat).init( allocator ),
                .hIndices = ArrayList(GLuint).init( allocator ),
                .hDirty = false,

                .vao = 0,
                .prog = undefined,
                .dCoords = 0,
                .dIndices = 0,
                .dCount = 0,

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

            const t = @floatCast( GLfloat, simFrame.t );

            var kineticEnergy = @as( f64, 0.0 );
            for ( simFrame.ms ) |m,p| {
                var vSquared = @as( f64, 0.0 );
                for ( simFrame.vs[ p*N.. ][ 0..N ] ) |v| {
                    vSquared += v*v;
                }
                kineticEnergy += 0.5 * m * vSquared;
            }

            var potentialEnergy = @as( f64, 0.0 );
            for ( simFrame.config.accelerators ) |accelerator| {
                potentialEnergy += accelerator.computePotentialEnergy( simFrame.xs, simFrame.ms );
            }

            const totalEnergy = kineticEnergy + potentialEnergy;

            const newCoords = [_]GLfloat {
                t, @as( GLfloat, 0 ), @as( GLfloat, 0 ),
                t, @floatCast( GLfloat, potentialEnergy ), @as( GLfloat, 1 ),
                t, @floatCast( GLfloat, totalEnergy ), @as( GLfloat, 2 ),
            };

            {
                const held = self.hMutex.acquire( );
                defer held.release( );

                try self.hCoords.appendSlice( &newCoords );

                const hCount = @intCast( GLuint, @divTrunc( self.hCoords.items.len, 3 ) );
                if ( hCount >= 6 ) {
                    const C = hCount-4; const F = hCount-1;
                    const B = hCount-5; const E = hCount-2;
                    const A = hCount-6; const D = hCount-3;
                    const newIndices = [_]GLuint {
                        B, A, E,
                        E, A, D,
                        C, B, F,
                        F, B, E,
                    };
                    try self.hIndices.appendSlice( &newIndices );
                }

                self.hDirty = true;
            }
        }

        fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
            const self = @fieldParentPtr( Self, "painter", painter );

            self.prog = try CurveProgram.glCreate( );

            glGenBuffers( 1, &self.dCoords );
            glGenBuffers( 1, &self.dIndices );
            glBindBuffer( GL_ARRAY_BUFFER, self.dCoords );
            glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, self.dIndices );

            glGenVertexArrays( 1, &self.vao );
            glBindVertexArray( self.vao );
            if ( self.prog.inCoords >= 0 ) {
                const inCoords = @intCast( GLuint, self.prog.inCoords );
                glEnableVertexAttribArray( inCoords );
                glVertexAttribPointer( inCoords, 3, GL_FLOAT, GL_FALSE, 0, null );
            }
        }

        fn glPaint( painter: *Painter, pc: *const PainterContext ) !void {
            const self = @fieldParentPtr( Self, "painter", painter );

            glBindBuffer( GL_ARRAY_BUFFER, self.dCoords );
            glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, self.dIndices );

            {
                const held = self.hMutex.acquire( );
                defer held.release( );
                if ( self.hDirty ) {
                    glzBufferData( GL_ARRAY_BUFFER, GLfloat, self.hCoords.items, GL_STATIC_DRAW );
                    glzBufferData( GL_ELEMENT_ARRAY_BUFFER, GLuint, self.hIndices.items, GL_STATIC_DRAW );
                    self.dCount = @intCast( GLsizei, self.hIndices.items.len ); // FIXME: Overflow
                    self.hDirty = false;
                }
            }

            if ( self.dCount > 0 ) {
                const bounds = axisBounds( 2, self.axes );

                glzEnablePremultipliedAlphaBlending( );

                glUseProgram( self.prog.program );
                glzUniformInterval2( self.prog.XY_BOUNDS, bounds );
                glUniform3fv( self.prog.RGB_Z0, 1, &self.rgbPotential );
                glUniform3fv( self.prog.RGB_Z1, 1, &self.rgbKinetic );

                glBindVertexArray( self.vao );
                glDrawElements( GL_TRIANGLES, self.dCount, GL_UNSIGNED_INT, null );
            }
        }

        fn glDeinit( painter: *Painter ) void {
            const self = @fieldParentPtr( Self, "painter", painter );
            glDeleteProgram( self.prog.program );
            glDeleteVertexArrays( 1, &self.vao );
            glDeleteBuffers( 1, &self.dCoords );
            glDeleteBuffers( 1, &self.dIndices );
        }

        pub fn deinit( self: *Self ) void {
            {
                const held = self.hMutex.acquire( );
                defer held.release( );
                self.hCoords.deinit( );
                self.hIndices.deinit( );
            }
        }
    };
}

const CurveProgram = struct {
    program: GLuint,

    XY_BOUNDS: GLint,
    RGB_Z0: GLint,
    RGB_Z1: GLint,

    /// x_XAXIS, y_YAXIS, z
    inCoords: GLint,

    pub fn glCreate( ) !CurveProgram {
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
            \\// x_XAXIS, y_YAXIS, z
            \\in vec3 inCoords;
            \\
            \\out float vZ; // FIXME: Try "flat" keyword
            \\
            \\void main( void ) {
            \\    vec2 xy_XYAXIS = inCoords.xy;
            \\    gl_Position = vec4( coordsToNdc2D( xy_XYAXIS, XY_BOUNDS ), 0.0, 1.0 );
            \\    vZ = inCoords.z;
            \\}
        ;

        const fragSource =
            \\#version 150 core
            \\precision lowp float;
            \\
            \\uniform vec3 RGB_Z0;
            \\uniform vec3 RGB_Z1;
            \\
            \\in float vZ;
            \\
            \\out vec4 outRgba;
            \\
            \\void main( void ) {
            \\    switch ( int( vZ ) ) {
            \\        case 0:
            \\            outRgba = vec4( RGB_Z0, 1.0 );
            \\            break;
            \\        case 1:
            \\            outRgba = vec4( RGB_Z1, 1.0 );
            \\            break;
            \\        default:
            \\            discard;
            \\            break;
            \\    }
            \\}
        ;

        const program = try glzCreateProgram( vertSource, fragSource );
        return CurveProgram {
            .program = program,
            .XY_BOUNDS = glGetUniformLocation( program, "XY_BOUNDS" ),
            .RGB_Z0 = glGetUniformLocation( program, "RGB_Z0" ),
            .RGB_Z1 = glGetUniformLocation( program, "RGB_Z1" ),
            .inCoords = glGetAttribLocation( program, "inCoords" ),
        };
    }
};
