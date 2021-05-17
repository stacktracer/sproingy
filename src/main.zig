const std = @import( "std" );
const print = std.debug.print;
const warn = std.debug.warn;
const panic = std.debug.panic;
const cAllocator = std.heap.c_allocator;
const c = @import( "c.zig" );


const GLError = error {
    GenericFailure,
};

pub fn createProgram( vertSource: [*:0]const u8, fragSource: [*:0]const u8 ) !c.GLuint {
    const vertShader = try compileShaderSource( c.GL_VERTEX_SHADER, vertSource );
    defer c.glDeleteShader( vertShader );

    const fragShader = try compileShaderSource( c.GL_FRAGMENT_SHADER, fragSource );
    defer c.glDeleteShader( fragShader );

    const program = c.glCreateProgram( );

    c.glAttachShader( program, vertShader );
    defer c.glDetachShader( program, vertShader );

    c.glAttachShader( program, fragShader );
    defer c.glDetachShader( program, fragShader );

    c.glLinkProgram( program );

    var linkStatus: c.GLint = 0;
    c.glGetProgramiv( program, c.GL_LINK_STATUS, &linkStatus );
    if ( linkStatus != c.GL_TRUE ) {
        var messageSize: c.GLint = undefined;
        c.glGetProgramiv( program, c.GL_INFO_LOG_LENGTH, &messageSize );
        const message = try cAllocator.alloc( u8, @intCast( usize, messageSize ) );
        defer cAllocator.free( message );
        c.glGetProgramInfoLog( program, messageSize, null, message.ptr );
        warn( "Shader linking failed:\n{s}\n", .{ message } );
        // TODO: Make message available to caller
        return GLError.GenericFailure;
    }

    return program;
}

pub fn compileShaderSource( shaderType: c.GLenum, source: [*:0]const u8 ) !c.GLuint {
    const shader = c.glCreateShader( shaderType );
    c.glShaderSource( shader, 1, &source, null );
    c.glCompileShader( shader );

    var compileStatus: c.GLint = 0;
    c.glGetShaderiv( shader, c.GL_COMPILE_STATUS, &compileStatus );
    if ( compileStatus != c.GL_TRUE ) {
        var messageSize: c.GLint = undefined;
        c.glGetShaderiv( shader, c.GL_INFO_LOG_LENGTH, &messageSize );
        const message = try cAllocator.alloc( u8, @intCast( usize, messageSize ) );
        defer cAllocator.free( message );
        c.glGetShaderInfoLog( shader, messageSize, null, message.ptr );
        warn( "Shader compilation failed:\n{s}\n", .{ message } );
        // TODO: Make message available to caller
        return GLError.GenericFailure;
    }

    return shader;
}

pub fn enablePremultipliedAlphaBlending( ) void {
    c.glBlendEquation( c.GL_FUNC_ADD );
    c.glBlendFunc( c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA );
    c.glEnable( c.GL_BLEND );
}

pub fn disableBlending( ) void {
    c.glDisable( c.GL_BLEND );
}


const DummyProgram = struct {
    program: c.GLuint,

    XY_BOUNDS: c.GLint,
    SIZE_PX: c.GLint,
    RGBA: c.GLint,

    /// x_XAXIS, y_YAXIS
    inCoords: c.GLuint
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

    const dProgram = try createProgram( vertSource, fragSource );
    return DummyProgram {
        .program = dProgram,
        .XY_BOUNDS = c.glGetUniformLocation( dProgram, "XY_BOUNDS" ),
        .SIZE_PX = c.glGetUniformLocation( dProgram, "SIZE_PX" ),
        .RGBA = c.glGetUniformLocation( dProgram, "RGBA" ),
        .inCoords = @intCast( c.GLuint, c.glGetAttribLocation( dProgram, "inCoords" ) ),
    };
}


const SDLError = error {
    GenericFailure,
};

pub fn checkStatus( status: c_int ) SDLError!void {
    if ( status != 0 ) {
        return SDLError.GenericFailure;
    }
}

pub fn initSDL( flags: u32 ) SDLError!void {
    if ( c.SDL_Init( c.SDL_INIT_VIDEO ) != 0 ) {
        return SDLError.GenericFailure;
    }
}

pub fn createWindow( title: [*]const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: u32 ) SDLError!*c.SDL_Window {
    return c.SDL_CreateWindow( title, x, y, w, h, flags ) orelse SDLError.GenericFailure;
}

pub fn setGLAttr( attr: c_int, value: c_int ) SDLError!void {
    return checkStatus( c.SDL_GL_SetAttribute( @intToEnum( c.SDL_GLattr, attr ), value ) );
}

pub fn createGLContext( window: *c.SDL_Window ) SDLError!*c.SDL_GLContext {
    return c.SDL_GL_CreateContext( window ) orelse SDLError.GenericFailure;
}

pub fn makeGLCurrent( window: *c.SDL_Window, context: c.SDL_GLContext ) SDLError!void {
    return checkStatus( c.SDL_GL_MakeCurrent( window, context ) );
}

pub fn setGLSwapInterval( interval: c_int ) SDLError!void {
    return checkStatus( c.SDL_GL_SetSwapInterval( interval ) );
}


pub fn main( ) !u8 {
    try initSDL( c.SDL_INIT_VIDEO );
    defer c.SDL_Quit( );

    try setGLAttr( c.SDL_GL_DOUBLEBUFFER, 1 );
    try setGLAttr( c.SDL_GL_ACCELERATED_VISUAL, 1 );
    try setGLAttr( c.SDL_GL_RED_SIZE, 8 );
    try setGLAttr( c.SDL_GL_GREEN_SIZE, 8 );
    try setGLAttr( c.SDL_GL_BLUE_SIZE, 8 );
    try setGLAttr( c.SDL_GL_ALPHA_SIZE, 8 );
    try setGLAttr( c.SDL_GL_CONTEXT_MAJOR_VERSION, 3 );
    try setGLAttr( c.SDL_GL_CONTEXT_MINOR_VERSION, 2 );
    try setGLAttr( c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE );

    const window = try createWindow( "Dummy", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 800, 800, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_SHOWN );
    defer c.SDL_DestroyWindow( window );

    const context = c.SDL_GL_CreateContext( window );
    defer c.SDL_GL_DeleteContext( context );

    try makeGLCurrent( window, context );
    try setGLSwapInterval( 0 );

    var vao: c.GLuint = 0;
    c.glGenVertexArrays( 1, &vao );
    defer c.glDeleteVertexArrays( 1, &vao );
    c.glBindVertexArray( vao );

    const hVertexCoords = [_][2]c.GLfloat{
        [_]c.GLfloat{ 0.0, 0.0 },
        [_]c.GLfloat{ 0.5, 0.0 },
        [_]c.GLfloat{ 0.0, 0.5 },
    };
    var dVertexCoords = @intCast( c.GLuint, 0 );
    c.glGenBuffers( 1, &dVertexCoords );
    c.glBindBuffer( c.GL_ARRAY_BUFFER, dVertexCoords );
    c.glBufferData( c.GL_ARRAY_BUFFER, hVertexCoords.len*2*@sizeOf( c.GLfloat ), @ptrCast( *const c_void, &hVertexCoords[0][0] ), c.GL_STATIC_DRAW );

    const dProgram = try createDummyProgram( );

    var running = true;
    while ( running ) {
        var wDrawable: c_int = undefined;
        var hDrawable: c_int = undefined;
        c.SDL_GL_GetDrawableSize( window, &wDrawable, &hDrawable );
        c.glViewport( 0, 0, wDrawable, hDrawable );

        c.glClearColor( 0.0, 0.0, 0.0, 1.0 );
        c.glClear( c.GL_COLOR_BUFFER_BIT );

        {
            enablePremultipliedAlphaBlending( );
            defer disableBlending( );

            c.glUseProgram( dProgram.program );
            defer c.glUseProgram( 0 );

            c.glEnable( c.GL_VERTEX_PROGRAM_POINT_SIZE );
            defer c.glDisable( c.GL_VERTEX_PROGRAM_POINT_SIZE );

            c.glUniform4f( dProgram.XY_BOUNDS, -1.0, -1.0, 2.0, 2.0 );
            c.glUniform1f( dProgram.SIZE_PX, 15 );
            c.glUniform4f( dProgram.RGBA, 1.0, 0.0, 0.0, 1.0 );
            c.glBindBuffer( c.GL_ARRAY_BUFFER, dVertexCoords );
            c.glEnableVertexAttribArray( dProgram.inCoords );
            c.glVertexAttribPointer( dProgram.inCoords, 2, c.GL_FLOAT, c.GL_FALSE, 0, null );
            c.glDrawArrays( c.GL_POINTS, 0, hVertexCoords.len );
        }

        c.SDL_GL_SwapWindow( window );
        c.SDL_Delay( 1 );

        while ( true ) {
            var ev: c.SDL_Event = undefined;
            if ( c.SDL_PollEvent( &ev ) == 0 ) {
                break;
            }
            else {
                switch ( ev.type ) {
                    c.SDL_QUIT => running = false,
                    c.SDL_KEYDOWN => {
                        const keysym = ev.key.keysym;
                        switch ( keysym.sym ) {
                            c.SDLK_ESCAPE => running = false,
                            c.SDLK_w => {
                                if ( @intCast( c_int, keysym.mod ) & c.KMOD_CTRL != 0 ) {
                                    running = false;
                                }
                            },
                            else => {}
                        }
                    },
                    else => {}
                }
            }
        }
    }

    return 0;
}
