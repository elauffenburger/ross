const std = @import("std");
const fs = std.fs;

pub fn build(b: *std.Build) !void {
    const exe = addInstall(b);
    addTests(b, exe.root_module);

    addBuildIso(b);
}

fn addInstall(b: *std.Build) *std.Build.Step.Compile {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{
            .default_target = .{
                .cpu_arch = .x86,
                .os_tag = .freestanding,
                .abi = .none,
                .cpu_features_add = blk: {
                    var res = std.Target.Cpu.Feature.Set.empty;
                    res.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

                    break :blk res;
                },
                .cpu_features_sub = blk: {
                    var res = std.Target.Cpu.Feature.Set.empty;
                    res.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
                    res.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
                    res.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
                    res.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
                    res.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));

                    break :blk res;
                },
            },
        }),
        .optimize = b.standardOptimizeOption(.{}),
        .link_libc = false,
        .link_libcpp = false,
    });

    const exe = b.addExecutable(.{
        .name = "ross",
        .root_module = exe_mod,
        .linkage = .static,
    });
    exe.entry = .{ .symbol_name = "_kmain" };
    exe.setLinkerScript(b.path("boot/link.ld"));

    b.installArtifact(exe);

    return exe;
}

fn addTests(b: *std.Build, exe_mod: *std.Build.Module) void {
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn addBuildIso(b: *std.Build) void {
    const step = b.step("build-iso", "Build iso");

    // Copy files to the iso staging dir.
    const copy_files = b.addWriteFiles();
    _ = copy_files.addCopyFile(b.path("boot/stage2_eltorito"), "out/iso/boot/grub/stage2_eltorito");
    _ = copy_files.addCopyFile(b.path("boot/menu.lst"), "out/iso/boot/grub/menu.lst");
    const kernel_elf_file = copy_files.addCopyFile(b.path("zig-out/bin/ross"), "out/iso/boot/kernel.elf");
    const iso_dir = kernel_elf_file.path(b, "../../");

    // Run mkisofs on iso staging dir.
    const mkisofs = std.Build.Step.Run.create(b, "mkisofs");
    mkisofs.addArgs(&.{
        "mkisofs",
        "-quiet",
        "-input-charset",
        "utf8",
        "-eltorito-boot",
        "boot/grub/stage2_eltorito",
        "-boot-info-table",
        "-boot-load-size",
        "4",
        "-rock",
        "-no-emul-boot",
        "-A",
        "os",
    });
    mkisofs.addArg("-o");
    const iso_file = mkisofs.addOutputFileArg(b.path("out/os.iso").getPath(b));
    mkisofs.addDirectoryArg(iso_dir);

    // Install os.iso
    const install_iso_file = b.addInstallFile(iso_file, "os.iso");

    // install -> copy_files -> mkiso -> copy_iso -> build_iso
    copy_files.step.dependOn(b.getInstallStep());
    mkisofs.step.dependOn(&copy_files.step);
    install_iso_file.step.dependOn(&mkisofs.step);
    step.dependOn(&install_iso_file.step);
}
