defmodule Thrift.Generator.Binary.Framed.HTTP.Client do
  alias Thrift.Generator.{
    Service
  }
  alias Thrift.Parser.FileGroup
  alias Thrift.Protocol.Binary

  def generate(service_module, service, file_group) do
    # thrift_root = generate_thrift_root(service_module, service, file_group)

    methods = Enum.map(
      service.functions,
      &(generate_method(service_module, &1, file_group))
    )

    quote do
      defmodule Binary.Framed.HTTP.Client do
        alias Thrift.Protocol.Binary

        unquote_splicing(methods)

      end
    end
  end

  def generate_method(service_module, {func_name, function_ast}, file_group) do

    # function_name = nil
    function_args = Enum.map(function_ast.params, &Macro.var(&1.name, nil))
    args_module = Service.module_name(function_ast, :args)
    args_binary_module = Module.concat(args_module, :BinaryProtocol)
    response_module = Service.module_name(function_ast, :response)
    response_binary_module = Module.concat(response_module, :BinaryProtocol)
    s_func_name = Atom.to_string(func_name)

    assignments =
      function_ast.params
      |> Enum.zip(function_args)
      |> Enum.map(fn {param, var} ->
        quote do
          {unquote(param.name), unquote(var)}
        end
      end)

    quote do
      def unquote(func_name)(thrift_url, unquote_splicing(function_args), opts \\ []) do
        args = %unquote(args_module){unquote_splicing(assignments)}
        serialized_args = unquote(args_binary_module).serialize(args)
        header = Binary.serialize(:message_begin, {:call, 0, unquote(s_func_name)})
        payload = [header | serialized_args] |> IO.iodata_to_binary()

        {http_headers, opts} = Keyword.pop(opts, :headers, [])
        opts = Keyword.merge([hackney: [pool: false]], opts)

        {:ok, response} = HTTPoison.post(thrift_url, payload, http_headers, opts)

        result =
          with(
            {:ok, {:reply, 0, unquote(s_func_name), rest}} <- Binary.deserialize(:message_begin, response.body),
            {%unquote(response_module){success: s}, ""} <- unquote(response_binary_module).deserialize(rest)
          ) do
            {:ok, s}
          end
        {response, result}
      end
    end

  end

end
