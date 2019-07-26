load("//:defs.bzl", "openapi_generator")

openapi_generator(
    name = "petstore",
    language = "go",
    spec = "petstore.yaml",
)

openapi_generator(
    name = "petstore_java",
    language = "java",
    spec = "petstore.yaml",
)

openapi_generator(
    name = "petstore_java_feign",
    additional_properties = {
        "library": "feign",
    },
    language = "java",
    spec = "petstore.yaml",
)

openapi_generator(
    name = "petstore_java_no_tests",
    language = "java",
    spec = "petstore.yaml",
    system_properties = {
        "apiTests": "false",
        "modelTests": "false",
    },
)

openapi_generator(
    name = "petstore_java_bigdecimal",
    language = "java",
    spec = "petstore.yaml",
    type_mappings = {
        "Integer": "java.math.BigDecimal",
    },
)
