usingnamespace @import( "gtkz.zig" );

pub const Dragger = struct {
    canHandlePressFn: fn ( self: *Dragger, mouse_PX: [2]f64 ) bool,
    handlePressFn: fn ( self: *Dragger, mouse_PX: [2]f64 ) void,
    handleDragFn: fn ( self: *Dragger, mouse_PX: [2]f64 ) void,
    handleReleaseFn: fn ( self: *Dragger, mouse_PX: [2]f64 ) void,

    pub fn canHandlePress( self: *Dragger, mouse_PX: [2]f64 ) bool {
        return self.canHandlePressFn( self, mouse_PX );
    }

    pub fn handlePress( self: *Dragger, mouse_PX: [2]f64 ) void {
        self.handlePressFn( self, mouse_PX );
    }

    pub fn handleDrag( self: *Dragger, mouse_PX: [2]f64 ) void {
        self.handleDragFn( self, mouse_PX );
    }

    pub fn handleRelease( self: *Dragger, mouse_PX: [2]f64 ) void {
        self.handleReleaseFn( self, mouse_PX );
    }
};

pub const DraggingHandler = struct {
    draggers: []const *Dragger,
    activeDragger: ?*Dragger = null,

    pub fn init( widget: gpointer, draggers: []const *Dragger ) !DraggingHandler {
        return DraggingHandler {
            .draggers = draggers,
        };
    }

    pub fn onMouseDown( widget: *GtkWidget, ev: *GdkEventButton, self: *DraggingHandler ) callconv(.C) gboolean {
        if ( self.activeDragger == null and ev.button == 1 ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            self.activeDragger = findDragger( self.draggers, mouse_PX );
            if ( self.activeDragger != null ) {
                self.activeDragger.?.handlePress( mouse_PX );
                gtk_widget_queue_draw( widget );
            }
        }
        return 1;
    }

    pub fn onMouseMove( widget: *GtkWidget, ev: *GdkEventMotion, self: *DraggingHandler ) callconv(.C) gboolean {
        if ( self.activeDragger != null ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            self.activeDragger.?.handleDrag( mouse_PX );
            gtk_widget_queue_draw( widget );
        }
        return 1;
    }

    pub fn onMouseUp( widget: *GtkWidget, ev: *GdkEventButton, self: *DraggingHandler ) callconv(.C) gboolean {
        if ( self.activeDragger != null and ev.button == 1 ) {
            const mouse_PX = gtkzMousePos_PX( widget, ev );
            self.activeDragger.?.handleRelease( mouse_PX );
            self.activeDragger = null;
            gtk_widget_queue_draw( widget );
        }
        return 1;
    }

    fn findDragger( draggers: []const *Dragger, mouse_PX: [2]f64 ) ?*Dragger {
        for ( draggers ) |dragger| {
            if ( dragger.canHandlePress( mouse_PX ) ) {
                return dragger;
            }
        }
        return null;
    }
};
