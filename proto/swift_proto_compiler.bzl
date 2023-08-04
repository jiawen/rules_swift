# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Defines a rule for compiling Swift source files from ProtoInfo providers.
"""

load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load(
    "//proto:swift_proto_common.bzl",
    "swift_proto_common",
)
load(
    "//proto:swift_proto_utils.bzl",
    "register_module_mapping_write_action",
)
load("//swift:providers.bzl", "SwiftInfo", "SwiftProtoCompilerInfo")

def _swift_proto_compile(label, actions, swift_proto_compiler_info, additional_compiler_info, proto_infos, module_mappings):
    """Compiles Swift source files from `ProtoInfo` providers.

    Args:
        label: The label of the target for which the Swift files are being generated.
        actions: The actions object used to declare the files to be generated and the actions that generate them.
        swift_proto_compiler_info: This `SwiftProtoCompilerInfo` provider.
        additional_compiler_info: Additional information passed from the target target to the compiler.
        proto_infos: The list of `ProtoInfo` providers to compile.
        module_mappings: The module_mappings field of the `SwiftProtoInfo` for the target.

    Returns:
        A `list` of `.swift` `File`s generated by the compiler.
    """

    # Create a dictionary of the allowed plugin options for faster lookup:
    plugin_option_allowlist = swift_proto_compiler_info.internal.plugin_option_allowlist
    allowed_plugin_options = {plugin_option: True for plugin_option in plugin_option_allowlist}

    # Overlay the additional plugin options on top of the default plugin options,
    # filtering out any that are unsupported by the plugin.
    plugin_options = {}
    for plugin_option, value in swift_proto_compiler_info.internal.plugin_options.items():
        if not plugin_option in allowed_plugin_options:
            continue
        plugin_options[plugin_option] = value
    for plugin_option, value in additional_compiler_info.items():
        if not plugin_option in allowed_plugin_options:
            continue
        plugin_options[plugin_option] = value

    # Some protoc plugins like protoc-gen-grpc-swift only generate swift files for a subset of the protos.
    # We can't inspect the proto contents to determine which ones will actually be generated.
    # This is a problem for Bazel which requires every declared file to actually be created.
    # To avoid this, we first generate the protos into a temporary declared directory,
    # and then follow this up with a shell action to copy the generated files to the declared paths,
    # before finally touching all of the paths to ensure we at least have a blank Swift file for those.

    # Declare the temporary output directory and define the temporary and permanent output paths:
    target_relative_permanent_output_directory_path = paths.join(label.name, "gen")
    target_relative_temporary_output_directory_path = paths.join(label.name, swift_proto_compiler_info.internal.plugin_name, "tmp")
    temporary_output_directory = actions.declare_directory(target_relative_temporary_output_directory_path)

    # Create a map of bundled proto paths for faster lookup:
    bundled_proto_paths = {}
    for bundled_proto_path in swift_proto_compiler_info.bundled_proto_paths:
        bundled_proto_paths[bundled_proto_path] = True

    # Declare the Swift files that will be generated:
    swift_srcs = []
    proto_paths = {}
    transitive_descriptor_sets_list = []
    permanent_output_directory_path = None
    for proto_info in proto_infos:
        # Collect the transitive descriptor sets from the proto infos:
        transitive_descriptor_sets_list.append(proto_info.transitive_descriptor_sets)

        # Iterate over the proto sources in the proto info to gather information
        # about their proto sources and declare the swift files that will be generated:
        for proto_src in proto_info.check_deps_sources.to_list():
            # Derive the proto path:
            path = swift_proto_common.proto_path(proto_src, proto_info)
            if path in bundled_proto_paths:
                continue
            if path in proto_paths:
                if proto_paths[path] != proto_src:
                    fail("proto files {} and {} have the same import path, {}".format(
                        proto_src.path,
                        proto_paths[path].path,
                        path,
                    ))
                continue
            proto_paths[path] = proto_src

            # Declare the Swift source files that will be generated:
            suffixes = swift_proto_compiler_info.internal.suffixes
            for suffix in suffixes:
                output_directory_relative_swift_src_path = paths.replace_extension(path, suffix)

                # Apply the file naming option to the path:
                file_naming_plugin_option = plugin_options["FileNaming"] if "FileNaming" in plugin_options else "FullPath"
                if file_naming_plugin_option == "PathToUnderscores":
                    output_directory_relative_swift_src_path = output_directory_relative_swift_src_path.replace("/", "_")
                elif file_naming_plugin_option == "DropPath":
                    output_directory_relative_swift_src_path = paths.basename(output_directory_relative_swift_src_path)
                elif file_naming_plugin_option == "FullPath":
                    # This is the default behavior and it leaves the path as-is.
                    pass
                else:
                    fail("unknown file naming plugin option: ", file_naming_plugin_option)

                swift_src_path = paths.join(target_relative_permanent_output_directory_path, output_directory_relative_swift_src_path)
                swift_src = actions.declare_file(swift_src_path)
                swift_srcs.append(swift_src)

                # Grab the permanent output directory path:
                if permanent_output_directory_path == None:
                    full_swift_src_path = swift_srcs[0].path
                    permanent_output_directory_path = full_swift_src_path.removesuffix("/" + output_directory_relative_swift_src_path)
    transitive_descriptor_sets = depset(direct = [], transitive = transitive_descriptor_sets_list)

    # If the generated swift sources are empty, create an empty directory and file to satisfy bazel and the compiler:
    if len(swift_srcs) == 0:
        arguments = actions.args()
        arguments.add(temporary_output_directory.path)
        actions.run_shell(
            command = "mkdirall",
            arguments = [arguments],
            outputs = [temporary_output_directory],
        )

        empty_file = actions.declare_file(paths.join(target_relative_permanent_output_directory_path, "Empty.swift"))
        actions.write(empty_file, "")
        return [empty_file]

    # Write the module mappings to a file:
    module_mappings_file = register_module_mapping_write_action(
        actions = actions,
        label = label,
        module_mappings = module_mappings,
    )

    # Build the arguments for protoc:
    arguments = actions.args()
    arguments.set_param_file_format("multiline")
    arguments.use_param_file("@%s")

    # Add the plugin argument with the provided name to namespace all of the options:
    plugin_name_argument = "--plugin=protoc-gen-{}={}".format(
        swift_proto_compiler_info.internal.plugin_name,
        swift_proto_compiler_info.internal.plugin.path,
    )
    arguments.add(plugin_name_argument)

    # Add the plugin option arguments:
    for plugin_option in plugin_options:
        plugin_option_value = plugin_options[plugin_option]
        plugin_option_argument = "--{}_opt={}={}".format(
            swift_proto_compiler_info.internal.plugin_name,
            plugin_option,
            plugin_option_value,
        )
        arguments.add(plugin_option_argument)

    # Add the module mappings file argument:
    module_mappings_file_argument = "--{}_opt=ProtoPathModuleMappings={}".format(
        swift_proto_compiler_info.internal.plugin_name,
        module_mappings_file.path,
    )
    arguments.add(module_mappings_file_argument)

    # Add the output directory argument:
    output_directory_argument = "--{}_out={}".format(
        swift_proto_compiler_info.internal.plugin_name,
        temporary_output_directory.path,
    )
    arguments.add(output_directory_argument)

    # Join the transitive descriptor sets into a single argument separated by colons:
    formatted_descriptor_set_paths = ":".join([f.path for f in transitive_descriptor_sets.to_list()])
    descriptor_set_in_argument = "--descriptor_set_in={}".format(formatted_descriptor_set_paths)
    arguments.add(descriptor_set_in_argument)

    # Finally, add the proto paths:
    arguments.add_all(proto_paths.keys())

    # Run the protoc action:
    actions.run(
        inputs = depset(
            direct = [
                swift_proto_compiler_info.internal.protoc,
                swift_proto_compiler_info.internal.plugin,
                module_mappings_file,
            ],
            transitive = [transitive_descriptor_sets],
        ),
        outputs = [temporary_output_directory],
        progress_message = "Generating protos into %s" % temporary_output_directory.path,
        mnemonic = "SwiftProtocGen",
        executable = swift_proto_compiler_info.internal.protoc,
        arguments = [arguments],
    )

    # Expand the copy Swift sources template:
    copy_swift_sources_file_path = paths.join(label.name, swift_proto_compiler_info.internal.plugin_name, "copy_swift_sources.sh")
    copy_swift_sources_file = actions.declare_file(copy_swift_sources_file_path)
    actions.expand_template(
        template = swift_proto_compiler_info.internal.copy_swift_sources_template,
        output = copy_swift_sources_file,
        substitutions = {
            "{temporary_output_directory_path}": temporary_output_directory.path,
            "{permanent_output_directory_path}": permanent_output_directory_path,
            "{swift_source_file_paths}": " ".join([src.path for src in swift_srcs]),
        },
        is_executable = True,
    )

    # Run the copy swift sources action:
    actions.run(
        inputs = depset([temporary_output_directory]),
        outputs = swift_srcs,
        progress_message = "Copying protos into %s" % permanent_output_directory_path,
        mnemonic = "CopySwiftSources",
        executable = copy_swift_sources_file,
    )

    return swift_srcs

def _swift_proto_compiler_impl(ctx):
    return [
        SwiftProtoCompilerInfo(
            bundled_proto_paths = ctx.attr.bundled_proto_paths,
            compile = _swift_proto_compile,
            compiler_deps = ctx.attr.deps,
            internal = struct(
                protoc = ctx.executable.protoc,
                plugin = ctx.executable.plugin,
                plugin_name = ctx.attr.plugin_name,
                plugin_option_allowlist = ctx.attr.plugin_option_allowlist,
                plugin_options = ctx.attr.plugin_options,
                suffixes = ctx.attr.suffixes,
                copy_swift_sources_template = ctx.file._copy_swift_sources_template,
            ),
        ),
    ]

swift_proto_compiler = rule(
    attrs = {
        "bundled_proto_paths": attr.string_list(
            doc = """\
List of proto paths for which to skip generation because they're built into the modules
imported by the generated Swift proto code, e.g., SwiftProtobuf.
""",
            default = [
                "google/protobuf/any.proto",
                "google/protobuf/api.proto",
                "google/protobuf/descriptor.proto",
                "google/protobuf/duration.proto",
                "google/protobuf/empty.proto",
                "google/protobuf/field_mask.proto",
                "google/protobuf/source_context.proto",
                "google/protobuf/struct.proto",
                "google/protobuf/timestamp.proto",
                "google/protobuf/type.proto",
                "google/protobuf/wrappers.proto",
            ],
        ),
        "deps": attr.label_list(
            default = [],
            doc = """\
List of targets providing SwiftInfo and CcInfo.
Added as implicit dependencies for any swift_proto_library using this compiler.
Typically, these are Well Known Types and proto runtime libraries.
""",
            providers = [SwiftInfo],
        ),
        "protoc": attr.label(
            doc = """\
A proto compiler executable binary.

E.g.
"//tools/protoc_wrapper:protoc"
""",
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
        "plugin": attr.label(
            doc = """\
A proto compiler plugin executable binary.

For example:
"//tools/protoc_wrapper:protoc-gen-grpc-swift"
"//tools/protoc_wrapper:ProtoCompilerPlugin"
""",
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
        "plugin_name": attr.string(
            doc = """\
Name of the proto compiler plugin passed to protoc.

For example:

```
protoc \
    --plugin=protoc-gen-NAME=path/to/plugin/binary
```

This name will be used to prefix the option and output directory arguments. E.g.:

```
protoc \
    --plugin=protoc-gen-NAME=path/to/mybinary \
    --NAME_out=OUT_DIR \
    --NAME_opt=Visibility=Public
```

See the [protobuf API reference](https://protobuf.dev/reference/cpp/api-docs/google.protobuf.compiler.plugin) for more information.
""",
            mandatory = True,
        ),
        "plugin_option_allowlist": attr.string_list(
            doc = """\
Allowlist of options allowed by the plugin.
This is used to filter out any irrelevant plugin options passed down to the compiler from the library,
which is especially useful when using multiple plugins in combination like GRPC and SwiftProtobuf.
""",
            mandatory = True,
        ),
        "plugin_options": attr.string_dict(
            doc = """\
Dictionary of plugin options passed to the plugin.

These are prefixed with the plugin_name + "_opt". E.g.:

```
plugin_name = "swift"
plugin_options = {
    "Visibility": "Public",
    "FileNaming": "FullPath",
}
```

Would be passed to protoc as:

```
protoc \
    --plugin=protoc-gen-NAME=path/to/plugin/binary \
    --NAME_opt=Visibility=Public \
    --NAME_opt=FileNaming=FullPath
```
""",
            mandatory = True,
        ),
        "suffixes": attr.string_list(
            doc = """\
Suffix used for Swift files generated by the plugin from protos.

E.g.

```
foo.proto => foo.pb.swift
foo_service.proto => foo.grpc.swift
```

Each compiler target should configure this based on the suffix applied to the generated files.
""",
            mandatory = True,
        ),
        "_copy_swift_sources_template": attr.label(
            default = "//proto:copy_swift_sources.sh.tpl",
            allow_single_file = True,
        ),
    },
    implementation = _swift_proto_compiler_impl,
)