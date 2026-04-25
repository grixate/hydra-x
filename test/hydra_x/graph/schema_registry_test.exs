defmodule HydraX.Graph.SchemaRegistryTest do
  use ExUnit.Case, async: true

  alias HydraX.Graph.SchemaRegistry

  describe "validate_attributes/2" do
    test "passes when schema is empty" do
      assert SchemaRegistry.validate_attributes(%{}, %{"anything" => 1}) == :ok
    end

    test "checks required fields" do
      schema = %{"required" => ["summary"], "properties" => %{"summary" => %{"type" => "string"}}}
      assert {:error, errors} = SchemaRegistry.validate_attributes(schema, %{})
      assert {"summary", "is required"} in errors
    end

    test "accepts matching types" do
      schema = %{"properties" => %{"count" => %{"type" => "integer"}}}
      assert SchemaRegistry.validate_attributes(schema, %{"count" => 3}) == :ok
    end

    test "rejects mismatched types" do
      schema = %{"properties" => %{"count" => %{"type" => "integer"}}}
      assert {:error, errors} = SchemaRegistry.validate_attributes(schema, %{"count" => "three"})
      assert {"count", "expected type integer"} in errors
    end

    test "enforces enum constraint" do
      schema = %{
        "properties" => %{
          "priority" => %{"type" => "string", "enum" => ["low", "high"]}
        }
      }

      assert SchemaRegistry.validate_attributes(schema, %{"priority" => "low"}) == :ok
      assert {:error, _} = SchemaRegistry.validate_attributes(schema, %{"priority" => "wild"})
    end

    test "rejects additional properties when disallowed" do
      schema = %{
        "properties" => %{"a" => %{"type" => "string"}},
        "additionalProperties" => false
      }

      assert {:error, errors} =
               SchemaRegistry.validate_attributes(schema, %{"a" => "ok", "b" => 1})

      assert Enum.any?(errors, fn {key, msg} ->
               key == "b" and msg =~ "not a declared attribute"
             end)
    end

    test "accepts additional properties by default" do
      schema = %{"properties" => %{"a" => %{"type" => "string"}}}
      assert SchemaRegistry.validate_attributes(schema, %{"a" => "ok", "extra" => 1}) == :ok
    end

    test "handles atom-keyed attribute maps safely" do
      schema = %{"required" => ["a"], "properties" => %{"a" => %{"type" => "string"}}}
      assert SchemaRegistry.validate_attributes(schema, %{a: "ok"}) == :ok
    end
  end
end
