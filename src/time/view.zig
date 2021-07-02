const std = @import( "std" );
const Allocator = std.mem.Allocator;
usingnamespace @import( "../core/core.zig" );
usingnamespace @import( "../core/gtkz.zig" );
usingnamespace @import( "../core/support.zig" );
usingnamespace @import( "cursor.zig" );
usingnamespace @import( "curve.zig" );

pub fn TimeView( comptime N: usize, comptime P: usize ) type {
    return struct {
        const Self = @This();

        glArea: *GtkWidget,

        axis0: Axis,
        axis1: Axis,

        bgPaintable: ClearPaintable,
        curvePaintable: CurvePaintable(N,P),

        cursor: VerticalCursor,

        axisUpdatingHandler0: AxisUpdatingHandler(1),
        axisUpdatingHandler1: AxisUpdatingHandler(1),
        painters: [3]*Painter,
        paintingHandler: PaintingHandler,

        axisDraggable0: AxisDraggable(1),
        draggers: [2]*Dragger,
        draggingHandler: DraggingHandler,

        // TODO: RLS would be better, but needs https://github.com/ziglang/zig/issues/2765
        pub fn init( self: *Self, allocator: *Allocator ) !void {
            self.glArea = gtk_gl_area_new( );
            gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, self.glArea ), 3, 2 );
            gtk_widget_set_events( self.glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_KEY_PRESS_MASK );
            gtk_widget_set_can_focus( self.glArea, 1 );

            self.axis0 = Axis.initBounds( -0.1, 60.0, 1 );
            self.axis1 = Axis.initBounds( 0, 400, 1 );
            var _axes = [2]*Axis { &self.axis0, &self.axis1 };
            var _axes0 = [1]*Axis { &self.axis0 };
            var _axes1 = [1]*Axis { &self.axis1 };

            self.bgPaintable = ClearPaintable.init( "TimeView.bgPaintable", GL_COLOR_BUFFER_BIT );
            self.bgPaintable.rgba = [4]GLfloat { 0.4, 0.4, 0.4, 1.0 };

            self.curvePaintable = try CurvePaintable(N,P).init( "TimeView.curvePaintable", _axes, allocator );
            self.curvePaintable.rgbKinetic = [3]GLfloat { 0.0, 0.0, 0.0 };
            self.curvePaintable.rgbPotential = [3]GLfloat { 1.0, 0.0, 0.0 };
            self.curvePaintable.rgbPotentialA = [3]GLfloat { 1.0, 1.0, 1.0 };

            self.cursor = VerticalCursor.init( "TimeView.cursor", &self.axis0 );
            self.cursor.cursor = 30.0;

            self.axisUpdatingHandler0 = AxisUpdatingHandler(1).init( _axes0, [1]u1 { 0 } );
            _ = try gtkzConnectHandler( self.glArea, "render", AxisUpdatingHandler(1).onRender, &self.axisUpdatingHandler0 );
            _ = try gtkzConnectHandler( self.glArea, "scroll-event", AxisUpdatingHandler(1).onMouseWheel, &self.axisUpdatingHandler0 );

            self.axisUpdatingHandler1 = AxisUpdatingHandler(1).init( _axes1, [1]u1 { 1 } );
            _ = try gtkzConnectHandler( self.glArea, "render", AxisUpdatingHandler(1).onRender, &self.axisUpdatingHandler1 );

            self.painters = [_]*Painter {
                &self.bgPaintable.painter,
                &self.curvePaintable.painter,
                &self.cursor.painter,
            };
            self.paintingHandler = PaintingHandler.init( &self.painters );
            _ = try gtkzConnectHandler( self.glArea, "render", PaintingHandler.onRender, &self.paintingHandler );

            self.axisDraggable0 = AxisDraggable(1).init( _axes0, [1]u1 { 0 } );
            self.draggers = [_]*Dragger {
                &self.cursor.dragger,
                &self.axisDraggable0.dragger,
            };
            self.draggingHandler = try DraggingHandler.init( self.glArea, &self.draggers );
            _ = try gtkzConnectHandler( self.glArea, "button-press-event", DraggingHandler.onMouseDown, &self.draggingHandler );
            _ = try gtkzConnectHandler( self.glArea, "motion-notify-event", DraggingHandler.onMouseMove, &self.draggingHandler );
            _ = try gtkzConnectHandler( self.glArea, "button-release-event", DraggingHandler.onMouseUp, &self.draggingHandler );
        }

        pub fn deinit( self: *Self ) void {
            // FIXME: gtk_widget_destroy( self.glArea );
            self.curvePaintable.deinit( );
            // FIXME: Disconnect signal handlers
        }
    };
}
