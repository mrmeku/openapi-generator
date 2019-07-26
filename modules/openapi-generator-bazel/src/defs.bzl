def openapi_generator_repositories(swagger_openapi_generator_cli_version = "4.0.3", swagger_openapi_generator_cli_sha1 = "4a7e6d7c82df64a1d869e68f28f23e6afd0f9d85", prefix = "io_bazel_rules_openapi_generator"):
    native.maven_jar(
        name = prefix + "_cli",
        artifact = "org.openapitools:openapi-generator-cli:" + swagger_openapi_generator_cli_version,
        sha1 = swagger_openapi_generator_cli_sha1,
    )
    native.bind(
        name = prefix + "/dependency/openapi-generator-cli",
        actual = "@" + prefix + "_cli//jar",
    )

def _comma_separated_pairs(pairs):
    return ",".join([
        "{}={}".format(k, v)
        for k, v in pairs.items()
    ])

def _new_generator_command(ctx, declared_dir, rjars):
    java_path = ctx.attr._jdk[java_common.JavaRuntimeInfo].java_executable_exec_path
    gen_cmd = str(java_path)

    gen_cmd += " -cp {cli_jar}:{jars} org.openapitools.codegen.OpenAPIGenerator generate -i {spec} -g {language} -o {output}".format(
        java = java_path,
        cli_jar = ctx.file.openapi_generator_cli.path,
        jars = ":".join([j.path for j in rjars.to_list()]),
        spec = ctx.file.spec.path,
        language = ctx.attr.language,
        output = declared_dir.path,
    )

    gen_cmd += ' -D "{properties}"'.format(
        properties = _comma_separated_pairs(ctx.attr.system_properties),
    )

    additional_properties = dict(ctx.attr.additional_properties)

    # This is needed to ensure reproducible Java output
    if ctx.attr.language == "java" and \
       "hideGenerationTimestamp" not in ctx.attr.additional_properties:
        additional_properties["hideGenerationTimestamp"] = "true"

    gen_cmd += ' --additional-properties "{properties}"'.format(
        properties = _comma_separated_pairs(additional_properties),
    )

    gen_cmd += ' --type-mappings "{mappings}"'.format(
        mappings = _comma_separated_pairs(ctx.attr.type_mappings),
    )

    if ctx.attr.api_package:
        gen_cmd += " --api-package {package}".format(
            package = ctx.attr.api_package,
        )
    if ctx.attr.invoker_package:
        gen_cmd += " --invoker-package {package}".format(
            package = ctx.attr.invoker_package,
        )
    if ctx.attr.model_package:
        gen_cmd += " --model-package {package}".format(
            package = ctx.attr.model_package,
        )

    # fixme: by default, swagger-codegen is rather verbose. this helps with that but can also mask useful error messages
    # when it fails. look into log configuration options. it's a java app so perhaps just a log4j.properties or something
    gen_cmd += " 1>/dev/null"
    return gen_cmd

def _impl(ctx):
    jars = _collect_jars(ctx.attr.deps)
    (cjars, rjars) = (jars.compiletime, jars.runtime)

    declared_dir = ctx.actions.declare_directory("%s" % (ctx.attr.name))

    inputs = [
        ctx.file.openapi_generator_cli,
        ctx.file.spec,
    ] + cjars.to_list() + rjars.to_list()

    # TODO: Convert to run
    ctx.actions.run_shell(
        inputs = inputs,
        command = "mkdir -p {gen_dir}".format(
            gen_dir = declared_dir.path,
        ) + " && " + _new_generator_command(ctx, declared_dir, rjars),
        outputs = [declared_dir],
        tools = ctx.files._jdk,
    )

    target = ctx.outputs.codegen.path
    srcs = declared_dir.path
    ctx.actions.run(
        executable = ctx.executable._jar,
        arguments = ["cMf", target, "-C", srcs, "."],
        outputs = [ctx.outputs.codegen],
        inputs = inputs + [declared_dir],
    )

    return DefaultInfo(files = depset([
        declared_dir,
        # TODO: Not all users of this will be interested in a .srcjar output. As such,
        # it would be nice to break it into two separate providers so that a .srcjar isn't
        # created unless the caller depends on it.
        ctx.outputs.codegen,
    ]))

def _collect_jars(targets):
    """Compute the runtime and compile-time dependencies from the given targets"""  # noqa
    compile_jars = depset()
    runtime_jars = depset()
    for target in targets:
        found = False
        if hasattr(target, "scala"):
            if hasattr(target.scala.outputs, "ijar"):
                compile_jars = depset(transitive = [compile_jars, [target.scala.outputs.ijar]])
            compile_jars = depset(transitive = [compile_jars, target.scala.transitive_compile_exports])
            runtime_jars = depset(transitive = [runtime_jars, target.scala.transitive_runtime_deps])
            runtime_jars = depset(transitive = [runtime_jars, target.scala.transitive_runtime_exports])
            found = True
        if hasattr(target, "java"):
            compile_jars = depset(transitive = [compile_jars, target.java.transitive_deps])
            runtime_jars = depset(transitive = [runtime_jars, target.java.transitive_runtime_deps])
            found = True
        if not found:
            runtime_jars = depset(transitive = [runtime_jars, target.files])
            compile_jars = depset(transitive = [compile_jars, target.files])

    return struct(compiletime = compile_jars, runtime = runtime_jars)

openapi_generator = rule(
    attrs = {
        # downstream dependencies
        "deps": attr.label_list(),
        # openapi spec file
        "spec": attr.label(
            mandatory = True,
            allow_single_file = [
                ".json",
                ".yaml",
            ],
        ),
        # language to generate
        "language": attr.string(mandatory = True),
        "api_package": attr.string(),
        "invoker_package": attr.string(),
        "model_package": attr.string(),
        "additional_properties": attr.string_dict(),
        "system_properties": attr.string_dict(),
        "type_mappings": attr.string_dict(),
        "_jdk": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
            providers = [java_common.JavaRuntimeInfo],
        ),
        "_jar": attr.label(
            default = Label("@bazel_tools//tools/jdk:jar"),
            executable = True,
            cfg = "host",
        ),
        "openapi_generator_cli": attr.label(
            cfg = "host",
            default = Label("//external:io_bazel_rules_openapi_generator/dependency/openapi-generator-cli"),
            allow_single_file = True,
        ),
    },
    outputs = {
        "codegen": "%{name}.srcjar",
    },
    implementation = _impl,
)
