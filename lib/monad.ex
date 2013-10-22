defmodule Monad do
  use Behaviour

  @moduledoc """
  Helpers for writing monadic do-notation macros.

  ## Usage

  To add monadic do notation macro to your code you first need to
  define a module that implements Macro.Monad's callbacks. That is, it
  needs to have a return/1 and a bind/2.

  Then simply define a macro in which you call monad_do_notation with
  your implementation module and the do block passed to your macro,
  for example:

      defmacro source(opts) do
        Macro.Monad.monad_do_notation(Pipe, opts[:do])
      end

  That's it, now you can write stuff like (with appropriate
  `source_list` and such):

      source do
        yield_list [1, 2, 3]
        return 3
      end

  ## Terminology

  In this module the term "monad" is used fairly loosely to address
  the whole concept of a monad. For an explanation what a monad is,
  look elsewhere, the internet is full of good and not so good monad
  tutorials.

  The term "monadic value" as used here refers to something you can
  pass to a bind/2 function as the first argument. Because monads can
  be so different what is a monadic value for one monad doesn't need
  to be for another.

  ## Do-notation

  The do-notation supported is pretty simple. Basically there are four rules to
  remember:

  1. Every "statement" (i.e. thing on it's own line or separated by
     `;`) has to return a monadic value unless it's a "let statement".

  2. To use the value "inside" a monadic value write "pattern <-
     action" where "pattern" is a normal Elixir pattern and "action"
     is some expression which returns a monadic value.

  3. To use ordinary Elixir code inside a do-notation block prefix it
     with `let`. For multiple expressions or those for which
     precedence rules cause annoyances you can use `let` with a do
     block.

  4. For your convenience the `return/1` function of the monad is
     automatically imported inside the do-block.

  ## Example

  If you don't understand any of the above, don't worry, monads are
  one of those things which are easier to use in practice than in
  theory. Here's an example from the tests of a simple but often
  useful monad, the list monad:

      defmodule ListM do
        @behaviour Macro.Monad
        def return(x), do: [x]
        def bind(m, f), do: Enum.flat_map(m, f)

        defmacro monad(opts) do
          Macro.Monad.monad_do_notation(MonadTest.ListM, opts[:do])
        end
      end

      test "list monad" do
        require ListM

        prods = ListM.monad do
          x <- Enum.to_list(2..3)
          y <- Enum.to_list(2..3)
          let f = &(&1 * &2)
          return { x, y, f.(x, y) }
        end

        assert prods == [
          { 2, 2, 4 },
          { 2, 3, 6 },
          { 3, 2, 6 },
          { 3, 3, 9 }
        ]
      end

  The list monad is pretty much like the list comprehensions (or more
  exactly: list comprehensions are based on the concept of the list
  monad).

  ## Monad laws

  Return and bind need to obey a few rules (the "monad laws") to avoid
  surprising the user. In the following equivalences M stands for your
  monad module, a for an arbitrary value, m for a monadic value and f
  and g for functions that given a value return a new monadic value.

  Equivalence means you can always substitute the left side for the
  right side and vice versa in an expression without changing the
  result or side-effects

  * `M.bind(M.return(m), f)`    <=> `f.(m)` ("left identity")
  * `M.bind(m, &M.return/1)`    <=> `m`     ("right identity")
  * `M.bind(m, f) |> M.bind(g)` <=> `m |> M.bind(fn y -> M.bind(f.(y), g))` ("associativity")
  """

  @doc """
  Make the `m` macro available in your module.
  """
  defmacro __using__(_opts) do
    quote location: :keep do
      require Monad
      import Monad, only: [m: 2]
    end
  end

  defmacro m(mod, do: block) do
    case block do
      nil ->
        raise ArgumentError, message: "missing or empty do block"
      {:__block__, meta, exprs} ->
        {:__block__, meta, expand(mod, exprs)}
      expr ->
        {:__block__, [], expand(mod, [expr])}
    end
  end

  defp expand(mod, [{:let, _, let_exprs} | exprs]) do
    if length(let_exprs) == 1 and is_list(hd(let_exprs)) do
      case Keyword.fetch(hd(let_exprs), :do) do
        :error ->
          let_exprs ++ expand(mod, exprs)
        {:ok, e} ->
          [e | expand(mod, exprs)]
      end
    else
      let_exprs ++ expand(mod, exprs)
    end
  end
  defp expand(mod, [{:<-, _, [lhs, rhs]} | exprs]) do
    # x <- m ==> bind(b, fn x -> ... end)
    expand_bind(mod, lhs, rhs, exprs)
  end
  defp expand(_, [expr]) do
    [expr]
  end
  defp expand(mod, [expr | exprs]) do
    # m ==> bind(b, fn _ -> ... end)
    expand_bind(mod, quote(do: _), expr, exprs)
  end
  defp expand(_, []) do
    []
  end

  defp expand_bind(mod, lhs, rhs, exprs) do
    [quote do
      unquote(mod).bind(unquote(rhs),
                        fn unquote(lhs) ->
                             unquote_splicing(expand(mod, exprs))
                        end)
    end]
  end

  @type monad :: any

  @callback return(any) :: monad
  @callback bind(monad, (any -> monad)) :: monad
end
