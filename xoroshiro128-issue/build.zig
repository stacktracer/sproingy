const std = @import( "std" );
const Builder = std.build.Builder;

pub fn build( b: *Builder ) void {
    const mode = b.standardReleaseOptions( );

    // Problem only happens when we link gtk+-3.0
    const exe = b.addExecutable( "main", "main.zig" );
    exe.setBuildMode( mode );
    exe.linkSystemLibrary( "gtk+-3.0" );
    exe.install( );

    b.default_step.dependOn( &exe.step );

    const runCmd = exe.run( );
    runCmd.step.dependOn( b.getInstallStep( ) );
    const runStep = b.step( "run", "Run the program" );
    runStep.dependOn( &runCmd.step );
}
