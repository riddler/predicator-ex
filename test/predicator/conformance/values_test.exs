defmodule Predicator.Conformance.ValuesTest do
  use ExUnit.Case, async: true

  doctest Predicator.Conformance.Values

  alias Predicator.Conformance.Values

  # Every ISA value type (docs/isa.md section 3), plus nested lists and maps,
  # a duration with and without milliseconds, and :undefined - the exact set
  # Phase 2's success criteria names for the round-trip property.
  @round_trip_values [
    42,
    -7,
    3.5,
    "a string",
    "",
    true,
    false,
    [],
    [1, 2, 3],
    [1, "two", true, [3, 4]],
    %{},
    %{"a" => 1, "b" => [1, 2]},
    %{"nested" => %{"deep" => %{"deeper" => :undefined}}},
    ~D[2026-08-06],
    ~U[2026-08-06T12:00:00Z],
    Predicator.Duration.new(days: 3),
    Predicator.Duration.new(days: 3, hours: 8, minutes: 30),
    Predicator.Duration.new(seconds: 1, milliseconds: 500),
    Predicator.Duration.new(),
    :undefined
  ]

  describe "round-trip: from_json(to_json(v)) == {:ok, v}" do
    test "holds for every ISA value type, nested lists and maps, and both duration shapes" do
      for value <- @round_trip_values do
        assert {:ok, encoded} = Values.to_json(value),
               "to_json/1 failed to encode #{inspect(value)}"

        assert Values.from_json(encoded) == {:ok, value},
               "round-trip mismatch for #{inspect(value)}, encoded as #{inspect(encoded)}"
      end
    end
  end

  describe "to_json/1 - tagged encoding shape" do
    test ":undefined" do
      assert Values.to_json(:undefined) == {:ok, %{"$type" => "undefined"}}
    end

    test "Date" do
      assert Values.to_json(~D[2026-08-06]) ==
               {:ok, %{"$type" => "date", "value" => "2026-08-06"}}
    end

    test "DateTime" do
      assert Values.to_json(~U[2026-08-06T12:00:00Z]) ==
               {:ok, %{"$type" => "datetime", "value" => "2026-08-06T12:00:00Z"}}
    end

    test "duration without milliseconds carries the seven-key map and no milliseconds key" do
      duration = Predicator.Duration.new(days: 3)

      assert {:ok, %{"$type" => "duration", "value" => value}} = Values.to_json(duration)

      assert value == %{
               "years" => 0,
               "months" => 0,
               "weeks" => 0,
               "days" => 3,
               "hours" => 0,
               "minutes" => 0,
               "seconds" => 0
             }

      refute Map.has_key?(value, "milliseconds")
    end

    test "duration with milliseconds carries the eighth key" do
      duration = Predicator.Duration.new(seconds: 1, milliseconds: 500)

      assert {:ok, %{"$type" => "duration", "value" => value}} = Values.to_json(duration)
      assert value["milliseconds"] == 500
      assert value["seconds"] == 1
    end

    test "plain scalars mean themselves" do
      assert Values.to_json(42) == {:ok, 42}
      assert Values.to_json(3.5) == {:ok, 3.5}
      assert Values.to_json("hello") == {:ok, "hello"}
      assert Values.to_json(true) == {:ok, true}
    end

    test "lists encode element-wise, preserving order" do
      assert Values.to_json([1, :undefined, "x"]) ==
               {:ok, [1, %{"$type" => "undefined"}, "x"]}
    end

    test "plain maps encode member-wise with string keys" do
      assert Values.to_json(%{"a" => 1, "b" => :undefined}) ==
               {:ok, %{"a" => 1, "b" => %{"$type" => "undefined"}}}
    end
  end

  describe "to_json/1 - the $type collision guard" do
    test "a plain map containing a literal \"$type\" key returns an error, not a tag" do
      assert Values.to_json(%{"$type" => "not_really_a_tag", "value" => 1}) ==
               {:error, {:unencodable, %{"$type" => "not_really_a_tag", "value" => 1}}}
    end

    test "the guard applies inside a nested map" do
      term = %{"outer" => %{"$type" => "sneaky"}}
      assert {:error, {:unencodable, %{"$type" => "sneaky"}}} = Values.to_json(term)
    end

    test "the guard applies inside a list" do
      term = [1, %{"$type" => "sneaky"}]
      assert {:error, {:unencodable, %{"$type" => "sneaky"}}} = Values.to_json(term)
    end
  end

  describe "to_json/1 - unencodable terms" do
    test "a term outside the ISA value domain returns an error rather than raising" do
      assert Values.to_json({:a, :tuple}) == {:error, {:unencodable, {:a, :tuple}}}
      assert Values.to_json(self()) == {:error, {:unencodable, self()}}
    end

    test "an atom other than true/false is not encodable" do
      assert Values.to_json(:some_atom) == {:error, {:unencodable, :some_atom}}
    end
  end

  describe "from_json/1 - unknown $type" do
    test "rejects an unrecognized tag" do
      assert Values.from_json(%{"$type" => "not_a_real_type"}) ==
               {:error, {:unknown_type, "not_a_real_type"}}
    end
  end

  describe "from_json/1 - malformed tags" do
    test "a duration tag missing a required unit key is an error, not a crash" do
      incomplete = %{"$type" => "duration", "value" => %{"years" => 0}}
      assert {:error, {:invalid_duration, _value}} = Values.from_json(incomplete)
    end

    test "an invalid date string is an error, not a crash" do
      assert {:error, {:invalid_date, _reason}} =
               Values.from_json(%{"$type" => "date", "value" => "not-a-date"})
    end

    test "an invalid datetime string is an error, not a crash" do
      assert {:error, {:invalid_datetime, _reason}} =
               Values.from_json(%{"$type" => "datetime", "value" => "not-a-datetime"})
    end
  end
end
