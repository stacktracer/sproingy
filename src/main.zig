const std = @import( "std" );
const print = std.debug.print;
const warn = std.debug.warn;
const panic = std.debug.panic;
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
        // TODO: Include ProgramInfoLog string
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
        // TODO: Include ShaderInfoLog string
        return GLError.GenericFailure;
    }

    return shader;
}


const DummyProgram = struct {
    program: c.GLuint,
    RGBA: c.GLint,
    inXy: c.GLuint
};

fn createDummyProgram( ) !DummyProgram {
    const vertSource =
        \\#version 150 core
        \\
        \\in vec2 inXy;
        \\
        \\void main(void) {
        \\    gl_Position = vec4( inXy, 0.0, 1.0 );
        \\}
    ;

    const fragSource =
        \\#version 150 core
        \\
        \\uniform vec4 RGBA;
        \\
        \\out vec4 outRgba;
        \\
        \\void main(void) {
        \\    outRgba = vec4( 1.0, 0.0, 0.0, 1.0 );
        \\}
    ;

    const dProgram = try createProgram( vertSource, fragSource );
    return DummyProgram {
        .program = dProgram,
        .RGBA = c.glGetUniformLocation( dProgram, "RGBA" ),
        .inXy = @intCast( c.GLuint, c.glGetAttribLocation( dProgram, "inXy" ) ),
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

    const window = try createWindow( "Dummy", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 800, 800, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_SHOWN );
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
        var ev: c.SDL_Event = undefined;
        while ( c.SDL_PollEvent( &ev ) != 0 ) {
            print( "Event: {}\n", .{ ev.type } );
            switch ( ev.type ) {
                c.SDL_QUIT => running = false,
                else => {}
            }
        }

        c.glClearColor( 0.0, 0.0, 0.0, 1.0 );
        c.glClear( c.GL_COLOR_BUFFER_BIT );

        c.glUseProgram( dProgram.program );

        c.glUniform4f( dProgram.RGBA, 1.0, 0.0, 0.0, 1.0 );
        c.glBindBuffer( c.GL_ARRAY_BUFFER, dVertexCoords );
        c.glEnableVertexAttribArray( dProgram.inXy );
        c.glVertexAttribPointer( dProgram.inXy, 2, c.GL_FLOAT, c.GL_FALSE, 0, null );
        c.glDrawArrays( c.GL_TRIANGLES, 0, 3 );

        c.glUseProgram( 0 );

        c.SDL_GL_SwapWindow( window );
        c.SDL_Delay( 1 );
    }

    return 0;
}
