defmodule Thrift.Generator.TestDataGenerator.Typedef do
  alias Thrift.Generator.TestDataGenerator

  def generate(schema, name, typedef_ast) do
    file_group = schema.file_group
    test_data_module_name = TestDataGenerator.test_data_module_from_data_module(name)

    quote do
      defmodule unquote(test_data_module_name) do
        use PropCheck
        alias Thrift.Generator.TestDataGenerator

        def get_generator(context, props \\ [])

        def get_generator(context, props) when is_list(context) do
          ctx = Enum.map(context, &handler_module_from_context/1)

          f =
            TestDataGenerator.find_first_realization(
              ctx,
              {:get_generator, 2},
              &get_default_generator/2
            )

          f.(context, props)
        end

        def get_generator(nil, props) do
          get_generator([], props)
        end

        def get_generator(context, props) do
          get_generator([context], props)
        end

        def apply_defaults(example, nil) do
          apply_defaults(example, [])
        end

        def apply_defaults(example, context) when is_list(context) do
          ctx = Enum.map(context, &handler_module_from_context/1)

          f =
            TestDataGenerator.find_first_realization(
              ctx,
              {:apply_defaults, 2},
              &default_apply_defaults/2
            )

          f.(example, context)
        end

        def get_default_generator(context, props) do
          unquote(TestDataGenerator.get_generator(typedef_ast.type, file_group, typedef_ast.annotations))
        end

        def default_apply_defaults(example, context) do
          TestDataGenerator.apply_defaults(example, context)
        end

        def handler_module_from_context(context) do
          Module.concat(context, unquote(name))
        end
      end
    end
  end
end
