defmodule Predicator.Vocabulary do
  @moduledoc """
  The grammar's fixed vocabulary, enumerated for editor tooling.

  An expression editor that offers completion needs to know what the language
  accepts: which operators exist, which words are reserved, which duration
  units follow a number, and which functions are callable. Function names have
  always been reachable - `Predicator.Context.new/2` resolves them from
  `Predicator.FunctionProvider` modules - but the operator and keyword lexemes
  lived only inside `Predicator.Lexer`'s private clause heads, so a consumer
  wanting completion had to hard-code a second copy of the grammar and keep it
  in sync by hand. This module is the first copy made public instead.

  It is a reading surface, not a parsing one. Nothing here participates in
  lexing, parsing, compiling, or evaluating; the entries describe the grammar
  the lexer already implements, and adding a category or a doc string changes
  no program's meaning. `test/predicator/vocabulary_sync_test.exs` binds the
  two together: it round-trips every enumerated lexeme through
  `Predicator.Lexer.tokenize/1`, and it checks the enumeration against the
  lexer's own `t:Predicator.Lexer.token/0` union, its `classify_identifier/1`
  clause heads, and its `duration_unit?/1` clause heads, so a token added to
  the lexer without a matching entry here turns the suite red rather than
  quietly shipping an editor that cannot complete it.

  ## Entries

  Every static entry is a map with at least these five keys:

  - `:lexeme` - the exact source text, e.g. `">="`, `"contains"`
  - `:token_type` - the `t:Predicator.Lexer.token/0` tag it lexes to
  - `:category` - one of `categories/0`
  - `:display` - what an editor shows in a completion list, which differs from
    the lexeme only where the bare lexeme reads badly on its own (`"a + b"`
    for `"+"`, `"1d"` for the duration unit `"d"`)
  - `:doc` - one line of prose, sentence case, no trailing period

  A function entry carries the same five keys plus `:arity`, since a function's
  arity is part of what an editor needs to complete a call. Its `:doc` is
  `nil`: a provider binds a name to `{arity, atom}` and carries no description,
  so there is nothing truthful to put there, and an invented sentence in a
  documented field is worse than an absent one.

  ## Operator entries

  An entry in an operator category - the six categories `operators/0` returns -
  carries four more keys, because a structured editor needs more about an
  operator than a completion list does. A picklist has to name the operator in
  a sentence, know how many operands it takes, know which atom the parser will
  put in the AST for it, and know which kinds of value it is worth offering it
  for at all:

  - `:label` - a short phrase read in place of the operator, e.g. `"is at
    least"` for `">="`. `:display` is a template and `:doc` is a sentence of
    prose about the semantics; neither is a UI string, which is why this is
    its own key
  - `:arity` - how many operands the operator takes. `"-"` takes `[1, 2]`,
    since it is both subtraction and negation
  - `:ast_op` - the atom `Predicator.Parser.parse/2` puts in the node it
    builds, which differs from `:token_type` for three operators (`:in_op`
    becomes `:in`, `:contains_op` becomes `:contains`, `:strict_equal`
    becomes `:strict_eq`). `nil` where no node carries the operator as an
    atom of its own
  - `:value_kinds` - the `t:value_kind/0`s the operator is worth offering for,
    as the kind of the value on its right. `nil` for an operator that does not
    compare a field against a value at all - the logical, arithmetic, temporal
    and cast categories

  Entries outside an operator category carry none of the four. That is the
  shape `t:function_entry/0` already has against `t:entry/0`: an entry carries
  the keys its kind of thing has, and no placeholder keys for the ones it does
  not.

  ### What `:value_kinds` admits, and two deliberate exclusions

  The admissions follow `Predicator.Evaluator`'s own comparison semantics.
  Ordered comparison (`>`, `>=`, `<`, `<=`) is admitted where the evaluator
  orders the kind meaningfully: numbers and strings through its `types_match`
  guard, dates and datetimes chronologically, durations as the numbers they
  reduce to. Equality is admitted for every scalar kind. `in` takes a list on
  its right and nothing else; `contains` takes a list on its *left*, so the
  value beside it is a scalar of any kind.

  Two things the evaluator does answer are still not admitted, because a
  picklist offering them would be offering nonsense:

  | Excluded | Why |
  |---|---|
  | Ordered comparison of booleans | `types_match` admits them, so `true > false` evaluates - by Erlang term order, which is not a fact about the author's data |
  | Equality against a list | Lists compare with `==`, but the operator an author reaches for beside a list is `in`, and offering both invites writing the one that is almost never meant |

  Neither exclusion narrows the grammar. Both are the kind of judgement
  `Predicator.Simple` already records for the shapes it leaves out: the
  language still accepts them, and the structured surface still does not offer
  them.

  ## Case

  The word operators are accepted in two cases - `and` and `AND` both lex to
  `:and_op` - and both are enumerated, as separate entries with the same
  `:token_type`. An editor offering only one of them would be offering a house
  style the grammar does not have. `if`, `else`, `while`, and the temporal
  words are lower-case only, and are enumerated only that way.

  ## Examples

      iex> Predicator.Vocabulary.by_category(:arithmetic) |> Enum.map(& &1.lexeme)
      ["+", "-", "*", "/", "%"]

      iex> Predicator.Vocabulary.tokens() |> Enum.find(&(&1.lexeme == ">=")) |> Map.take([:token_type, :category])
      %{token_type: :gte, category: :comparison}

      iex> Predicator.Vocabulary.functions() |> Enum.any?(&(&1.lexeme == "len"))
      true

  """

  alias Predicator.Context

  @typedoc """
  The kind of thing an entry is, which is what an editor groups a completion
  list by.

  `:cast` holds the single `::` postfix operator (ADR-0011); `:grouping` holds
  the bracket pairs; `:punctuation` holds the separators that are neither.
  """
  @type category ::
          :comparison
          | :logical
          | :arithmetic
          | :membership
          | :temporal
          | :control
          | :literal
          | :grouping
          | :punctuation
          | :cast
          | :duration_unit
          | :function

  @typedoc "A fixed lexeme of the grammar - an operator, keyword, literal word, separator, or duration unit."
  @type entry :: %{
          lexeme: binary(),
          token_type: atom(),
          category: category(),
          display: binary(),
          doc: binary()
        }

  @typedoc """
  A callable function, resolved from the providers rather than from the lexer.

  `:token_type` is `:qualified_function_name` for a namespaced name
  (`"Math.abs"`) and `:function_name` for a bare one (`"len"`), matching what
  the lexer produces for a call to it.
  """
  @type function_entry :: %{
          lexeme: binary(),
          token_type: :function_name | :qualified_function_name,
          category: :function,
          display: binary(),
          doc: nil,
          arity: Predicator.Evaluator.function_arity()
        }

  @typedoc """
  The kind of a value on the right of an operator, as a structured editor
  models it.

  These are the kinds `Predicator.Simple` admits as a scalar or as a list of
  them, and no others.

  `:number` covers integer and float literals together. They are two shapes in
  `t:Predicator.Simple.scalar/0`, because the AST literal differs and the
  round-trip has to preserve which one was written, but they are one kind
  here: every operator worth offering beside `19.99` is worth offering beside
  `500`, so a `:float` kind would duplicate `:number`'s list exactly and make
  every editor branch on a distinction that changes nothing it renders
  (px-gv1).

  There is no `:relative_date` either, because `3d ago` is a datetime by the
  time anything compares it.
  """
  @type value_kind ::
          :string | :number | :boolean | :date | :datetime | :duration | :list

  @typedoc """
  An operator entry: an `t:entry/0` plus what a structured editor needs in
  order to offer the operator as a choice. See "Operator entries" above.
  """
  @type operator_entry :: %{
          lexeme: binary(),
          token_type: atom(),
          category: category(),
          display: binary(),
          doc: binary(),
          label: binary(),
          arity: 0 | 1 | 2 | [1 | 2, ...],
          ast_op: atom() | nil,
          value_kinds: [value_kind()] | nil
        }

  @value_kinds [:string, :number, :boolean, :date, :datetime, :duration, :list]

  @categories [
    :comparison,
    :logical,
    :arithmetic,
    :membership,
    :temporal,
    :control,
    :literal,
    :grouping,
    :punctuation,
    :cast,
    :duration_unit,
    :function
  ]

  # The operator categories, in the sense `operators/0` means: the categories
  # whose entries combine or compare values. `:literal`, `:control`,
  # `:grouping`, `:punctuation`, and `:duration_unit` are excluded because
  # none of them is an operator in any useful sense for a completion list.
  @operator_categories [:comparison, :logical, :arithmetic, :membership, :temporal, :cast]

  # {lexeme, token_type, category, display, doc}. Display equals the lexeme
  # unless the bare lexeme is unreadable on its own.
  @tokens [
    # Comparison
    {">", :gt, :comparison, "a > b", "Greater than"},
    {">=", :gte, :comparison, "a >= b", "Greater than or equal to"},
    {"<", :lt, :comparison, "a < b", "Less than"},
    {"<=", :lte, :comparison, "a <= b", "Less than or equal to"},
    {"=", :eq, :comparison, "a = b", "Equal to"},
    {"==", :equal_equal, :comparison, "a == b", "Equal to, spelled the C way"},
    {"===", :strict_equal, :comparison, "a === b", "Equal to, without type coercion"},
    {"!=", :ne, :comparison, "a != b", "Not equal to"},
    {"!==", :strict_ne, :comparison, "a !== b", "Not equal to, without type coercion"},

    # Logical
    {"and", :and_op, :logical, "a and b", "True when both sides are true"},
    {"AND", :and_op, :logical, "a AND b", "True when both sides are true"},
    {"&&", :and_and, :logical, "a && b", "True when both sides are true"},
    {"or", :or_op, :logical, "a or b", "True when either side is true"},
    {"OR", :or_op, :logical, "a OR b", "True when either side is true"},
    {"||", :or_or, :logical, "a || b", "True when either side is true"},
    {"not", :not_op, :logical, "not a", "Negates the value to its right"},
    {"NOT", :not_op, :logical, "NOT a", "Negates the value to its right"},
    {"!", :bang, :logical, "!a", "Negates the value to its right"},

    # Arithmetic
    {"+", :plus, :arithmetic, "a + b", "Addition"},
    {"-", :minus, :arithmetic, "a - b", "Subtraction, or negation of a single value"},
    {"*", :multiply, :arithmetic, "a * b", "Multiplication"},
    {"/", :divide, :arithmetic, "a / b", "Division"},
    {"%", :modulo, :arithmetic, "a % b", "Remainder after division"},

    # Membership
    {"in", :in_op, :membership, "a in [b, c]",
     "True when the left value is a member of the right"},
    {"IN", :in_op, :membership, "a IN [b, c]",
     "True when the left value is a member of the right"},
    {"contains", :contains_op, :membership, "a contains b",
     "True when the left collection or string holds the right value"},
    {"CONTAINS", :contains_op, :membership, "a CONTAINS b",
     "True when the left collection or string holds the right value"},

    # Temporal
    {"ago", :ago_op, :temporal, "3d ago", "A duration before now"},
    {"from", :from_op, :temporal, "3d from now", "A duration after the point that follows"},
    {"now", :now_op, :temporal, "now", "The current instant"},
    {"next", :next_op, :temporal, "next 3d", "The window forward from now"},
    {"last", :last_op, :temporal, "last 3d", "The window back from now"},

    # Control
    {"if", :if_kw, :control, "if a { b }", "Conditional statement"},
    {"else", :else_kw, :control, "else { b }", "The alternative branch of an if"},
    {"while", :while_kw, :control, "while a { b }", "Loop statement, under a fixed budget"},

    # Literals
    {"true", :boolean, :literal, "true", "The boolean true"},
    {"false", :boolean, :literal, "false", "The boolean false"},
    {"null", :null, :literal, "null", "The null value"},
    {"undefined", :undefined, :literal, "undefined", "The undefined value"},

    # Grouping
    {"(", :lparen, :grouping, "(", "Opens a grouped expression or an argument list"},
    {")", :rparen, :grouping, ")", "Closes a grouped expression or an argument list"},
    {"[", :lbracket, :grouping, "[", "Opens a list literal or an index"},
    {"]", :rbracket, :grouping, "]", "Closes a list literal or an index"},
    {"{", :lbrace, :grouping, "{", "Opens an object literal or a statement block"},
    {"}", :rbrace, :grouping, "}", "Closes an object literal or a statement block"},

    # Cast
    {"::", :double_colon, :cast, "a :: integer", "Postfix cast; failure yields undefined"},

    # Punctuation
    {",", :comma, :punctuation, ",", "Separates list elements and arguments"},
    {":", :colon, :punctuation, "key: value", "Separates a key from its value"},
    {";", :semicolon, :punctuation, ";", "Separates statements"},
    {".", :dot, :punctuation, "a.b", "Property access"},

    # Duration units, which are only units directly after a number
    {"y", :duration_unit, :duration_unit, "1y", "Years"},
    {"mo", :duration_unit, :duration_unit, "1mo", "Months"},
    {"w", :duration_unit, :duration_unit, "1w", "Weeks"},
    {"d", :duration_unit, :duration_unit, "1d", "Days"},
    {"h", :duration_unit, :duration_unit, "1h", "Hours"},
    {"m", :duration_unit, :duration_unit, "1m", "Minutes"},
    {"s", :duration_unit, :duration_unit, "1s", "Seconds"},
    {"ms", :duration_unit, :duration_unit, "1ms", "Milliseconds"}
  ]

  # The kinds an ordered comparison is worth offering for: the ones
  # Predicator.Evaluator orders meaningfully. Booleans are excluded even
  # though `types_match` admits them - see the moduledoc.
  @ordered_kinds [:number, :string, :date, :datetime, :duration]

  # The scalar kinds. Equality is offered for all of them, and so is the
  # right-hand side of `contains`, whose left side is the list.
  @scalar_kinds [:string, :number, :boolean, :date, :datetime, :duration]

  # token_type => {label, arity, ast_op, value_kinds}, for the operator
  # categories only. Keyed by token type rather than by lexeme because a word
  # operator is enumerated in both cases and the two spellings are the same
  # operator: `in` and `IN` share this row, as they should.
  #
  # `:eq` is the one comparison with no admitted kind at all. `=` lexes, but
  # the parser rejects it in expression position ("'=' is not an equality
  # operator - use '==' for equality"), so an editor that offered it would be
  # offering source that cannot parse. Its empty list says exactly that, and
  # says it in the same place as every other operator's answer.
  @operator_extras %{
    gt: {"is greater than", 2, :gt, @ordered_kinds},
    gte: {"is at least", 2, :gte, @ordered_kinds},
    lt: {"is less than", 2, :lt, @ordered_kinds},
    lte: {"is at most", 2, :lte, @ordered_kinds},
    eq: {"is equal to", 2, nil, []},
    equal_equal: {"is equal to", 2, :equal_equal, @scalar_kinds},
    strict_equal: {"is exactly equal to", 2, :strict_eq, @scalar_kinds},
    ne: {"is not equal to", 2, :ne, @scalar_kinds},
    strict_ne: {"is not exactly equal to", 2, :strict_ne, @scalar_kinds},
    and_op: {"and", 2, nil, nil},
    and_and: {"and", 2, nil, nil},
    or_op: {"or", 2, nil, nil},
    or_or: {"or", 2, nil, nil},
    not_op: {"not", 1, nil, nil},
    bang: {"not", 1, nil, nil},
    plus: {"plus", 2, nil, nil},
    minus: {"minus", [1, 2], nil, nil},
    multiply: {"times", 2, nil, nil},
    divide: {"divided by", 2, nil, nil},
    modulo: {"remainder of", 2, nil, nil},
    in_op: {"is one of", 2, :in, [:list]},
    contains_op: {"contains", 2, :contains, @scalar_kinds},
    ago_op: {"ago", 1, nil, nil},
    from_op: {"from", 2, nil, nil},
    now_op: {"now", 0, nil, nil},
    next_op: {"next", 1, nil, nil},
    last_op: {"last", 1, nil, nil},
    double_colon: {"cast to", 2, nil, nil}
  }

  @entries Enum.map(@tokens, fn {lexeme, token_type, category, display, doc} ->
             entry = %{
               lexeme: lexeme,
               token_type: token_type,
               category: category,
               display: display,
               doc: doc
             }

             case Map.fetch(@operator_extras, token_type) do
               {:ok, {label, arity, ast_op, value_kinds}} ->
                 Map.merge(entry, %{
                   label: label,
                   arity: arity,
                   ast_op: ast_op,
                   value_kinds: value_kinds
                 })

               :error ->
                 entry
             end
           end)

  @doc """
  Every category an entry can carry, in the order `tokens/0` groups them.

  ## Examples

      iex> :duration_unit in Predicator.Vocabulary.categories()
      true

  """
  @spec categories() :: [category(), ...]
  def categories, do: @categories

  @doc """
  Every fixed lexeme of the grammar: operators, keywords, literal words,
  brackets, separators, and duration units.

  Functions are not here - they depend on which providers a caller resolves,
  so they come from `functions/0` and `functions/1` instead. `all/0` is the
  two lists together.

  ## Examples

      iex> Predicator.Vocabulary.tokens() |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.member?(:function)
      false

  """
  @spec tokens() :: [entry() | operator_entry(), ...]
  def tokens, do: @entries

  @doc """
  The entries in one category.

  The argument is guarded against `categories/0`, so a misspelled category
  raises `FunctionClauseError` rather than returning an empty list that reads
  like a category the grammar happens not to use.

  ## Examples

      iex> Predicator.Vocabulary.by_category(:cast) |> Enum.map(& &1.lexeme)
      ["::"]

      iex> Predicator.Vocabulary.by_category(:literal) |> Enum.map(& &1.lexeme)
      ["true", "false", "null", "undefined"]

  """
  @spec by_category(category()) :: [entry() | operator_entry() | function_entry()]
  def by_category(:function), do: functions()
  def by_category(category) when category in @categories, do: filter_category(@entries, category)

  @doc """
  Every kind of value an operator can be offered for.

  The vocabulary of `:value_kinds` on an `t:operator_entry/0`, enumerated so a
  caller can iterate the kinds rather than hard-code them.

  ## Examples

      iex> Predicator.Vocabulary.value_kinds()
      [:string, :number, :boolean, :date, :datetime, :duration, :list]

  """
  @spec value_kinds() :: [value_kind(), ...]
  def value_kinds, do: @value_kinds

  @doc """
  The entries that combine or compare values: the comparison, logical,
  arithmetic, membership, temporal, and cast categories.

  Every entry here is an `t:operator_entry/0`, carrying `:label`, `:arity`,
  `:ast_op`, and `:value_kinds` on top of what `tokens/0` carries. See
  "Operator entries" in the module documentation for what each one means.

  ## Examples

      iex> Predicator.Vocabulary.operators() |> Enum.all?(&(&1.category != :literal))
      true

      iex> Predicator.Vocabulary.operators() |> Enum.find(&(&1.lexeme == ">=")) |> Map.take([:label, :arity, :ast_op])
      %{label: "is at least", arity: 2, ast_op: :gte}

      iex> Predicator.Vocabulary.operators() |> Enum.find(&(&1.lexeme == "IN")) |> Map.fetch!(:value_kinds)
      [:list]

  """
  @spec operators() :: [operator_entry(), ...]
  def operators, do: Enum.filter(@entries, &(&1.category in @operator_categories))

  @doc """
  The word-shaped entries: everything an editor must not offer as a plain
  identifier, because the lexer classifies it as something else.

  Duration units are excluded. `d` is an ordinary identifier everywhere except
  immediately after a number, so treating it as a reserved word would be
  wrong; `by_category(:duration_unit)` is where those live.

  ## Examples

      iex> Predicator.Vocabulary.keywords() |> Enum.map(& &1.lexeme) |> Enum.member?("contains")
      true

      iex> Predicator.Vocabulary.keywords() |> Enum.map(& &1.lexeme) |> Enum.member?("d")
      false

  """
  @spec keywords() :: [entry() | operator_entry(), ...]
  def keywords do
    Enum.filter(@entries, fn entry ->
      entry.category != :duration_unit and entry.lexeme =~ ~r/\A[A-Za-z]+\z/
    end)
  end

  @doc """
  The callable functions, resolved the same way `Predicator.Context.new/2`
  resolves them.

  `opts` takes `:builtins`, `:providers`, and `:functions`, and is passed
  straight to `Predicator.Context.resolve_functions/1`, so the names returned
  here are exactly the names a context built with the same options will
  accept - including a host's own providers, which is the case an editor
  embedded in a host application actually has.

  Entries are sorted by name, since a dispatch map has no order and a
  completion list needs one.

  ## Examples

      iex> Predicator.Vocabulary.functions(builtins: false)
      []

      iex> Predicator.Vocabulary.functions() |> Enum.find(&(&1.lexeme == "len")) |> Map.take([:display, :arity, :doc])
      %{display: "len(...)", arity: 1, doc: nil}

      iex> Predicator.Vocabulary.functions() |> Enum.find(&(&1.lexeme == "Math.abs")) |> Map.fetch!(:token_type)
      :qualified_function_name

  """
  @spec functions() :: [function_entry()]
  @spec functions(keyword()) :: [function_entry()]
  def functions(opts \\ []) do
    opts
    |> Context.resolve_functions()
    |> Enum.map(fn {name, {arity, _entry}} ->
      %{
        lexeme: name,
        token_type: function_token_type(name),
        category: :function,
        display: display_call(name, arity),
        doc: nil,
        arity: arity
      }
    end)
    |> Enum.sort_by(& &1.lexeme)
  end

  @doc """
  Every entry: `tokens/0` followed by `functions/1` on the same `opts`.

  ## Examples

      iex> length(Predicator.Vocabulary.all()) == length(Predicator.Vocabulary.tokens()) + length(Predicator.Vocabulary.functions())
      true

  """
  @spec all() :: [entry() | operator_entry() | function_entry(), ...]
  @spec all(keyword()) :: [entry() | operator_entry() | function_entry(), ...]
  def all(opts \\ []), do: @entries ++ functions(opts)

  @spec filter_category([entry() | operator_entry()], category()) :: [entry() | operator_entry()]
  defp filter_category(entries, category), do: Enum.filter(entries, &(&1.category == category))

  @spec function_token_type(binary()) :: :function_name | :qualified_function_name
  defp function_token_type(name) do
    if String.contains?(name, "."), do: :qualified_function_name, else: :function_name
  end

  # A name accepting several arities displays as its smallest call.
  @spec display_call(binary(), Predicator.Evaluator.function_arity()) :: binary()
  defp display_call(name, 0), do: name <> "()"
  defp display_call(name, arity) when is_integer(arity), do: name <> "(...)"

  defp display_call(name, arities) when is_list(arities),
    do: display_call(name, Enum.min(arities))
end
