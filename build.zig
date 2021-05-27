const std = @import( "std" );
const Builder = std.build.Builder;

pub fn build( b: *Builder ) void {
    const mode = b.standardReleaseOptions( );

    const exe = b.addExecutable( "sproingy", "src/main.zig" );
    exe.setBuildMode( mode );
    exe.addIncludeDir( "include" );
    exe.addIncludeDir( "/usr/include" );
    exe.addIncludeDir( "/usr/include/GL" );
    exe.linkSystemLibrary( "gtk+-3.0" );
    exe.linkSystemLibrary( "c" );
    exe.linkSystemLibrary( "epoxy" );
    exe.install( );

    b.default_step.dependOn( &exe.step );

    const runCmd = exe.run( );
    runCmd.step.dependOn( b.getInstallStep( ) );
    const runStep = b.step( "run", "Run the program" );
    runStep.dependOn( &runCmd.step );
}
