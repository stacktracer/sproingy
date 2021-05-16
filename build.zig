const std = @import( "std" );
const Builder = std.build.Builder;

pub fn build( b: *Builder ) void {
    const mode = b.standardReleaseOptions( );
    const exe = b.addExecutable( "dummy", "src/main.zig" );
    exe.setBuildMode( mode );

    exe.addIncludeDir( "/usr/include" );
    exe.addIncludeDir( "/usr/include/GL" );

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary( "glfw" );
    exe.linkSystemLibrary( "epoxy" );
    exe.install( );

    b.default_step.dependOn( &exe.step );

    // const runStep = b.step( "run", "Run the program" );
    // const runCmd = exe.run( );
    // runStep.dependOn( &runCmd.step );
}
