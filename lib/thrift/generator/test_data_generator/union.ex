defmodule Thrift.Generator.TestDataGenerator.Union do
  alias Thrift.Generator.TestDataGenerator
  alias Thrift.Generator.TestDataGenerator.Struct, as: StructGenerator

  def generate(schema, name, struct_ast) do
    file_group = schema.file_group
    test_data_module_name = TestDataGenerator.test_data_module_from_data_module(name)

    subgens = Enum.map(struct_ast.fields, &gen_sub_gens(&1, file_group, name))
    fields = Enum.map(struct_ast.fields, &Macro.var(&1.name, nil))

    {fast_access, apply_defaults} =
      struct_ast.fields
      |> Enum.map(&StructGenerator.gen_fast_access_replace/1)
      |> Enum.unzip()

    gen_replace =
      case fast_access do
        [] ->
          quote do
            unquote(Macro.var(:struct_, nil))
          end

        _otherwise ->
          quote do
            %unquote(name){unquote_splicing(fast_access)} = struct_
            %{struct_ | unquote_splicing(apply_defaults)}
          end
      end

    quote do
      defmodule unquote(test_data_module_name) do
        use PropCheck

        def get_generator(context \\ nil, props \\ []) do
          unquote_splicing(subgens)

          oneof([unquote_splicing(fields)])
        end

        def apply_defaults(struct_, context \\ nil) do
          unquote(gen_replace)
        end
      end
    end
  end

  def gen_sub_gens(field_ast, file_group, module_name) do
    field_var = Macro.var(field_ast.name, nil)
    gen = TestDataGenerator.get_generator(field_ast.type, file_group, field_ast.annotations)
    fill_field = [{field_ast.name, field_var}]

    quote do
      unquote(field_var) =
        let unquote(field_var) <- unquote(gen) do
          %unquote(module_name){unquote_splicing(fill_field)}
        end
    end
  end
end
