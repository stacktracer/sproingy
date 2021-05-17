pub usingnamespace @cImport( {
    @cInclude( "SDL2/SDL.h" );
} );

const Error = error {
    GenericFailure,
};

pub fn checkStatus( status: c_int ) !void {
    if ( status != 0 ) {
        return Error.GenericFailure;
    }
}

pub fn initSDL( flags: u32 ) !void {
    if ( SDL_Init( SDL_INIT_VIDEO ) != 0 ) {
        return Error.GenericFailure;
    }
}

pub fn createWindow( title: [*]const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: u32 ) !*SDL_Window {
    return SDL_CreateWindow( title, x, y, w, h, flags ) orelse Error.GenericFailure;
}

pub fn setGLAttr( attr: c_int, value: c_int ) Error!void {
    return checkStatus( SDL_GL_SetAttribute( @intToEnum( SDL_GLattr, attr ), value ) );
}

pub fn createGLContext( window: *SDL_Window ) !*SDL_GLContext {
    return SDL_GL_CreateContext( window ) orelse Error.GenericFailure;
}

pub fn makeGLCurrent( window: *SDL_Window, context: SDL_GLContext ) !void {
    return checkStatus( SDL_GL_MakeCurrent( window, context ) );
}

pub fn setGLSwapInterval( interval: c_int ) !void {
    return checkStatus( SDL_GL_SetSwapInterval( interval ) );
}

pub fn setMouseConfinedToWindow( window: *SDL_Window, confined: bool ) void {
    SDL_SetWindowGrab( window, fromBool( confined ) );
}

pub fn fromBool( b: bool ) SDL_bool {
    return @intToEnum( SDL_bool, if ( b ) SDL_TRUE else SDL_FALSE );
}
