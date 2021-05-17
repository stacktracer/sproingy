const std = @import( "std" );
const pow = std.math.pow;
const nan = std.math.nan;
const print = std.debug.print;
const g = @import( "gl.zig" );
const s = @import( "sdl2.zig" );


// TODO: Move to a utilities file
const Interval1 = struct {
    /// Inclusive lower bound.
    min: f64,

    /// Difference between min and exclusive upper bound.
    span: f64,

    fn createWithMinMax( min: f64, max: f64 ) Interval1 {
        return Interval1 {
            .min = min,
            .span = max - min
        };
    }

    fn set( self: *Interval1, min: f64, span: f64 ) void {
        self.min = min;
        self.span = span;
    }

    fn valueToFrac( self: *const Interval1, v: f64 ) f64 {
        return ( ( v - self.min ) / self.span );
    }

    fn fracToValue( self: *const Interval1, frac: f64 ) f64 {
        return ( self.min + frac*self.span );
    }
};

// TODO: Move to a utilities file
fn glUniformInterval2( location: g.GLint, x: Interval1, y: Interval1 ) void {
    g.glUniform4f( location, @floatCast( f32, x.min ), @floatCast( f32, y.min ), @floatCast( f32, x.span ), @floatCast( f32, y.span ) );
}

// TODO: Move to a utilities file
const Axis1 = struct {
    viewport_PX: Interval1,

    // TODO: Any way to make tieFrac const?
    tieFrac: f64,
    tieCoord: f64,
    scale: f64,

    fn createWithMinMax( min: f64, max: f64 ) Axis1 {
        var axis = Axis1 {
            .viewport_PX = Interval1.createWithMinMax( 0, 1000 ),
            .tieFrac = 0.5,
            .tieCoord = 0.0,
            .scale = 1000,
        };
        axis.setBounds( Interval1.createWithMinMax( min, max ) );
        return axis;
    }

    fn pan( self: *Axis1, frac: f64, coord: f64 ) void {
        const scale = self.scale;
        self.set( frac, coord, scale );
    }

    fn set( self: *Axis1, frac: f64, coord: f64, scale: f64 ) void {
        // TODO: Apply constraints
        const span = self.viewport_PX.span / scale;
        self.tieCoord = coord + ( self.tieFrac - frac )*span;
        self.scale = scale;
    }

    fn setBounds( self: *Axis1, bounds: Interval1 ) void {
        // TODO: Apply constraints
        self.tieCoord = bounds.fracToValue( self.tieFrac );
        self.scale = self.viewport_PX.span / bounds.span;
    }

    fn getBounds( self: *const Axis1 ) Interval1 {
        const span = self.viewport_PX.span / self.scale;
        const min = self.tieCoord - self.tieFrac*span;
        return Interval1 {
            .min = min,
            .span = span,
        };
    }
};



const Dragger = struct {
    const Self = @This( );

    handlePressImpl: fn ( self: *Self, xFrac: f64, yFrac: f64 ) void,
    handleDragImpl: fn ( self: *Self, xFrac: f64, yFrac: f64 ) void,
    handleReleaseImpl: fn ( self: *Self, xFrac: f64, yFrac: f64 ) void,

    fn handlePress( self: *Self, xFrac: f64, yFrac: f64 ) void {
        self.handlePressImpl( self, xFrac, yFrac );
    }

    fn handleDrag( self: *Self, xFrac: f64, yFrac: f64 ) void {
        self.handleDragImpl( self, xFrac, yFrac );
    }

    fn handleRelease( self: *Self, xFrac: f64, yFrac: f64 ) void {
        self.handleReleaseImpl( self, xFrac, yFrac );
    }
};

const AxisPanner2 = struct {
    const Self = @This( );

    // FIXME: Can this be renamed?
    dragger: Dragger,

    xAxis: *Axis1,
    yAxis: *Axis1,

    xGrabFrac: f64,
    yGrabFrac: f64,
    xGrabCoord: f64,
    yGrabCoord: f64,

    fn handlePress( dragger: *Dragger, xFrac: f64, yFrac: f64 ) void {
        const self = @fieldParentPtr( Self, "dragger", dragger );
        self.xGrabFrac = xFrac;
        self.yGrabFrac = yFrac;
        self.xGrabCoord = self.xAxis.getBounds( ).fracToValue( xFrac );
        self.yGrabCoord = self.yAxis.getBounds( ).fracToValue( yFrac );
    }

    fn handleDrag( dragger: *Dragger, xFrac: f64, yFrac: f64 ) void {
        const self = @fieldParentPtr( Self, "dragger", dragger );
        self.xAxis.pan( xFrac, self.xGrabCoord );
        self.yAxis.pan( yFrac, self.yGrabCoord );
    }

    fn handleRelease( dragger: *Dragger, xFrac: f64, yFrac: f64 ) void {
        const self = @fieldParentPtr( Self, "dragger", dragger );
        self.xAxis.pan( xFrac, self.xGrabCoord );
        self.yAxis.pan( yFrac, self.yGrabCoord );
    }

    fn init( xAxis: *Axis1, yAxis: *Axis1 ) Self {
        return Self {
            .xAxis = xAxis,
            .yAxis = yAxis,
            .xGrabFrac = nan( f64 ),
            .yGrabFrac = nan( f64 ),
            .xGrabCoord = nan( f64 ),
            .yGrabCoord = nan( f64 ),
            .dragger = Dragger {
                .handlePressImpl = handlePress,
                .handleDragImpl = handleDrag,
                .handleReleaseImpl = handleRelease,
            },
        };
    }
};


const DummyProgram = struct {
    program: g.GLuint,

    XY_BOUNDS: g.GLint,
    SIZE_PX: g.GLint,
    RGBA: g.GLint,

    /// x_XAXIS, y_YAXIS
    inCoords: g.GLuint
};

fn createDummyProgram( ) !DummyProgram {
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

    const dProgram = try g.createProgram( vertSource, fragSource );
    return DummyProgram {
        .program = dProgram,
        .XY_BOUNDS = g.glGetUniformLocation( dProgram, "XY_BOUNDS" ),
        .SIZE_PX = g.glGetUniformLocation( dProgram, "SIZE_PX" ),
        .RGBA = g.glGetUniformLocation( dProgram, "RGBA" ),
        .inCoords = @intCast( g.GLuint, g.glGetAttribLocation( dProgram, "inCoords" ) ),
    };
}

pub fn main( ) !u8 {

    // Window setup
    //

    try s.initSDL( s.SDL_INIT_VIDEO );
    defer s.SDL_Quit( );

    try s.setGLAttr( s.SDL_GL_DOUBLEBUFFER, 1 );
    try s.setGLAttr( s.SDL_GL_ACCELERATED_VISUAL, 1 );
    try s.setGLAttr( s.SDL_GL_RED_SIZE, 8 );
    try s.setGLAttr( s.SDL_GL_GREEN_SIZE, 8 );
    try s.setGLAttr( s.SDL_GL_BLUE_SIZE, 8 );
    try s.setGLAttr( s.SDL_GL_ALPHA_SIZE, 8 );
    try s.setGLAttr( s.SDL_GL_CONTEXT_MAJOR_VERSION, 3 );
    try s.setGLAttr( s.SDL_GL_CONTEXT_MINOR_VERSION, 2 );
    try s.setGLAttr( s.SDL_GL_CONTEXT_PROFILE_MASK, s.SDL_GL_CONTEXT_PROFILE_CORE );

    const window = try s.createWindow( "Dummy", s.SDL_WINDOWPOS_UNDEFINED, s.SDL_WINDOWPOS_UNDEFINED, 800, 600, s.SDL_WINDOW_OPENGL | s.SDL_WINDOW_RESIZABLE | s.SDL_WINDOW_SHOWN );
    defer s.SDL_DestroyWindow( window );

    const context = s.SDL_GL_CreateContext( window );
    defer s.SDL_GL_DeleteContext( context );

    try s.makeGLCurrent( window, context );
    try s.setGLSwapInterval( 0 );


    // Application state
    //

    var xAxis = Axis1.createWithMinMax( -1, 1 );
    var yAxis = Axis1.createWithMinMax( -1, 1 );

    var xMouseFrac: f64 = 0.5;
    var yMouseFrac: f64 = 0.5;

    // TODO: Awkward to store axis ptrs in AxisPanner2
    var axisPanner = AxisPanner2.init( &xAxis, &yAxis );
    var dragger: ?*Dragger = null;


    // GL setup
    //

    var vao: g.GLuint = 0;
    g.glGenVertexArrays( 1, &vao );
    defer g.glDeleteVertexArrays( 1, &vao );
    g.glBindVertexArray( vao );

    const hVertexCoords = [_][2]g.GLfloat{
        [_]g.GLfloat{ 0.0, 0.0 },
        [_]g.GLfloat{ 0.5, 0.0 },
        [_]g.GLfloat{ 0.0, 0.5 },
    };
    var dVertexCoords = @intCast( g.GLuint, 0 );
    g.glGenBuffers( 1, &dVertexCoords );
    g.glBindBuffer( g.GL_ARRAY_BUFFER, dVertexCoords );
    g.glBufferData( g.GL_ARRAY_BUFFER, hVertexCoords.len*2*@sizeOf( g.GLfloat ), @ptrCast( *const c_void, &hVertexCoords[0][0] ), g.GL_STATIC_DRAW );

    const dProgram = try createDummyProgram( );


    // Render loop
    //

    var running = true;
    while ( running ) {
        var wDrawable_PX: c_int = 0;
        var hDrawable_PX: c_int = 0;
        s.SDL_GL_GetDrawableSize( window, &wDrawable_PX, &hDrawable_PX );
        g.glViewport( 0, 0, wDrawable_PX, hDrawable_PX );
        xAxis.viewport_PX.set( 0, @intToFloat( f64, wDrawable_PX ) );
        yAxis.viewport_PX.set( 0, @intToFloat( f64, hDrawable_PX ) );
        const xBounds = xAxis.getBounds( );
        const yBounds = yAxis.getBounds( );

        g.glClearColor( 0.0, 0.0, 0.0, 1.0 );
        g.glClear( g.GL_COLOR_BUFFER_BIT );

        {
            g.enablePremultipliedAlphaBlending( );
            defer g.disableBlending( );

            g.glUseProgram( dProgram.program );
            defer g.glUseProgram( 0 );

            g.glEnable( g.GL_VERTEX_PROGRAM_POINT_SIZE );
            defer g.glDisable( g.GL_VERTEX_PROGRAM_POINT_SIZE );

            glUniformInterval2( dProgram.XY_BOUNDS, xBounds, yBounds );
            g.glUniform1f( dProgram.SIZE_PX, 15 );
            g.glUniform4f( dProgram.RGBA, 1.0, 0.0, 0.0, 1.0 );
            g.glBindBuffer( g.GL_ARRAY_BUFFER, dVertexCoords );
            g.glEnableVertexAttribArray( dProgram.inCoords );
            g.glVertexAttribPointer( dProgram.inCoords, 2, g.GL_FLOAT, g.GL_FALSE, 0, null );
            g.glDrawArrays( g.GL_POINTS, 0, hVertexCoords.len );
        }

        s.SDL_GL_SwapWindow( window );
        s.SDL_Delay( 1 );

        while ( true ) {
            var ev: s.SDL_Event = undefined;
            if ( s.SDL_PollEvent( &ev ) == 0 ) {
                break;
            }
            else {
                switch ( ev.type ) {
                    s.SDL_QUIT => running = false,
                    s.SDL_KEYDOWN => {
                        const keysym = ev.key.keysym;
                        switch ( keysym.sym ) {
                            s.SDLK_ESCAPE => running = false,
                            s.SDLK_w => {
                                if ( @intCast( c_int, keysym.mod ) & s.KMOD_CTRL != 0 ) {
                                    running = false;
                                }
                            },
                            else => {}
                        }
                    },
                    s.SDL_MOUSEBUTTONDOWN => {
                        // TODO: Check ev.motion.windowID
                        // TODO: Check ev.motion.which
                        switch ( ev.button.button ) {
                            s.SDL_BUTTON_LEFT => {
                                s.setMouseConfinedToWindow( window, true );
                                if ( dragger == null ) {
                                    dragger = &axisPanner.dragger;
                                    xMouseFrac = xAxis.viewport_PX.valueToFrac( @intToFloat( f64, ev.motion.x ) + 0.5 );
                                    yMouseFrac = 1.0 - yAxis.viewport_PX.valueToFrac( @intToFloat( f64, ev.motion.y ) + 0.5 );
                                    dragger.?.handlePress( xMouseFrac, yMouseFrac );
                                }
                            },
                            else => {}
                        }
                    },
                    s.SDL_MOUSEMOTION => {
                        // TODO: Check ev.motion.windowID
                        // TODO: Check ev.motion.which
                        // TODO: Adjust coords for HiDPI
                        xMouseFrac = xAxis.viewport_PX.valueToFrac( @intToFloat( f64, ev.motion.x ) + 0.5 );
                        yMouseFrac = 1.0 - yAxis.viewport_PX.valueToFrac( @intToFloat( f64, ev.motion.y ) + 0.5 );
                        if ( dragger != null ) {
                            dragger.?.handleDrag( xMouseFrac, yMouseFrac );
                        }
                    },
                    s.SDL_MOUSEBUTTONUP => {
                        // TODO: Check ev.motion.windowID
                        // TODO: Check ev.motion.which
                        switch ( ev.button.button ) {
                            s.SDL_BUTTON_LEFT => {
                                s.setMouseConfinedToWindow( window, false );
                                if ( dragger != null ) {
                                    dragger.?.handleRelease( xMouseFrac, yMouseFrac );
                                    dragger = null;
                                }
                            },
                            else => {}
                        }
                    },
                    s.SDL_MOUSEWHEEL => {
                        // TODO: Check ev.wheel.windowID
                        // TODO: Check ev.wheel.which
                        var zoomSteps = ev.wheel.y;
                        if ( ev.wheel.direction == s.SDL_MOUSEWHEEL_FLIPPED ) {
                            zoomSteps = -zoomSteps;
                        }
                        const zoomFactor = pow( f64, 1.12, @intToFloat( f64, zoomSteps ) );
                        const xFrac = xMouseFrac;
                        const yFrac = yMouseFrac;
                        const xCoord = xBounds.fracToValue( xFrac );
                        const yCoord = yBounds.fracToValue( yFrac );
                        xAxis.set( xFrac, xCoord, xAxis.scale*zoomFactor );
                        yAxis.set( yFrac, yCoord, yAxis.scale*zoomFactor );
                    },
                    else => {}
                }
            }
        }
    }

    return 0;
}
