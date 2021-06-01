pub trait Dragger {
    fn canHandlePress( &self, mouse_PX: [f64; 2] ) -> bool;
    fn handlePress( &mut self, mouse_PX: [f64; 2] );
    fn handleDrag( &mut self, mouse_PX: [f64; 2] );
    fn handleRelease( &mut self, mouse_PX: [f64; 2] );
}

pub struct Interval {
    /// Inclusive lower bound.
    pub min: f64,

    /// Difference between min and exclusive upper bound.
    pub span: f64,
}

impl Interval {
    pub fn new( min: f64, span: f64 ) -> Interval {
        Interval { min, span }
    }

    pub fn withMinMax( min: f64, max: f64 ) -> Interval {
        Interval::new( min, max - min )
    }

    pub fn valueToFrac( &self, value: f64 ) -> f64 {
        ( value - self.min ) / self.span
    }

    pub fn fracToValue( &self, frac: f64 ) -> f64 {
        self.min + frac*self.span
    }
}

pub struct Axis {
    viewport_PX: Interval,
    tieFrac: f64,
    tieCoord: f64,
    scale: f64,
    grabCoord: f64,
}

impl Axis {
    pub fn new( viewport_PX: Interval ) -> Axis {
        Axis {
            scale: viewport_PX.span / 10.0,
            viewport_PX,
            tieFrac: 0.5,
            tieCoord: 0.0,
            grabCoord: 0.0,
        }
    }

    pub fn withSize_PX( viewportSize_PX: f64 ) -> Axis {
        Axis::new( Interval::new( 0.0, viewportSize_PX ) )
    }

    pub fn bounds( &self ) -> Interval {
        let span = self.viewport_PX.span / self.scale;
        let min = self.tieCoord - self.tieFrac*span;
        Interval { min, span }
    }

    pub fn pxToFrac( &self, px: f64 ) -> f64 {
        self.viewport_PX.valueToFrac( px )
    }

    pub fn pxToCoord( &self, px: f64 ) -> f64 {
        self.bounds( ).fracToValue( self.pxToFrac( px ) )
    }

    pub fn set( &mut self, frac: f64, coord: f64, scale: f64 ) {
        let span = self.viewport_PX.span / scale;
        self.tieCoord = coord + ( self.tieFrac - frac )*span;
        self.scale = scale;
    }
}

impl Dragger for [Axis; 2] {
    fn canHandlePress( &self, mouse_PX: [f64; 2] ) -> bool {
        for i in 0..2 {
            let mouse_FRAC = self[i].pxToFrac( mouse_PX[i] );
            if mouse_FRAC < 0.0 || mouse_FRAC > 1.0 {
                return false;
            }
        }
        true
    }

    fn handlePress( &mut self, mouse_PX: [f64; 2] ) {
        for i in 0..2 {
            self[i].grabCoord = self[i].pxToCoord( mouse_PX[i] );
        }
    }

    fn handleDrag( &mut self, mouse_PX: [f64; 2] ) {
        for i in 0..2 {
            let mouse_FRAC = self[i].pxToFrac( mouse_PX[i] );
            self[i].set( mouse_FRAC, self[i].grabCoord, self[i].scale );
        }
    }

    fn handleRelease( &mut self, mouse_PX: [f64; 2] ) {
        for i in 0..2 {
            let mouse_FRAC = self[i].pxToFrac( mouse_PX[i] );
            self[i].set( mouse_FRAC, self[i].grabCoord, self[i].scale );
        }
    }
}
