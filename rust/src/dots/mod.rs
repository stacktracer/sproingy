extern crate gl;
extern crate epoxy;
extern crate simple_error;

use std::ptr;
use std::str;
use std::rc::Rc;
use std::ffi::CString;
use std::error::Error;
use simple_error::bail;

use gl::types::*;

pub struct Dots {
    // axis: Rc<[Axis; 2]>

    // size_LPX: f64,
    // rgba: [gl::GLfloat; 4],
    // coords: ,
    // coordsModified: bool,

    // FIXME: Maybe an Option<DeviceResources> field?

    prog: Program,
}


impl Dots {
    // FIXME
    // pub fn new( axis: Rc<[Axis; 2]> ) -> Dots {
    //     Dots {
    //         axis,
    //         size_LPX: 15,
    //         rgba:
    //     }
    // }

    pub fn glInit( &mut self ) -> Result<(), Box<dyn Error>> {
        self.prog = Program::new( )?;
        Ok(())
    }

    pub fn glRender( ) {
        // FIXME
    }
}

struct Program {
    prog: GLuint,

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
            let prog = createProgram( vertSource, fragSource )?;
            Ok( Program {
                prog,
                XY_BOUNDS: getUniformLoc( prog, "XY_BOUNDS" )?,
                SIZE_PX: getUniformLoc( prog, "SIZE_PX" )?,
                RGBA: getUniformLoc( prog, "RGBA" )?,
                inCoords: getAttribLoc( prog, "inCoords" )?,
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
