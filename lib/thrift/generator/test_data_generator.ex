defmodule Thrift.Generator.TestDataGenerator do
  alias __MODULE__, as: TestDataGenerator

  alias Thrift.AST.{
    Exception,
    Struct,
    TEnum,
    TypeRef,
    Typedef,
    Union
  }

  alias Thrift.Parser.FileGroup

  def generate(label, schema, full_name, struct) do
    case label do
      :typedef -> TestDataGenerator.Typedef.generate(schema, full_name, struct)
      :union -> TestDataGenerator.Union.generate(schema, full_name, struct)
      :enum -> TestDataGenerator.Enum.generate(schema, full_name, struct)
      _ -> TestDataGenerator.Struct.generate(schema, full_name, struct)
    end
  end

  def get_generator(type, file_group, annotations \\ %{})

  def get_generator(:bool, _, _) do
    quote do
      bool()
    end
  end

  def get_generator(:string, _, _) do
    ascii = ?a..?z |> Enum.to_list()

    quote do
      let chars <- list(oneof(unquote(ascii))) do
        List.to_string(chars)
      end
    end
  end

  def get_generator(:binary, _, _) do
    quote do
      binary(100)
    end
  end

  def get_generator(:i8, _, annotations) do
    min = refinement_from_annotations(annotations, :min, &parse_integer/1, -128)
    max = refinement_from_annotations(annotations, :max, &parse_integer/1, 127)

    quote do
      integer(unquote(min), unquote(max))
    end
  end

  def get_generator(:i16, _, annotations) do
    min = refinement_from_annotations(annotations, :min, &parse_integer/1, -32_768)
    max = refinement_from_annotations(annotations, :max, &parse_integer/1, 32_767)

    quote do
      integer(unquote(min), unquote(max))
    end
  end

  def get_generator(:i32, _, annotations) do
    min = refinement_from_annotations(annotations, :min, &parse_integer/1, -2_147_483_648)
    max = refinement_from_annotations(annotations, :max, &parse_integer/1, 2_147_483_647)

    quote do
      integer(unquote(min), unquote(max))
    end
  end

  def get_generator(:i64, _, annotations) do
    min =
      refinement_from_annotations(annotations, :min, &parse_integer/1, -9_223_372_036_854_775_808)

    max =
      refinement_from_annotations(annotations, :max, &parse_integer/1, 9_223_372_036_854_775_807)

    quote do
      integer(unquote(min), unquote(max))
    end
  end

  def get_generator(:double, _, annotations) do
    min = refinement_from_annotations(annotations, :min, &parse_float/1, :inf)
    max = refinement_from_annotations(annotations, :max, &parse_float/1, :inf)

    quote do
      float(unquote(min), unquote(max))
    end
  end

  def get_generator({:list, t}, file_group, annotations) do
    subgen = get_generator(t, file_group, annotations)

    quote do
      list(unquote(subgen))
    end
  end

  def get_generator({:set, t}, file_group, annotations) do
    subgen = get_generator({:list, t}, file_group, annotations)

    quote do
      let set <- unquote(subgen) do
        MapSet.new(set)
      end
    end
  end

  def get_generator({:map, {k, v}}, file_group, annotations) do
    separate = fn {k, v} ->
      [type, key] =
        k
        |> Atom.to_string()
        |> String.split("_", parts: 2)

      {type, {String.to_atom(key), v}}
    end

    separated_annotations =
      annotations
      |> Enum.map(separate)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 2))

    key_annotations = Map.new(separated_annotations[:k] || %{})
    val_annotations = Map.new(separated_annotations[:v] || %{})

    key_subgen = get_generator(k, file_group, key_annotations)
    val_subgen = get_generator(v, file_group, val_annotations)

    quote do
      map(unquote(key_subgen), unquote(val_subgen))
    end
  end

  def get_generator(%TEnum{name: name}, file_group, _annotations) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator(context)
    end
  end

  def get_generator(
        %TypeRef{referenced_type: type_name},
        %FileGroup{resolutions: resolutions} = file_group,
        annotations
      ) do
    case resolutions[type_name] do
      %Typedef{} = td ->
        get_generator(td, file_group, annotations)

      other_type ->
        file_group
        |> FileGroup.resolve(other_type)
        |> get_generator(file_group, annotations)
    end
  end

  def get_generator(%Union{name: name}, file_group, annotations) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    props = gen_props(annotations)

    quote do
      unquote(dest_module).get_generator(context, unquote(props))
    end
  end

  def get_generator(%Exception{name: name}, file_group, annotations) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator(context)
    end
  end

  def get_generator(%Struct{name: name}, file_group, annotations) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    props = gen_props(annotations)

    quote do
      unquote(dest_module).get_generator(context, unquote(props))
    end
  end

  def get_generator(%Typedef{} = typedef, file_group, annotations) do
    dest_module =
      FileGroup.dest_module(file_group, typedef)
      |> test_data_module_from_data_module

    props = gen_props(annotations)

    quote do
      unquote(dest_module).get_generator(context, unquote(props))
    end
  end

  def test_data_module_from_data_module(data_module) do
    Module.concat(TestData, data_module)
  end

  def apply_defaults(struct_) do
    apply_defaults(struct_, nil)
  end

  def apply_defaults(struct_, context) when is_struct(struct_) do
    module_name =
      struct_.__struct__
      |> test_data_module_from_data_module()

    apply(module_name, :apply_defaults, [struct_, context])
  end

  def apply_defaults(some_list, context) when is_list(some_list) do
    Enum.map(some_list, &apply_defaults(&1, context))
  end

  def apply_defaults(some_map, context) when is_map(some_map) do
    Map.new(some_map, fn {k, v} -> {k, apply_defaults(v, context)} end)
  end

  def apply_defaults(%MapSet{} = some_set, context) do
    MapSet.new(some_set, &apply_defaults(&1, context))
  end

  def apply_defaults(anything_else, _context) do
    anything_else
  end

  def find_first_realization([], _fns, default) do
    default
  end

  def find_first_realization([module | rest], {fname, arity} = func, default) do
    Code.ensure_loaded(module)

    if function_exported?(module, fname, arity) do
      Function.capture(module, fname, arity)
    else
      find_first_realization(rest, func, default)
    end
  end

  defp refinement_from_annotations(annotations, field, parse_fun, default) do
    annotations
    |> Map.get(field)
    |> case do
      nil -> default
      "^" <> v -> annotation_to_pin(v)
      v -> parse_fun.(v)
    end
  end

  defp parse_integer(str) do
    str |> Integer.parse() |> elem(0)
  end

  defp parse_float(str) do
    str |> Float.parse() |> elem(0)
  end

  defp annotation_to_pin(anno) do
    var_name =
      anno
      |> String.to_atom()
      |> Macro.var(nil)

    quote do
      ^unquote(var_name)
    end
  end

  defp gen_props(annotations) do
    to_prop = fn {k, v} ->
      v =
        case v do
          "^" <> v -> annotation_to_pin(v)
          v -> v
        end

      {k, v}
    end

    props_from_annotations =
      annotations
      |> Enum.map(to_prop)

    quote do
      [unquote_splicing(props_from_annotations)]
    end
  end
end
