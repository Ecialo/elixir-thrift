defmodule Thrift.Generator.TestDataGenerator.Struct do
  alias Thrift.Generator.TestDataGenerator

  def generate(schema, name, struct_ast) do
    file_group = schema.file_group
    test_data_module_name = TestDataGenerator.test_data_module_from_data_module(name)

    struct_fields = Enum.map(struct_ast.fields, &gen_struct_field/1)
    draw_fields = Enum.map(struct_ast.fields, &gen_draw(&1, file_group))

    {fast_access, apply_defaults} =
      struct_ast.fields
      |> Enum.map(&gen_fast_access_replace/1)
      |> Enum.unzip()

    gen =
      case draw_fields do
        [] ->
          quote do
            %unquote(name){unquote_splicing(struct_fields)}
          end

        draw_fields ->
          quote do
            let [unquote_splicing(draw_fields)] do
              %unquote(name){unquote_splicing(struct_fields)}
            end
          end
      end

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

        def get_generator(context \\ nil) do
          unquote(gen)
        end

        def apply_defaults(struct_, context \\ nil) do
          unquote(gen_replace)
        end
      end
    end
  end

  def gen_struct_field(field_ast) do
    quote do
      unquote({field_ast.name, Macro.var(field_ast.name, nil)})
    end
  end

  def gen_draw(field_ast, file_group) do
    generator = TestDataGenerator.get_generator(field_ast.type, file_group)

    generator =
      if field_ast.required do
        generator
      else
        quote do
          oneof([unquote(generator), nil])
        end
      end

    quote do
      unquote(Macro.var(field_ast.name, nil)) <- unquote(generator)
    end
  end

  def gen_fast_access_replace(field_ast) do
    field_var = Macro.var(field_ast.name, nil)
    default = field_ast.default

    access =
      quote do
        unquote({field_ast.name, field_var})
      end

    with_default =
      case default do
        nil ->
          quote do
            Thrift.Generator.TestDataGenerator.apply_defaults(unquote(field_var), context)
          end

        default ->
          quote do
            Thrift.Generator.TestDataGenerator.apply_defaults(unquote(field_var), context) ||
              unquote(default)
          end
      end

    replace =
      quote do
        unquote({field_ast.name, with_default})
      end

    {access, replace}
  end

  def gen_apply_defaults(struct_ast, name) do
    {fast_access, apply_defaults} =
      struct_ast.fields
      |> Enum.map(&gen_fast_access_replace/1)
      |> Enum.unzip()

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
  end
end
