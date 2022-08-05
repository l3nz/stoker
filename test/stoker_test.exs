defmodule StokerTest do
  use ExUnit.Case
  doctest Stoker

  test "greets the world" do
    assert Stoker.hello() == :world
  end
end
