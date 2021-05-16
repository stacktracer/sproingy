const std = @import( "std" );
const print = std.debug.print;
const warn = std.debug.warn;
const panic = std.debug.panic;
const c = @import( "c.zig" );


const GLError = error {
    FailedToCompileShader,
    FailedToLinkProgram,
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
        return GLError.FailedToLinkProgram;
    }

    return program;
}

pub fn compileShaderSource( shaderType: c.GLenum, source: [*:0]const u8 ) !c.GLuint {
    const shader = c.glCreateShader( shaderType );
    // var sources: [*]const [*:0]const u8 = ( [_][*:0]const u8{ source } )[0..1];
    // c.glShaderSource( shader, 1, sources, null );
    c.glShaderSource( shader, 1, &source, null );
    c.glCompileShader( shader );

    var compileStatus: c.GLint = 0;
    c.glGetShaderiv( shader, c.GL_COMPILE_STATUS, &compileStatus );
    if ( compileStatus != c.GL_TRUE ) {
        // TODO: Include ShaderInfoLog string
        return GLError.FailedToCompileShader;
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


fn handleGlfwError( err: c_int, message: [*c]const u8 ) callconv(.C) void {
    warn( "GLFW error: {s}\n", .{ message } );
}

fn handleGlfwKeyEvent( window: ?*c.GLFWwindow, key: c_int, scanCode: c_int, action: c_int, mods: c_int ) callconv(.C) void {
    print( "GLFW key event: {}, {}, {}\n", .{ key, mods, action } );
}

pub fn main( ) !u8 {
    _ = c.glfwSetErrorCallback( handleGlfwError );

    if ( c.glfwInit( ) == c.GL_FALSE ) {
        panic( "GLFW init failed\n", .{} );
    }
    defer c.glfwTerminate( );

    c.glfwWindowHint( c.GLFW_CONTEXT_VERSION_MAJOR, 4 );
    c.glfwWindowHint( c.GLFW_CONTEXT_VERSION_MINOR, 1 );
    c.glfwWindowHint( c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_FALSE );
    c.glfwWindowHint( c.GLFW_OPENGL_DEBUG_CONTEXT, c.GL_TRUE );
    c.glfwWindowHint( c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE );
    c.glfwWindowHint( c.GLFW_DEPTH_BITS, 0 );
    c.glfwWindowHint( c.GLFW_STENCIL_BITS, 0 );
    c.glfwWindowHint( c.GLFW_DECORATED, c.GL_FALSE );
    c.glfwWindowHint( c.GLFW_RESIZABLE, c.GL_TRUE );

    var window = c.glfwCreateWindow( 800, 800, "Dummy", null, null ) orelse {
        panic( "GLFW window creation failed\n", .{} );
    };
    defer c.glfwDestroyWindow( window );

    _ = c.glfwSetKeyCallback( window, handleGlfwKeyEvent );
    c.glfwMakeContextCurrent( window );
    c.glfwSwapInterval( 1 );

    var vao: c.GLuint = 0;
    c.glGenVertexArrays( 1, &vao );
    c.glBindVertexArray( vao );
    defer c.glDeleteVertexArrays( 1, &vao );

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

    while ( c.glfwWindowShouldClose( window ) == c.GL_FALSE ) {
        const frameTime_GLFWSEC = c.glfwGetTime( );

        c.glClearColor( 0.0, 0.0, 0.0, 1.0 );
        c.glClear( c.GL_COLOR_BUFFER_BIT );

        c.glUseProgram( dProgram.program );

        c.glUniform4f( dProgram.RGBA, 1.0, 0.0, 0.0, 1.0 );
        c.glBindBuffer( c.GL_ARRAY_BUFFER, dVertexCoords );
        c.glEnableVertexAttribArray( dProgram.inXy );
        c.glVertexAttribPointer( dProgram.inXy, 2, c.GL_FLOAT, c.GL_FALSE, 0, null );
        c.glDrawArrays( c.GL_TRIANGLES, 0, 3 );

        c.glUseProgram( 0 );

        c.glfwSwapBuffers( window );
        c.glfwPollEvents( );
    }

    return 0;
}
