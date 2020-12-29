defmodule Thrift.Generator.Utils.Types do
  require Logger

  alias Thrift.AST.{
    Exception,
    Struct,
    TEnum,
    TypeRef,
    Union
  }

  alias Thrift.Parser.FileGroup

  def typespec(:void, _), do: quote(do: nil)
  def typespec(:bool, _), do: quote(do: boolean())
  def typespec(:string, _), do: quote(do: String.t())
  def typespec(:binary, _), do: quote(do: binary)
  def typespec(:i8, _), do: quote(do: Thrift.i8())
  def typespec(:i16, _), do: quote(do: Thrift.i16())
  def typespec(:i32, _), do: quote(do: Thrift.i32())
  def typespec(:i64, _), do: quote(do: Thrift.i64())
  def typespec(:double, _), do: quote(do: Thrift.double())

  def typespec(%TypeRef{} = ref, file_group) do
    file_group
    |> FileGroup.resolve(ref)
    |> typespec(file_group)
  end

  def typespec(%TEnum{}, _) do
    quote do
      non_neg_integer
    end
  end

  def typespec(%Union{name: name}, file_group) do
    dest_module = FileGroup.dest_module(file_group, name)

    quote do
      %unquote(dest_module){}
    end
  end

  def typespec(%Exception{name: name}, file_group) do
    dest_module = FileGroup.dest_module(file_group, name)

    quote do
      # %unquote(dest_module){}
      unquote(dest_module).t()
    end
  end

  def typespec(%Struct{name: name}, file_group) do
    dest_module = FileGroup.dest_module(file_group, name)

    quote do
      # %unquote(dest_module){}
      unquote(dest_module).t()
    end
  end

  def typespec({:set, _t}, _) do
    quote do
      %MapSet{}
    end
  end

  def typespec({:list, t}, file_group) do
    quote do
      [unquote(typespec(t, file_group))]
    end
  end

  def typespec({:map, {k, v}}, file_group) do
    key_type = typespec(k, file_group)
    val_type = typespec(v, file_group)

    quote do
      %{unquote(key_type) => unquote(val_type)}
    end
  end

  def typespec(unknown_typespec, _) do
    Logger.error("Unknown type: #{inspect(unknown_typespec)}. Falling back to any()")

    quote do
      any()
    end
  end
end
