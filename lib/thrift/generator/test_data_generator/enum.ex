defmodule Thrift.Generator.TestDataGenerator.Enum do
  alias Thrift.Generator.TestDataGenerator

  def generate(_schema, name, enum_ast) do
    # file_group = schema.file_group
    test_data_module_name = TestDataGenerator.test_data_module_from_data_module(name)
    # enums = Enum.map(enum_ast.values, fn {vname, _} -> to_name(vname) end)
    enums = Enum.map(enum_ast.values, fn {_, val} -> val end)

    quote do
      defmodule unquote(test_data_module_name) do
        use PropCheck

        def get_generator(context \\ nil, props \\ []) do
          oneof(unquote(enums))
        end
      end
    end
  end

  def to_name(key) do
    key
    |> to_string()
    |> String.downcase()
    |> String.to_atom()
  end
end
