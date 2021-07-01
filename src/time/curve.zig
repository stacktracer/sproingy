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

        rgb: [3]GLfloat,

        pendingCoordsMutex: Mutex,
        pendingCoords: ArrayList(GLfloat),
        vCoords: ArrayList(GLfloat),

        prog: CurveProgram,
        vbo: GLuint,
        vao: GLuint,

        painter: Painter,
        simListener: SimListener(N,P) = SimListener(N,P) {
            .handleFrameFn = handleFrame,
        },

        pub fn init( name: []const u8, axes: [2]*const Axis, allocator: *Allocator ) !Self {
            return Self {
                .axes = axes,

                .rgb = [3]GLfloat { 1.0, 1.0, 1.0 },

                .pendingCoordsMutex = Mutex {},
                .pendingCoords = ArrayList(GLfloat).init( allocator ),
                .vCoords = ArrayList(GLfloat).init( allocator ),

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

        /// Called on simulator thread
        fn handleFrame( simListener: *SimListener(N,P), simFrame: *const SimFrame(N,P) ) !void {
            const self = @fieldParentPtr( Self, "simListener", simListener );

            var totalKineticEnergy = @as( f64, 0.0 );
            for ( simFrame.ms ) |m,p| {
                var vSquared = @as( f64, 0.0 );
                for ( simFrame.vs[ p*N.. ][ 0..N ] ) |v| {
                    vSquared += v*v;
                }
                totalKineticEnergy += 0.5 * m * vSquared;
            }

            var totalPotentialEnergy = @as( f64, 0.0 );
            for ( simFrame.config.accelerators ) |accelerator| {
                totalPotentialEnergy += accelerator.computePotentialEnergy( simFrame.xs, simFrame.ms );
            }

            const totalEnergy = totalKineticEnergy + totalPotentialEnergy;

            const newCoords = [_]GLfloat {
                @floatCast( GLfloat, simFrame.t ),
                @floatCast( GLfloat, totalEnergy ),
            };

            {
                const held = self.pendingCoordsMutex.acquire( );
                defer held.release( );
                try self.pendingCoords.appendSlice( &newCoords );
            }
        }

        fn glInit( painter: *Painter, pc: *const PainterContext ) !void {
            const self = @fieldParentPtr( Self, "painter", painter );

            self.prog = try CurveProgram.glCreate( );

            glGenBuffers( 1, &self.vbo );
            glBindBuffer( GL_ARRAY_BUFFER, self.vbo );

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

            glBindBuffer( GL_ARRAY_BUFFER, self.vbo );

            var vCoordsModified = false;
            {
                const held = self.pendingCoordsMutex.acquire( );
                defer held.release( );
                if ( self.pendingCoords.items.len > 0 ) {
                    try self.vCoords.appendSlice( self.pendingCoords.items );
                    self.pendingCoords.items.len = 0;
                    vCoordsModified = true;
                }
            }
            if ( vCoordsModified ) {
                glzBufferData( GL_ARRAY_BUFFER, GLfloat, self.vCoords.items, GL_STATIC_DRAW );
            }

            const vCount = @divTrunc( self.vCoords.items.len, 2 );
            if ( vCount > 0 ) {
                const bounds = axisBounds( 2, self.axes );

                glzEnablePremultipliedAlphaBlending( );

                glUseProgram( self.prog.program );
                glzUniformInterval2( self.prog.XY_BOUNDS, bounds );
                glUniform3fv( self.prog.RGB, 1, &self.rgb );

                glBindVertexArray( self.vao );
                // FIXME: Draw simple lines
                glPointSize( 4 );
                glDrawArrays( GL_POINTS, 0, @intCast( c_int, vCount ) ); // FIXME: Overflow
            }
        }

        fn glDeinit( painter: *Painter ) void {
            const self = @fieldParentPtr( Self, "painter", painter );
            glDeleteProgram( self.prog.program );
            glDeleteVertexArrays( 1, &self.vao );
            glDeleteBuffers( 1, &self.vbo );
        }

        pub fn deinit( self: *Self ) void {
            self.vCoords.deinit( );
        }
    };
}

const CurveProgram = struct {
    program: GLuint,

    XY_BOUNDS: GLint,
    RGB: GLint,

    /// x_XAXIS, y_YAXIS
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
            \\uniform vec3 RGB;
            \\
            \\out vec4 outRgba;
            \\
            \\void main( void ) {
            \\    float alpha = 1.0;
            \\    outRgba = vec4( alpha*RGB, alpha );
            \\}
        ;

        const program = try glzCreateProgram( vertSource, fragSource );
        return CurveProgram {
            .program = program,
            .XY_BOUNDS = glGetUniformLocation( program, "XY_BOUNDS" ),
            .RGB = glGetUniformLocation( program, "RGB" ),
            .inCoords = glGetAttribLocation( program, "inCoords" ),
        };
    }
};
