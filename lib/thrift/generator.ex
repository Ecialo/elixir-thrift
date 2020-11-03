defmodule Thrift.Generator do
  @moduledoc """
  This module provides functions for generating Elixir source code from Thrift
  IDL files (`.thrift`).
  """

  alias Thrift.AST.{Constant, Schema}

  alias Thrift.{
    Generator,
    Generator.ConstantGenerator,
    Generator.EnumGenerator,
    Generator.StructGenerator,
    Generator.TestDataGenerator
  }

  alias Thrift.Parser.FileGroup

  @doc """
  Returns the list of target paths that would be generated from a Thrift file.
  """
  @spec targets(FileGroup.t()) :: [Path.t()]
  def targets(%FileGroup{} = file_group) do
    Enum.flat_map(file_group.schemas, fn {_, schema} ->
      schema
      |> Map.put(:file_group, file_group)
      |> generate_schema
      |> hd()
      |> Enum.map(fn {name, _} -> target_path(name) end)

      # |> IO.inspect(label: "target paths")
    end)
  end

  @spec target_path(String.t()) :: Path.t()
  defp target_path(module_name) do
    module_name
    |> inspect
    |> String.split(".")
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
    |> Kernel.<>(".ex")
  end

  def generate!(%FileGroup{} = file_group, [_output_dir, _output_test_data] = output) do
    IO.inspect(file_group.schemas, label: "fg")

    Enum.flat_map(file_group.schemas, fn {_, schema} ->
      schema
      |> Map.put(:file_group, file_group)
      |> generate_schema
      |> write_schema_to_file(output)
    end)
  end

  def generate_to_string!(%FileGroup{} = file_group) do
    Enum.flat_map(file_group.schemas, fn {_, schema} ->
      generate_schema(%Schema{schema | file_group: file_group})
    end)
    |> Enum.reverse()
    |> Enum.map(fn {_, code} ->
      Macro.to_string(code)
    end)
    |> Enum.join("\n")
  end

  def generate_schema(schema) do
    current_module_file_group = FileGroup.set_current_module(schema.file_group, schema.module)
    schema = %Schema{schema | file_group: current_module_file_group}
    IO.inspect(schema, label: "schema")

    modules =
      List.flatten([
        generate_enum_modules(schema),
        generate_const_modules(schema),
        generate_struct_modules(schema),
        generate_union_modules(schema),
        generate_exception_modules(schema),
        generate_services(schema),
        generate_behaviours(schema)
      ])

    test_modules = generate_test_data_modules(schema)
    [modules, test_modules]
  end

  defp write_schema_to_file(module_groups, outputs) do
    module_groups
    |> Enum.zip(outputs)
    |> Enum.map(&perform_write/1)
  end

  defp perform_write({modules, output}) do
    modules
    |> resolve_name_collisions
    |> Enum.map(fn {name, quoted} ->
      filename = target_path(name)
      source = Macro.to_string(quoted)

      path = Path.join(output, filename)

      path
      |> Path.dirname()
      |> File.mkdir_p!()

      File.write!(path, source)

      filename
    end)
  end

  defp resolve_name_collisions(generated_modules) do
    Enum.reduce(generated_modules, [], fn {name, quoted}, acc ->
      Keyword.update(
        acc,
        name,
        quoted,
        &resolve_name_collision(name, &1, quoted)
      )
    end)
  end

  # We resolve name collisions (two generated modules with the same name)
  # pairwise by inspecting the types of modules generated.
  # Most collisions cannot be resolved.  Constants can be merged into
  # modules that define other types (structs, etc).
  defp resolve_name_collision(name, q1, q2) do
    # breaks apart the module's ast and gets the parts we need
    {meta1, ast1} = get_meta_and_ast(q1)
    {meta2, ast2} = get_meta_and_ast(q2)

    # the context will tell us what type (e.g., Enum, Constant, etc.)
    #   was defined by each module
    context1 = Keyword.get(meta1, :context)
    context2 = Keyword.get(meta2, :context)

    # only allow constants to be merged into other modules
    #   but make sure the meta is for the not-constant module, so that
    #   subsequent collisions are properly dealt with
    cond do
      context1 == Thrift.Generator.ConstantGenerator ->
        combine_module_defs(name, meta2, ast1, ast2)

      context2 == Thrift.Generator.ConstantGenerator ->
        combine_module_defs(name, meta1, ast1, ast2)

      true ->
        raise "Name collision: #{name}"
    end
  end

  defp get_meta_and_ast(quoted) do
    {:defmodule, meta, [_name, [do: {:__block__, [], ast}]]} = quoted
    {meta, ast}
  end

  defp combine_module_defs(name, meta, ast1, ast2) do
    {:defmodule, meta, [name, [do: {:__block__, [], ast1 ++ ast2}]]}
  end

  defp generate_test_data_modules(schema) do
    endless_label = fn label -> Stream.repeatedly(fn -> label end) end
    zip_with_label = fn label, stream -> Stream.zip(endless_label.(label), stream) end

    typedefs_stream = zip_with_label.(:typedef, schema.typedefs)
    structs_stream = zip_with_label.(:struct, schema.structs)
    exceptions_stream = zip_with_label.(:exception, schema.exceptions)
    unions_stream = zip_with_label.(:union, schema.unions)
    enums_stream = zip_with_label.(:enum, schema.enums)

    all_streams =
      Stream.concat([
        typedefs_stream,
        structs_stream,
        exceptions_stream,
        unions_stream,
        enums_stream
      ])

    for {label, {key, struct}} <- all_streams do
      full_name =
        case label do
          :typedef ->
            thrift_module = Atom.to_string(schema.module)
            typedef = key |> Atom.to_string() |> String.capitalize()
            name = "#{thrift_module}.#{typedef}" |> String.to_atom()

            # typedef_name =
            #   Atom.to_string(schema.module) <>
            #     "." <> (key |> Atom.to_string() |> String.capitalize())

            # IO.inspect(schema, limit: 10, label: "schema")

            # IO.inspect(ss)
            FileGroup.dest_module(schema.file_group, name)

          # |> IO.inspect(label: "full_name")

          _otherwise ->
            FileGroup.dest_module(schema.file_group, struct)
        end

      # if label == :typedef do
      #   IO.inspect(ss)
      # end
      # full_name = FileGroup.dest_module(schema.file_group, struct)
      # |> IO.inspect()
      full_test_data_name = TestDataGenerator.test_data_module_from_data_module(full_name)

      {full_test_data_name, TestDataGenerator.generate(label, schema, full_name, struct)}
    end
  end

  defp generate_enum_modules(schema) do
    for {_, enum} <- schema.enums do
      full_name = FileGroup.dest_module(schema.file_group, enum)
      {full_name, EnumGenerator.generate(full_name, enum)}
    end
  end

  defp generate_const_modules(%Schema{constants: constants})
       when constants == %{} do
    # no constants => nothing to generate
    []
  end

  defp generate_const_modules(schema) do
    # schema.constants is a map %{name: constant} but constant includes the
    # name and all we really need is the values
    #
    # we also only want constants that are defined in the main file from this
    # file group
    constants =
      schema.constants
      |> Map.values()
      |> Enum.filter(&FileGroup.own_constant?(schema.file_group, &1))

    if Enum.empty?(constants) do
      # if we filtered out all of the constants, we don't need to write
      # anything
      []
    else
      # name of the generated module
      full_name = FileGroup.dest_module(schema.file_group, Constant)
      [{full_name, ConstantGenerator.generate(full_name, constants, schema)}]
    end
  end

  defp generate_struct_modules(schema) do
    for {_, struct} <- schema.structs do
      full_name = FileGroup.dest_module(schema.file_group, struct)
      {full_name, StructGenerator.generate(:struct, schema, full_name, struct)}
    end
  end

  defp generate_union_modules(schema) do
    for {_, union} <- schema.unions do
      full_name = FileGroup.dest_module(schema.file_group, union)
      {full_name, StructGenerator.generate(:union, schema, full_name, union)}
    end
  end

  defp generate_exception_modules(schema) do
    for {_, exception} <- schema.exceptions do
      full_name = FileGroup.dest_module(schema.file_group, exception)
      {full_name, StructGenerator.generate(:exception, schema, full_name, exception)}
    end
  end

  defp generate_services(schema) do
    for {_, service} <- schema.services do
      Generator.Service.generate(schema, service)
    end
  end

  defp generate_behaviours(schema) do
    for {_, service} <- schema.services do
      Generator.Behaviour.generate(schema, service)
    end
  end
end
