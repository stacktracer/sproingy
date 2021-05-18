const std = @import( "std" );
const pow = std.math.pow;
const print = std.debug.print;
const g = @import( "gl.zig" );
const s = @import( "sdl2.zig" );
const a = @import( "axis.zig" );
const Axis2 = a.Axis2;
const Vec2 = a.Vec2;
const getPixelFrac = a.getPixelFrac;
const Draggable = a.Draggable;
const Dragger = a.Dragger;
const findDragger = a.findDragger;

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
    const windowID = try s.getWindowID( window );
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

            g.glUniformInterval2( dProgram.XY_BOUNDS, bounds );
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
                        if ( ev.key.windowID == windowID ) {
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
                        }
                    },
                    s.SDL_MOUSEBUTTONDOWN => {
                        // TODO: Check ev.button.which
                        if ( ev.button.windowID == windowID ) {
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
                        }
                    },
                    s.SDL_MOUSEMOTION => {
                        // TODO: Check ev.motion.which
                        // TODO: Maybe coalesce mouse moves, but don't mix moves and drags
                        if ( ev.motion.windowID == windowID ) {
                            mouseFrac = getPixelFrac( &axis, ev.motion.x, ev.motion.y );
                            if ( dragger != null ) {
                                dragger.?.handleDrag( &axis, mouseFrac );
                            }
                        }
                    },
                    s.SDL_MOUSEBUTTONUP => {
                        // TODO: Check ev.button.which
                        if ( ev.button.windowID == windowID ) {
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
                        }
                    },
                    s.SDL_MOUSEWHEEL => {
                        // TODO: Check ev.wheel.which
                        if ( ev.wheel.windowID == windowID ) {
                            var zoomSteps = ev.wheel.y;
                            if ( ev.wheel.direction == s.SDL_MOUSEWHEEL_FLIPPED ) {
                                zoomSteps = -zoomSteps;
                            }
                            const zoomFactor = pow( f64, 1.12, @intToFloat( f64, zoomSteps ) );
                            const frac = mouseFrac;
                            const coord = bounds.fracToValue( frac );
                            const scale = Vec2.create( zoomFactor*axis.x.scale, zoomFactor*axis.y.scale );
                            axis.set( frac, coord, scale );
                        }
                    },
                    else => {}
                }
            }
        }
    }

    return 0;
}
