usingnamespace @import( "../core/core.zig" );
usingnamespace @import( "../core/gtkz.zig" );
usingnamespace @import( "../core/support.zig" );
usingnamespace @import( "cursor.zig" );

pub const TimeView = struct {
    glArea: *GtkWidget,

    axis0: Axis,
    axis1: Axis,

    bgPaintable: ClearPaintable,

    cursor: VerticalCursor,

    axisUpdatingHandler: AxisUpdatingHandler(2),
    painters: [2]*Painter,
    paintingHandler: PaintingHandler,

    axisDraggable0: AxisDraggable(1),
    draggers: [2]*Dragger,
    draggingHandler: DraggingHandler,

    // TODO: RLS would be better, but needs https://github.com/ziglang/zig/issues/2765
    pub fn init( self: *TimeView ) !void {
        self.glArea = gtk_gl_area_new( );
        gtk_gl_area_set_required_version( @ptrCast( *GtkGLArea, self.glArea ), 3, 2 );
        gtk_widget_set_events( self.glArea, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_MOTION_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_KEY_PRESS_MASK );
        gtk_widget_set_can_focus( self.glArea, 1 );

        self.axis0 = Axis.initBounds( -8.4, 8.4, 1 );
        self.axis1 = Axis.initBounds( -6.4, 6.4, 1 );

        self.bgPaintable = ClearPaintable.init( "TimeView.bgPaintable", GL_COLOR_BUFFER_BIT );
        self.bgPaintable.rgba = [4]GLfloat { 0.0, 0.0, 0.0, 1.0 };

        self.cursor = VerticalCursor.init( "TimeView.cursor", &self.axis0 );

        var _axes = [2]*Axis { &self.axis0, &self.axis1 };
        self.axisUpdatingHandler = AxisUpdatingHandler(2).init( _axes, [2]u1 { 0, 1 } );
        _ = try gtkzConnectHandler( self.glArea, "render", AxisUpdatingHandler(2).onRender, &self.axisUpdatingHandler );
        _ = try gtkzConnectHandler( self.glArea, "scroll-event", AxisUpdatingHandler(2).onMouseWheel, &self.axisUpdatingHandler );

        self.painters = [_]*Painter {
            &self.bgPaintable.painter,
            &self.cursor.painter,
        };
        self.paintingHandler = PaintingHandler.init( &self.painters );
        _ = try gtkzConnectHandler( self.glArea, "render", PaintingHandler.onRender, &self.paintingHandler );

        var _axes0 = [1]*Axis { &self.axis0 };
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

    pub fn deinit( self: *TimeView ) void {
        // FIXME: Drop self.glArea
        // FIXME: Drop self.paintingHandler
        // FIXME: Disconnect signal handlers
        // FIXME: glDeinit
    }
};
