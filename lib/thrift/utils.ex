defmodule Thrift.Utils.Web do

  def normalize_q_result(result) do
    result
    |> Map.from_struct()
    |> Enum.find({:success, nil}, fn {_k, v} -> v != nil end)
    |> case do
      {:success, r} -> {:ok, r}
      {_f, err} -> {:error, err}
    end


  end

end
