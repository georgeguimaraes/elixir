Code.require_file("../test_helper.exs", __DIR__)

defmodule Kernel.Overridable do
  def sample do
    1
  end

  def with_super do
    1
  end

  def without_super do
    1
  end

  def super_with_multiple_args(x, y) do
    x + y
  end

  def many_clauses(0) do
    11
  end

  def many_clauses(1) do
    13
  end

  defoverridable sample: 0,
                 with_super: 0,
                 without_super: 0,
                 super_with_multiple_args: 2,
                 many_clauses: 1

  true = Module.overridable?(__MODULE__, {:without_super, 0})
  true = Module.overridable?(__MODULE__, {:with_super, 0})

  def without_super do
    :without_super
  end

  def with_super do
    super() + 2
  end

  def super_with_multiple_args(x, y) do
    super(x, y * 2)
  end

  def many_clauses(2) do
    17
  end

  def many_clauses(3) do
    super(0) + super(1)
  end

  def many_clauses(x) do
    super(x)
  end

  ## Macros

  defmacro overridable_macro(x) do
    quote do
      unquote(x) + 100
    end
  end

  defoverridable overridable_macro: 1

  defmacro overridable_macro(x) do
    quote do
      unquote(super(x)) + 1000
    end
  end

  defmacrop private_macro(x \\ raise("never called"))

  defmacrop private_macro(x) do
    quote do
      unquote(x) + 100
    end
  end

  defoverridable private_macro: 1

  defmacrop private_macro(x) do
    quote do
      unquote(super(x)) + 1000
    end
  end

  def private_macro_call(val \\ 11) do
    private_macro(val)
  end
end

defmodule Kernel.OverridableExampleBehaviour do
  @callback required_callback :: any
  @callback optional_callback :: any
  @macrocallback required_macro_callback(arg :: any) :: Macro.t()
  @macrocallback optional_macro_callback(arg :: any, arg2 :: any) :: Macro.t()
  @optional_callbacks optional_callback: 0, optional_macro_callback: 1
end

defmodule Kernel.OverridableTest do
  require Kernel.Overridable, as: Overridable
  use ExUnit.Case

  defp purge(module) do
    :code.purge(module)
    :code.delete(module)
  end

  test "overridable keeps function ordering" do
    defmodule OverridableOrder do
      def not_private(str) do
        process_url(str)
      end

      def process_url(_str) do
        :first
      end

      # There was a bug where the order in which we removed
      # overridable expressions lead to errors. This module
      # aims to guarantee removing process_url/1 before we
      # remove the function that depends on it does not cause
      # errors. If it compiles, it works!
      defoverridable process_url: 1, not_private: 1

      def process_url(_str) do
        :second
      end
    end
  end

  test "overridable works with defaults" do
    defmodule OverridableDefault do
      def fun(value, opt \\ :from_parent) do
        {value, opt}
      end

      defmacro macro(value, opt \\ :from_parent) do
        {{value, opt}, Macro.escape(__CALLER__)}
      end

      # There was a bug where the default function would
      # attempt to call its overridable name instead of
      # func/1. If it compiles, it works!
      defoverridable fun: 1, fun: 2, macro: 1, macro: 2

      def fun(value) do
        {value, super(value)}
      end

      defmacro macro(value) do
        {{value, super(value)}, Macro.escape(__CALLER__)}
      end
    end

    defmodule OverridableCall do
      require OverridableDefault
      OverridableDefault.fun(:foo)
      OverridableDefault.macro(:bar)
    end
  end

  test "overridable is made concrete if no other is defined" do
    assert Overridable.sample() == 1
  end

  test "overridable overridden with super" do
    assert Overridable.with_super() == 3
  end

  test "overridable overridden without super" do
    assert Overridable.without_super() == :without_super
  end

  test "calling super with multiple args" do
    assert Overridable.super_with_multiple_args(1, 2) == 5
  end

  test "overridable with many clauses" do
    assert Overridable.many_clauses(0) == 11
    assert Overridable.many_clauses(1) == 13
    assert Overridable.many_clauses(2) == 17
    assert Overridable.many_clauses(3) == 24
  end

  test "overridable definitions are private" do
    refute {:"with_super (overridable 0)", 0} in Overridable.module_info(:exports)
    refute {:"with_super (overridable 1)", 0} in Overridable.module_info(:exports)
  end

  test "overridable macros" do
    a = 11
    assert Overridable.overridable_macro(a) == 1111
    assert Overridable.private_macro_call() == 1111
  end

  test "invalid super call" do
    message =
      "nofile:4: no super defined for foo/0 in module Kernel.OverridableOrder.Forwarding. " <>
        "Overridable functions available are: bar/0"

    assert_raise CompileError, message, fn ->
      Code.eval_string("""
      defmodule Kernel.OverridableOrder.Forwarding do
        def bar(), do: 1
        defoverridable bar: 0
        def foo(), do: super()
      end
      """)
    end

    purge(Kernel.OverridableOrder.Forwarding)
  end

  test "undefined functions can't be marked as overridable" do
    message = "cannot make function foo/2 overridable because it was not defined"

    assert_raise ArgumentError, message, fn ->
      Code.eval_string("""
      defmodule Kernel.OverridableOrder.Foo do
        defoverridable foo: 2
      end
      """)
    end

    purge(Kernel.OverridableOrder.Foo)
  end

  test "overrides with behaviour" do
    defmodule OverridableWithBehaviour do
      @behaviour Elixir.Kernel.OverridableExampleBehaviour

      def required_callback(), do: "original"

      def optional_callback(), do: "original"

      def not_a_behaviour_callback(), do: "original"

      defmacro required_macro_callback(boolean) do
        quote do
          if unquote(boolean) do
            "original"
          end
        end
      end

      defoverridable Elixir.Kernel.OverridableExampleBehaviour

      defmacro optional_macro_callback(arg1, arg2), do: {arg1, arg2}

      assert Module.overridable?(__MODULE__, {:required_callback, 0})
      assert Module.overridable?(__MODULE__, {:optional_callback, 0})
      assert Module.overridable?(__MODULE__, {:required_macro_callback, 1})
      refute Module.overridable?(__MODULE__, {:optional_macro_callback, 1})
      refute Module.overridable?(__MODULE__, {:not_a_behaviour_callback, 1})
    end
  end

  test "undefined module can't be passed as argument to defoverridable" do
    message =
      "cannot pass module Kernel.OverridableTest.Bar as argument to defoverridable/1 because it was not defined"

    assert_raise ArgumentError, message, fn ->
      Code.eval_string("""
      defmodule Kernel.OverridableTest.Foo do
        defoverridable Kernel.OverridableTest.Bar
      end
      """)
    end

    purge(Kernel.OverridableTest.Foo)
  end

  test "module without @behaviour can't be passed as argument to defoverridable" do
    message =
      "cannot pass module Kernel.OverridableExampleBehaviour as argument to defoverridable/1" <>
        " because its corresponding behaviour is missing. Did you forget to add " <>
        "@behaviour Kernel.OverridableExampleBehaviour?"

    assert_raise ArgumentError, message, fn ->
      Code.eval_string("""
      defmodule Kernel.OverridableTest.Foo do
        defoverridable Kernel.OverridableExampleBehaviour
      end
      """)
    end

    purge(Kernel.OverridableTest.Foo)
  end

  test "module with no callbacks can't be passed as argument to defoverridable" do
    message =
      "cannot pass module Kernel.OverridableTest.Bar as argument to defoverridable/1 because it does not define any callbacks"

    assert_raise ArgumentError, message, fn ->
      Code.eval_string("""
      defmodule Kernel.OverridableTest.Bar do
      end
      defmodule Kernel.OverridableTest.Foo do
        @behaviour Kernel.OverridableTest.Bar
        defoverridable Kernel.OverridableTest.Bar
      end
      """)
    end

    purge(Kernel.OverridableTest.Bar)
    purge(Kernel.OverridableTest.Foo)
  end

  test "atom which is not a module can't be passed as argument to defoverridable" do
    message = "cannot pass module :abc as argument to defoverridable/1 because it was not defined"

    assert_raise ArgumentError, message, fn ->
      Code.eval_string("""
      defmodule Kernel.OverridableTest.Foo do
        defoverridable :abc
      end
      """)
    end

    purge(Kernel.OverridableTest.Foo)
  end
end
