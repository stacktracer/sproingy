const std = @import( "std" );
const inf = std.math.inf;
const min = std.math.min;
const Allocator = std.mem.Allocator;
usingnamespace @import( "../core/util.zig" );
usingnamespace @import( "../core/core.zig" );
usingnamespace @import( "../core/gtkz.zig" );
usingnamespace @import( "../core/support.zig" );
usingnamespace @import( "staticPaintable.zig" );
usingnamespace @import( "dots.zig" );
usingnamespace @import( "../time/cursor.zig" );

pub const SpaceView = struct {
    glArea: *GtkWidget,

    axis0: Axis,
    axis1: Axis,

    bgPaintable: ClearPaintable,
    boxPaintable: StaticPaintable(4),
    dotsPaintable: DotsPaintable,

    axisUpdatingHandler: AxisUpdatingHandler(2),
    painters: [3]*Painter,
    paintingHandler: PaintingHandler,

    axisDraggable: AxisDraggable(2),
    draggers: [1]*Dragger,
    draggingHandler: DraggingHandler,

    // TODO: RLS would be better, but needs https://github.com/ziglang/zig/issues/2765
    pub fn init( self: *SpaceView, xLimits: *const [2]Interval, tCursor: *const VerticalCursor, allocator: *Allocator ) !void {
        self.glArea = gtk_gl_area_new( );
        gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, self.glArea ), 3, 2 );
        gtk_widget_set_events( self.glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_KEY_PRESS_MASK );
        gtk_widget_set_can_focus( self.glArea, 1 );

        self.axis0 = Axis.initBounds( -8.4, 8.4, 1 );
        self.axis1 = Axis.initBounds( -6.4, 6.4, 1 );

        self.bgPaintable = ClearPaintable.init( "SpaceView.bgPaintable", GL_COLOR_BUFFER_BIT );
        self.bgPaintable.rgba = [4]GLfloat { 0.4, 0.4, 0.4, 1.0 };

        var _axes = [2]*Axis { &self.axis0, &self.axis1 };

        // TODO: Replace with aspect-ratio locking
        var _axesScale = inf( f64 );
        for ( _axes ) |axis| {
            _axesScale = min( _axesScale, axis.scale );
        }
        for ( _axes ) |axis| {
            axis.scale = _axesScale;
        }

        self.boxPaintable = StaticPaintable(4).init( "SpaceView.boxPaintable", _axes, GL_TRIANGLE_STRIP );
        self.boxPaintable.rgba = [4]GLfloat { 0.0, 0.0, 0.0, 1.0 };
        const xMin0 = @floatCast( GLfloat, xLimits[0].lowerBound( ).coord );
        const xMax0 = @floatCast( GLfloat, xLimits[0].upperBound( ).coord );
        const xMin1 = @floatCast( GLfloat, xLimits[1].lowerBound( ).coord );
        const xMax1 = @floatCast( GLfloat, xLimits[1].upperBound( ).coord );
        self.boxPaintable.vCoords = [8]GLfloat { xMin0,xMax1, xMin0,xMin1, xMax0,xMax1, xMax0,xMin1 };
        self.boxPaintable.vCount = 4;

        self.dotsPaintable = DotsPaintable.init( "SpaceView.dotsPaintable", _axes, tCursor, allocator );
        self.dotsPaintable.rgba = [4]GLfloat { 1.0, 0.0, 0.0, 1.0 };

        self.axisUpdatingHandler = AxisUpdatingHandler(2).init( _axes, [2]u1 { 0, 1 } );
        _ = try gtkzConnectHandler( self.glArea, "render", AxisUpdatingHandler(2).onRender, &self.axisUpdatingHandler );
        _ = try gtkzConnectHandler( self.glArea, "scroll-event", AxisUpdatingHandler(2).onMouseWheel, &self.axisUpdatingHandler );

        self.painters = [_]*Painter {
            &self.bgPaintable.painter,
            &self.boxPaintable.painter,
            &self.dotsPaintable.painter,
        };
        self.paintingHandler = PaintingHandler.init( &self.painters );
        _ = try gtkzConnectHandler( self.glArea, "render", PaintingHandler.onRender, &self.paintingHandler );

        self.axisDraggable = AxisDraggable(2).init( _axes, [2]u1 { 0, 1 } );
        self.draggers = [_]*Dragger {
            &self.axisDraggable.dragger,
        };
        self.draggingHandler = try DraggingHandler.init( self.glArea, &self.draggers );
        _ = try gtkzConnectHandler( self.glArea, "button-press-event", DraggingHandler.onMouseDown, &self.draggingHandler );
        _ = try gtkzConnectHandler( self.glArea, "motion-notify-event", DraggingHandler.onMouseMove, &self.draggingHandler );
        _ = try gtkzConnectHandler( self.glArea, "button-release-event", DraggingHandler.onMouseUp, &self.draggingHandler );
    }

    pub fn deinit( self: *SpaceView ) void {
        // FIXME: Drop self.glArea
        // FIXME: Drop self.paintingHandler
        // FIXME: Disconnect signal handlers
        // FIXME: glDeinit
    }
};
