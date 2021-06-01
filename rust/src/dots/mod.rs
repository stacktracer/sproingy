extern crate gl;
extern crate epoxy;
extern crate simple_error;

use std::ptr;
use std::str;
use std::rc::Rc;
use std::ffi::CString;
use std::error::Error;
use std::mem::{ MaybeUninit, size_of };
use simple_error::bail;
use gl::types::*;
use crate::axis::*;

pub struct RenderContext {
    viewport_PX: [Interval; 2],
    lpxToPx: f64,
}

pub struct Dots {
    axis: Rc<[Axis; 2]>,

    size_LPX: f64,
    rgba: [GLfloat; 4],
    // coords: ,
    coordsModified: bool,

    // FIXME: Maybe an Option<DeviceResources> field?
    prog: Program,
    vbo: GLuint,
    vCount: GLsizei,
    vao: GLuint,
}

impl Dots {
    pub fn new( axis: Rc<[Axis; 2]> ) -> Dots {
        Dots {
            axis,
            size_LPX: 15.0,
            rgba: [ 1.0, 0.0, 0.0, 1.0 ],
            coords: ,
            coordsModified: true,
        }
    }

    pub fn glInit( &mut self, context: &RenderContext ) -> Result<(), Box<dyn Error>> {
        self.prog = Program::new( )?;

        gl::GenBuffers( 1, &mut self.vbo );
        gl::BindBuffer( gl::ARRAY_BUFFER, self.vbo );

        gl::GenVertexArrays( 1, &mut self.vao );
        gl::BindVertexArray( self.vao );
        gl::EnableVertexAttribArray( self.prog.inCoords );
        gl::VertexAttribPointer( self.prog.inCoords, 2, gl::FLOAT, gl::FALSE, 0, ptr::null( ) );

        Ok(())
    }

    pub fn glRender( &mut self, context: &RenderContext ) {
        if self.coordsModified {
            self.vCount = ( self.coords.items.len / 2 ) as GLsizei;
            if self.vCount > 0 {
                gl::BufferData( gl::ARRAY_BUFFER, 2*self.vCount*size_of::<GLfloat>( ), @ptrCast( *const c_void, self.coords.items.ptr ), gl::STATIC_DRAW );
            }
            self.coordsModified = false;
        }

        if self.vCount > 0 {
            let bounds = mapArray( &self.axis, &Axis::bounds );
            let size_PX = ( self.size_LPX * context.lpxToPx ) as f32;

            gl::BlendEquation( gl::FUNC_ADD );
            gl::BlendFunc( gl::ONE, gl::ONE_MINUS_SRC_ALPHA );
            gl::Enable( gl::BLEND );

            gl::Enable( gl::VERTEX_PROGRAM_POINT_SIZE );
            gl::UseProgram( self.prog.program );
            uniformInterval2( self.prog.XY_BOUNDS, bounds );
            gl::Uniform1f( self.prog.SIZE_PX, size_PX );
            gl::Uniform4fv( self.prog.RGBA, 1, self.rgba.as_ptr( ) );

            gl::BindVertexArray( self.vao );
            gl::DrawArrays( gl::POINTS, 0, self.vCount );
        }
    }

    pub fn glDeinit( &mut self, context: &RenderContext ) {
        gl::DeleteProgram( self.prog.program );
        gl::DeleteVertexArrays( 1, &self.vao );
        gl::DeleteBuffers( 1, &self.vbo );
    }
}

pub fn mapArray<A, B, F: Fn(&A)->B, const N: usize>( array: &[A; N], f: F ) -> [B; N] {
    let mut result: [B; N] = unsafe { MaybeUninit::uninit( ).assume_init( ) };
    for i in 0..N {
        result[i] = f( &array[i] );
    }
    result
}

pub fn uniformInterval2( location: GLint, interval2: [Interval; 2] ) {
    gl::Uniform4f( location,
                   interval2[0].min as GLfloat,
                   interval2[1].min as GLfloat,
                   interval2[0].span as GLfloat,
                   interval2[1].span as GLfloat );
}

struct Program {
    program: GLuint,

    XY_BOUNDS: GLint,
    SIZE_PX: GLint,
    RGBA: GLint,

    inCoords: GLuint,
}

impl Program {
    pub fn new( ) -> Result<Program, Box<dyn Error>> {
        unsafe {
            let vertSource = include_str!( "shader.vert" );
            let fragSource = include_str!( "shader.frag" );
            let program = createProgram( vertSource, fragSource )?;
            Ok( Program {
                program,
                XY_BOUNDS: getUniformLoc( program, "XY_BOUNDS" )?,
                SIZE_PX: getUniformLoc( program, "SIZE_PX" )?,
                RGBA: getUniformLoc( program, "RGBA" )?,
                inCoords: getAttribLoc( program, "inCoords" )?,
            } )
        }
    }
}

pub unsafe fn getUniformLoc( prog: GLuint, name: &str ) -> Result<GLint, Box<dyn Error>> {
    let cName = CString::new( name.as_bytes( ) )?;
    Ok( gl::GetUniformLocation( prog, cName.as_ptr( ) ) )
}

pub unsafe fn getAttribLoc( prog: GLuint, name: &str ) -> Result<GLuint, Box<dyn Error>> {
    let cName = CString::new( name.as_bytes( ) )?;
    Ok( gl::GetAttribLocation( prog, cName.as_ptr( ) ) as GLuint )
}

pub unsafe fn createProgram( vertSource: &str, fragSource: &str ) -> Result<GLuint, Box<dyn Error>> {
    let vertShader = compileShader( gl::VERTEX_SHADER, vertSource )?;
    let fragShader = compileShader( gl::FRAGMENT_SHADER, fragSource )?;
    let program = gl::CreateProgram( );
    gl::AttachShader( program, vertShader );
    gl::AttachShader( program, fragShader );
    gl::LinkProgram( program );
    gl::DetachShader( program, vertShader );
    gl::DetachShader( program, fragShader );
    gl::DeleteShader( vertShader );
    gl::DeleteShader( fragShader );
    checkLinkStatus( program )
}

pub unsafe fn checkLinkStatus( program: GLuint ) -> Result<GLuint, Box<dyn Error>> {
    let mut status = gl::FALSE as GLint;
    gl::GetProgramiv( program, gl::LINK_STATUS, &mut status );
    match status {
        1 => {
            Ok( program )
        },
        _ => {
            let mut messageSize = 0 as GLint;
            gl::GetProgramiv( program, gl::INFO_LOG_LENGTH, &mut messageSize );
            let mut message = Vec::with_capacity( messageSize as usize );
            message.set_len( ( messageSize as usize ) - 1 );
            gl::GetProgramInfoLog( program, messageSize, ptr::null_mut( ), message.as_mut_ptr( ) as *mut GLchar );
            bail!( str::from_utf8( &message )? )
        },
    }
}

pub unsafe fn compileShader( shaderType: GLenum, source: &str ) -> Result<GLuint, Box<dyn Error>> {
    let shader = gl::CreateShader( shaderType );
    let cSource = CString::new( source.as_bytes( ) )?;
    gl::ShaderSource( shader, 1, &cSource.as_ptr( ), ptr::null( ) );
    gl::CompileShader( shader );
    checkCompileStatus( shader )
}

pub unsafe fn checkCompileStatus( shader: GLuint ) -> Result<GLuint, Box<dyn Error>> {
    let mut compileStatus = gl::FALSE as GLint;
    gl::GetShaderiv( shader, gl::COMPILE_STATUS, &mut compileStatus );
    match compileStatus {
        1 => {
            Ok( shader )
        },
        _ => {
            let mut messageSize = 0 as GLint;
            gl::GetShaderiv( shader, gl::INFO_LOG_LENGTH, &mut messageSize );
            let mut message = Vec::with_capacity( messageSize as usize );
            message.set_len( ( messageSize as usize ) - 1 );
            gl::GetShaderInfoLog( shader, messageSize, ptr::null_mut( ), message.as_mut_ptr( ) as *mut GLchar );
            bail!( str::from_utf8( &message )? )
        },
    }
}
