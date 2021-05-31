#![allow(non_snake_case)]
#![allow(non_upper_case_globals)]

extern crate gl;
extern crate epoxy;
extern crate shared_library;
extern crate gtk;
extern crate gdk;
extern crate glib;

use std::ptr;
use std::rc::{ Rc, Weak };
use std::cell::RefCell;
use std::ops::DerefMut;
use gtk::prelude::*;
use gtk::{ Window, WindowType, WidgetExt, GLArea };
use gdk::EventMask;
use gdk::keys::constants::{ Escape };
use glib::clone;
use shared_library::dynamic_library::DynamicLibrary;

fn glInit( ) {
    epoxy::load_with( |s| {
        unsafe {
            match DynamicLibrary::open( None ).unwrap( ).symbol( s ) {
                Ok( v ) => v,
                Err( _ ) => ptr::null( ),
            }
        }
    } );
    gl::load_with( epoxy::get_proc_addr );
}



trait Dragger {
    fn canHandlePress( &self, mouse_PX: (f64,f64) ) -> bool;
    fn handlePress( &mut self, mouse_PX: (f64,f64) );
    fn handleDrag( &mut self, mouse_PX: (f64,f64) );
    fn handleRelease( &mut self, mouse_PX: (f64,f64) );
}

struct Model {
    draggers: Vec<Rc<RefCell<dyn Dragger>>>,
    activeDragger: RefCell<Option<Rc<RefCell<dyn Dragger>>>>,
}

struct Axis2 {
    viewport_PX: (f64,f64,f64,f64),
    tieFrac: (f64,f64),
    tieCoord: (f64,f64),
    scale: (f64,f64),
    grabCoord: (f64,f64),
}

impl Axis2 {
    fn new( viewport_PX: (f64,f64,f64,f64) ) -> Axis2 {
        Axis2 {
            viewport_PX: viewport_PX,
            tieFrac: ( 0.5, 0.5 ),
            tieCoord: ( 0.0, 0.0 ),
            scale: ( 1000.0, 1000.0 ),
            grabCoord: ( 0.0, 0.0 ),
        }
    }
}

fn pxToAxisFrac( axis: &Axis2, loc_PX: (f64,f64) ) -> (f64,f64) {
    // FIXME
    return ( 0.5, 0.5 );
}

impl Dragger for Axis2 {
    fn canHandlePress( &self, mouse_PX: (f64,f64) ) -> bool {
        let mouse_FRAC = pxToAxisFrac( self, mouse_PX );
        0.0 <= mouse_FRAC.0 && mouse_FRAC.0 <= 1.0 && 0.0 <= mouse_FRAC.1 && mouse_FRAC.1 <= 1.0
    }

    fn handlePress( &mut self, mouse_PX: (f64,f64) ) {
        println!( "handlePress {:?}", mouse_PX );
        // FIXME
        self.grabCoord = ( 0.0, 0.0 );
    }

    fn handleDrag( &mut self, mouse_PX: (f64,f64) ) {
        println!( "handleDrag {:?}", mouse_PX );
        // FIXME
    }

    fn handleRelease( &mut self, mouse_PX: (f64,f64) ) {
        println!( "handleRelease {:?}", mouse_PX );
        // FIXME
    }
}

fn lpxToPx( widget: &impl WidgetExt, xy_LPX: (f64,f64) ) -> (f64,f64) {
    let scale = widget.get_scale_factor( ) as f64;
    ( scale*xy_LPX.0 + 0.5, scale*xy_LPX.1 + 0.5 )
}

fn main( ) {
    glInit( );
    gtk::init( ).unwrap( );

    let glArea = GLArea::new( );
    glArea.set_events( EventMask::POINTER_MOTION_MASK | EventMask::BUTTON_PRESS_MASK | EventMask::BUTTON_MOTION_MASK | EventMask::BUTTON_RELEASE_MASK | EventMask::SCROLL_MASK | EventMask::SMOOTH_SCROLL_MASK | EventMask::KEY_PRESS_MASK );
    glArea.set_can_focus( true );

    let window = Window::new( WindowType::Toplevel );
    window.set_title( "Sproingy" );
    window.set_default_size( 480, 360 );
    window.add( &glArea );

    let axis = Rc::new( RefCell::new( Axis2::new( ( 0.0, 0.0, 480.0, 360.0 ) ) ) );

    let model = Rc::new( Model {
        draggers: vec! [ axis.clone( ) ],
        activeDragger: RefCell::new( None ),
    } );

    glArea.connect_render( |_, _| {
        unsafe {
            gl::ClearColor( 0.3, 0.3, 0.3, 1.0 );
            gl::Clear( epoxy::COLOR_BUFFER_BIT );
        }
        Inhibit( false )
    } );

    glArea.connect_button_press_event( clone!(
        @weak model => @default-panic,
        move |glArea, ev| {
            if ev.get_button( ) == 1 {
                let mouse_PX = lpxToPx( glArea, ev.get_position( ) );
                for dragger in model.draggers.iter( ) {
                    if dragger.borrow( ).canHandlePress( mouse_PX ) {
                        *model.activeDragger.borrow_mut( ) = Some( Rc::clone( dragger ) );
                        break;
                    }
                }
                if let Some( dragger ) = &*model.activeDragger.borrow( ) {
                    dragger.borrow_mut( ).handlePress( mouse_PX );
                }
            }
            Inhibit( true )
        }
     ) );

    glArea.connect_motion_notify_event( clone!(
        @weak model => @default-panic,
        move |glArea, ev| {
            if let Some( dragger ) = &*model.activeDragger.borrow( ) {
                let mouse_PX = lpxToPx( glArea, ev.get_position( ) );
                dragger.borrow_mut( ).handleDrag( mouse_PX );
            }
            Inhibit( true )
        }
    ) );

    glArea.connect_button_release_event( clone!(
        @weak model => @default-panic,
        move |glArea, ev| {
            if let Some( dragger ) = &*model.activeDragger.borrow( ) {
                let mouse_PX = lpxToPx( glArea, ev.get_position( ) );
                dragger.borrow_mut( ).handleRelease( mouse_PX );
            }
            *model.activeDragger.borrow_mut( ) = None;
            Inhibit( true )
        }
    ) );

    glArea.connect_key_press_event( clone!(
        @weak window => @default-panic,
        move |_, ev| {
            match ev.get_keyval( ) {
                Escape => window.close( ),
                _ => ( ),
            }
            Inhibit( true )
        }
    ) );

    window.connect_delete_event( |_, _| {
        gtk::main_quit( );
        Inhibit( false )
    } );

    window.show_all( );
    gtk::main( );
}
