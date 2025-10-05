const std = @import("std");

pub fn build(b: *std.Build) !void {
    const kernelc = addInstall(b);
    addTests(b, kernelc);
}

fn addInstall(b: *std.Build) *std.Build.Step.Compile {
    const kernel = b.addExecutable(.{
        // NOTE: this should only matter if we're compiling an x64 kernel (in which case, check out https://gitlab.com/x86-psABIs/x86-64-ABI/-/jobs/artifacts/master/raw/x86-64-ABI/abi.pdf?job=build).
        // .code_model = .kernel,

        .name = "ross",
        .linkage = .static,
        .root_module = b.createModule(.{
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
            .dwarf_format = .@"32",

            // Disable red zone to prevent stack-clobbering nonsense in IRQ handlers.
            .red_zone = false,
        }),
    });
    kernel.entry = .{ .symbol_name = "_kentry" };
    kernel.setLinkerScript(b.path("src/asm/link.ld"));

    // kernel.setVerboseLink(true);

    // Compile and link asm libs.
    const asm_dir = b.path("src/asm/");
    inline for ([_][]const u8{ "main.s", "gdt.s", "multitask.s", "stack.s", "vmem.s" }) |asm_src| {
        // Create nasm run step.
        const nasm = std.Build.Step.Run.create(b, std.fmt.comptimePrint("Build asm lib ({s})", .{asm_src}));
        kernel.step.dependOn(&nasm.step);

        nasm.setCwd(asm_dir);
        nasm.addArgs(&.{
            "nasm",
            "-g",
            "-f",
            "elf32",
            "-w+all",
        });

        // Add output arg.
        nasm.addArg("-o");
        const nasm_out = nasm.addOutputFileArg(std.fmt.comptimePrint("asm-{s}.o", .{asm_src}));

        // Add input arg.
        nasm.addFileArg(asm_dir.path(b, asm_src));

        // Add object file to kernel build.
        kernel.root_module.addObjectFile(nasm_out);
    }

    b.installArtifact(kernel);

    return kernel;
}

fn addTests(b: *std.Build, kernelc: *std.Build.Step.Compile) void {
    const exe_unit_tests = b.addTest(.{
        .root_module = kernelc.root_module,
    });
    exe_unit_tests.linker_script = kernelc.linker_script;

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
