# Takes a thrift service definition and creates a behavoiur module for users
# to implement. Thrift types are converted into Elixir typespecs that are
# equivalent to their thrift counterparts.
defmodule Thrift.Generator.Behaviour do
  @moduledoc false
  import Thrift.Generator.Utils.Types, only: [typespec: 2]

  alias Thrift.AST.{
    Exception,
    Field,
    Struct,
    TEnum,
    TypeRef,
    Union
  }

  alias Thrift.Generator.Utils
  alias Thrift.Parser.FileGroup

  require Logger

  def generate(schema, service) do
    file_group = schema.file_group
    dest_module = Module.concat(FileGroup.dest_module(file_group, service), Handler)

    callbacks =
      service.functions
      |> Map.values()
      |> Enum.map(&create_callback(file_group, &1))

    behaviour_module =
      quote do
        defmodule unquote(dest_module) do
          @moduledoc false
          (unquote_splicing(callbacks))
        end
      end

    {dest_module, behaviour_module}
  end

  defp create_callback(file_group, function) do
    callback_name = Utils.underscore(function.name)

    return_type = typespec(function.return_type, file_group)
    return_type = ok_type(return_type)

    exceptions = Enum.map(
      function.exceptions,
      &(&1.type |> typespec(file_group) |> exception_type())
    )

    return_type = Enum.reduce([return_type | exceptions], &unite/2)

    params =
      function.params
      |> Enum.map(&FileGroup.resolve(file_group, &1))
      |> Enum.map(&to_arg_spec(&1, file_group))

    quote do
      @callback unquote(callback_name)(unquote_splicing(params)) :: unquote(return_type)
    end
  end

  def to_arg_spec(%Field{name: name, type: type}, file_group) do
    quote do
      unquote(Macro.var(name, nil)) :: unquote(typespec(type, file_group))
    end
  end

  defp ok_type(typespec_) do
    quote do
      {:ok, unquote(typespec_)}
    end
  end

  defp exception_type(typespec_) do
    quote do
      {:exception, unquote(typespec_)}
    end
  end

  defp unite(type, acc) do
    quote do
      unquote(acc) | unquote(type)
    end
  end
end
