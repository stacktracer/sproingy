const std = @import( "std" );
const pow = std.math.pow;
const nan = std.math.nan;
const print = std.debug.print;
const g = @import( "gl.zig" );
const s = @import( "sdl2.zig" );


const Dragger = struct {
    handlePressImpl: fn ( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void,
    handleDragImpl: fn ( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void,
    handleReleaseImpl: fn ( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void,

    fn handlePress( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        self.handlePressImpl( self, axis, mouseFrac );
    }

    fn handleDrag( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        self.handleDragImpl( self, axis, mouseFrac );
    }

    fn handleRelease( self: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        self.handleReleaseImpl( self, axis, mouseFrac );
    }
};

const Draggable = struct {
    getDraggerImpl: fn ( self: *Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger,

    fn getDragger( self: *Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger {
        return self.getDraggerImpl( self, axis, mouseFrac );
    }
};

fn findDragger( draggables: []*Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger {
    for ( draggables ) |draggable| {
        const dragger = draggable.getDragger( axis, mouseFrac );
        if ( dragger != null ) {
            return dragger;
        }
    }
    return null;
}

// TODO: Move to a utilities file
const Vec2 = struct {
    x: f64,
    y: f64,

    fn create( x: f64, y: f64 ) Vec2 {
        return Vec2 {
            .x = x,
            .y = y,
        };
    }

    fn set( self: *Vec2, x: f64, y: f64 ) void {
        self.x = x;
        self.y = y;
    }
};

const Interval1 = struct {
    /// Inclusive lower bound.
    min: f64,

    /// Difference between min and exclusive upper bound.
    span: f64,

    fn create( min: f64, span: f64 ) Interval1 {
        return Interval1 {
            .min = min,
            .span = span,
        };
    }

    fn createWithMinMax( min: f64, max: f64 ) Interval1 {
        return Interval1.create( min, max - min );
    }

    fn set( self: *Interval1, min: f64, span: f64 ) void {
        self.min = min;
        self.span = span;
    }

    fn valueToFrac( self: *const Interval1, value: f64 ) f64 {
        return ( ( value - self.min ) / self.span );
    }

    fn fracToValue( self: *const Interval1, frac: f64 ) f64 {
        return ( self.min + frac*self.span );
    }
};

const Axis1 = struct {
    viewport_PX: Interval1,

    // TODO: Any way to make tieFrac const?
    tieFrac: f64,
    tieCoord: f64,
    scale: f64,

    fn create( min: f64, span: f64 ) Axis1 {
        var axis = Axis1 {
            .viewport_PX = Interval1.createWithMinMax( 0, 1000 ),
            .tieFrac = 0.5,
            .tieCoord = 0.0,
            .scale = 1000,
        };
        axis.setBounds( Interval1.create( min, span ) );
        return axis;
    }

    fn createWithMinMax( min: f64, max: f64 ) Axis1 {
        return Axis1.create( min, max - min );
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

const Interval2 = struct {
    x: Interval1,
    y: Interval1,

    fn create( xMin: f64, yMin: f64, xSpan: f64, ySpan: f64 ) Interval2 {
        return Interval2 {
            .x = Interval1.create( xMin, xSpan ),
            .y = Interval1.create( yMin, ySpan ),
        };
    }

    fn valueToFrac( self: *const Interval2, value: Vec2 ) Vec2 {
        return Vec2 {
            .x = self.x.valueToFrac( value.x ),
            .y = self.y.valueToFrac( value.y ),
        };
    }

    fn fracToValue( self: *const Interval2, frac: Vec2 ) Vec2 {
        return Vec2 {
            .x = self.x.fracToValue( frac.x ),
            .y = self.y.fracToValue( frac.y ),
        };
    }
};

fn glUniformInterval2( location: g.GLint, interval: Interval2 ) void {
    g.glUniform4f( location,
                   @floatCast( f32, interval.x.min ),
                   @floatCast( f32, interval.y.min ),
                   @floatCast( f32, interval.x.span ),
                   @floatCast( f32, interval.y.span ) );
}

const Axis2Panner = struct {
    dragger: Dragger,
    grabCoord: Vec2,

    /// Pass this same axis to ensuing handleDrag and handleRelease calls
    fn handlePress( dragger: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        const self = @fieldParentPtr( Axis2Panner, "dragger", dragger );
        self.grabCoord = axis.getBounds( ).fracToValue( mouseFrac );
    }

    /// Pass the same axis that was passed to the preceding handlePress call
    fn handleDrag( dragger: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        const self = @fieldParentPtr( Axis2Panner, "dragger", dragger );
        axis.pan( mouseFrac, self.grabCoord );
    }

    /// Pass the same axis that was passed to the preceding handlePress call
    fn handleRelease( dragger: *Dragger, axis: *Axis2, mouseFrac: Vec2 ) void {
        const self = @fieldParentPtr( Axis2Panner, "dragger", dragger );
        axis.pan( mouseFrac, self.grabCoord );
    }

    fn create( ) Axis2Panner {
        return Axis2Panner {
            .grabCoord = Vec2.create( nan( f64 ), nan( f64 ) ),
            .dragger = Dragger {
                .handlePressImpl = handlePress,
                .handleDragImpl = handleDrag,
                .handleReleaseImpl = handleRelease,
            },
        };
    }
};

const Axis2 = struct {
    x: Axis1,
    y: Axis1,
    panner: Axis2Panner,
    draggable: Draggable,

    fn getDragger( draggable: *Draggable, axis: *const Axis2, mouseFrac: Vec2 ) ?*Dragger {
        const self = @fieldParentPtr( Axis2, "draggable", draggable );
        return &self.panner.dragger;
    }

    fn create( xMin: f64, yMin: f64, xSpan: f64, ySpan: f64 ) Axis2 {
        return Axis2 {
            .x = Axis1.create( xMin, xSpan ),
            .y = Axis1.create( yMin, ySpan ),
            .panner = Axis2Panner.create( ),
            .draggable = Draggable {
                .getDraggerImpl = getDragger,
            },
        };
    }

    fn createWithMinMax( xMin: f64, yMin: f64, xMax: f64, yMax: f64 ) Axis2 {
        return Axis2.create( xMin, yMin, xMax - xMin, yMax - yMin );
    }

    // TODO: Maybe don't return by value?
    fn getViewport_PX( self: *const Axis2 ) Interval2 {
        return Interval2 {
            .x = self.x.viewport_PX,
            .y = self.y.viewport_PX,
        };
    }

    fn pan( self: *Axis2, frac: Vec2, coord: Vec2 ) void {
        // TODO: Not sure this will work well with axis constraints
        self.x.pan( frac.x, coord.x );
        self.y.pan( frac.y, coord.y );
    }

    fn set( self: *Axis2, frac: Vec2, coord: Vec2, scale: Vec2 ) void {
        // TODO: Not sure this will work well with axis constraints
        self.x.set( frac.x, coord.x, scale.x );
        self.y.set( frac.y, coord.y, scale.y );
    }

    // TODO: Maybe don't return by value?
    fn getBounds( self: *const Axis2 ) Interval2 {
        return Interval2 {
            .x = self.x.getBounds( ),
            .y = self.y.getBounds( ),
        };
    }
};

fn getPixelFrac( axis: *const Axis2, x: c_int, y: c_int ) Vec2 {
    // TODO: Adjust coords for HiDPI
    // Add 0.5 to get the center of the pixel
    const coord_PX = Vec2.create( @intToFloat( f64, x ) + 0.5, @intToFloat( f64, y ) + 0.5 );
    var frac = axis.getViewport_PX( ).valueToFrac( coord_PX );
    // Invert so y increases upward
    frac.y = 1.0 - frac.y;
    return frac;
}


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

    var axis = Axis2.createWithMinMax( -1, -1, 1, 1 );
    var mouseFrac = Vec2.create( 0.5, 0.5 );
    var draggables = [_]*Draggable{ &axis.draggable };
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
        axis.x.viewport_PX.set( 0, @intToFloat( f64, wDrawable_PX ) );
        axis.y.viewport_PX.set( 0, @intToFloat( f64, hDrawable_PX ) );
        const bounds = axis.getBounds( );

        g.glClearColor( 0.0, 0.0, 0.0, 1.0 );
        g.glClear( g.GL_COLOR_BUFFER_BIT );

        {
            g.enablePremultipliedAlphaBlending( );
            defer g.disableBlending( );

            g.glUseProgram( dProgram.program );
            defer g.glUseProgram( 0 );

            g.glEnable( g.GL_VERTEX_PROGRAM_POINT_SIZE );
            defer g.glDisable( g.GL_VERTEX_PROGRAM_POINT_SIZE );

            glUniformInterval2( dProgram.XY_BOUNDS, bounds );
            g.glUniform1f( dProgram.SIZE_PX, 15 );
            g.glUniform4f( dProgram.RGBA, 1.0, 0.0, 0.0, 1.0 );
            g.glBindBuffer( g.GL_ARRAY_BUFFER, dVertexCoords );
            g.glEnableVertexAttribArray( dProgram.inCoords );
            g.glVertexAttribPointer( dProgram.inCoords, 2, g.GL_FLOAT, g.GL_FALSE, 0, null );
            g.glDrawArrays( g.GL_POINTS, 0, hVertexCoords.len );
        }

        s.SDL_GL_SwapWindow( window );
        s.SDL_Delay( 1 );

        // TODO: Does SDL do any event coalescing?
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
                                mouseFrac = getPixelFrac( &axis, ev.button.x, ev.button.y );
                                dragger = findDragger( draggables[0..], &axis, mouseFrac );
                                if ( dragger != null ) {
                                    dragger.?.handlePress( &axis, mouseFrac );
                                }
                            },
                            else => {}
                        }
                    },
                    s.SDL_MOUSEMOTION => {
                        // TODO: Check ev.motion.windowID
                        // TODO: Check ev.motion.which
                        mouseFrac = getPixelFrac( &axis, ev.motion.x, ev.motion.y );
                        if ( dragger != null ) {
                            dragger.?.handleDrag( &axis, mouseFrac );
                        }
                    },
                    s.SDL_MOUSEBUTTONUP => {
                        // TODO: Check ev.motion.windowID
                        // TODO: Check ev.motion.which
                        switch ( ev.button.button ) {
                            s.SDL_BUTTON_LEFT => {
                                s.setMouseConfinedToWindow( window, false );
                                mouseFrac = getPixelFrac( &axis, ev.button.x, ev.button.y );
                                if ( dragger != null ) {
                                    dragger.?.handleRelease( &axis, mouseFrac );
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
                        const frac = mouseFrac;
                        const coord = bounds.fracToValue( frac );
                        const scale = Vec2.create( zoomFactor*axis.x.scale, zoomFactor*axis.y.scale );
                        axis.set( frac, coord, scale );
                    },
                    else => {}
                }
            }
        }
    }

    return 0;
}
