# Predicator Enhancement Requirements for SCXML Datamodel Support

This document outlines the requirements for enhancing Predicator to support SCXML (State Chart XML) datamodel expressions, based on the W3C SCXML specification and practical implementation needs.

## Current Predicator Usage in SC (SCXML Library) - **ENHANCED**

Predicator is currently used for:

- **Conditional expressions** in transition `cond` attributes ✅
- **SCXML In() function** for state checking ✅
- **Boolean evaluation** with secure expression parsing ✅
- **Value expressions** with any data type return ✅ (NEW)
- **Structured error handling** for better SCXML integration ✅ (NEW)

```elixir
# Enhanced usage example with structured errors
case Predicator.evaluate(compiled_cond, context, functions: scxml_functions) do
  {:ok, result} when is_boolean(result) -> result
  {:ok, result} -> result  # Now supports any value type
  {:error, %Predicator.Errors.UndefinedVariableError{}} -> false
  {:error, %Predicator.Errors.TypeMismatchError{}} -> false
  {:error, %Predicator.Errors.EvaluationError{}} -> false
  {:error, _other} -> false  # Backward compatibility
end
```

## SCXML Datamodel Requirements

### Expression Types Required

The SCXML specification defines three types of expressions:

1. **Conditional Expressions** ✅ (Currently supported)
   - Must evaluate to boolean values
   - Used in `cond` attributes on transitions
   - Example: `score > 80 && In('ready')`

2. **Value Expressions** ✅ (Enhanced `evaluate` API supports all value types)
   - Return any legal data value
   - Used in `expr` attributes for `<log>`, `<assign>`, `<data>`, etc.
   - Example: `user.name + ' (' + user.age + ' years old)'`
   - **Implementation Status**: The enhanced `evaluate/3` API now supports value expressions returning any type

3. **Location Expressions** ❌ (Need to add - requires property access implementation)
   - Specify assignable locations in the datamodel
   - Used in `location` attributes for `<assign>`
   - Example: `user.profile.settings['theme']`
   - **Blocked by**: Property access parsing (`obj.prop`, `obj['key']`) not yet implemented

### Data Types and Operations

#### Basic Types

- **String**: `"hello"`, `'world'`
- **Number**: `42`, `3.14`, `-10`
- **Boolean**: `true`, `false`
- **Null/Undefined**: `null`, `undefined`
- **Object**: `{name: "John", age: 30}`
- **Array**: `[1, 2, 3]`, `["a", "b", "c"]`

#### Required Operations

**Arithmetic**:

```
x + y    // Addition (numbers) or concatenation (strings)
x - y    // Subtraction
x * y    // Multiplication
x / y    // Division
x % y    // Modulo
```

**Comparison**:

```
x == y   // Equality (with type coercion)
x != y   // Inequality
x < y    // Less than
x > y    // Greater than
x <= y   // Less than or equal
x >= y   // Greater than or equal
```

**Logical**:

```
x && y   // Logical AND
x || y   // Logical OR
!x       // Logical NOT
```

**Property Access**:

```
obj.property        // Dot notation
obj['property']     // Bracket notation
obj[variable]       // Dynamic property access
array[0]           // Array indexing
array[index]       // Dynamic indexing
```

**Advanced Operations** (Future enhancements):

```
x ?? y              // Nullish coalescing
obj?.prop           // Safe navigation
array.length        // Array properties
string.toUpperCase() // String methods
array.filter(x > 5) // Array methods
```

### Type Coercion Rules

SCXML requires specific type coercion behavior:

1. **String + Number**:
   - Context dependent: `"5" + 3` could be `"53"` (concatenation) or `8` (addition)
   - SCXML datamodel-specific rules apply

2. **Boolean Context**:
   - `""`, `0`, `null`, `undefined`, `false` → `false`
   - All other values → `true`

3. **Number Context**:
   - Strings containing valid numbers convert to numbers
   - Invalid strings become `NaN` or trigger errors

4. **Comparison Coercion**:
   - Follow JavaScript-like coercion rules for compatibility

### Error Handling Requirements ✅ (Implemented with structured error types)

SCXML requires specific error handling:

1. **Error Types** - **IMPLEMENTED**:

   ```elixir
   # New structured error format (implemented)
   {:error, %Predicator.Errors.UndefinedVariableError{variable: "x"}}
   {:error, %Predicator.Errors.TypeMismatchError{expected: "number", got: "string", operation: "add"}}
   {:error, %Predicator.Errors.EvaluationError{message: "Division by zero"}}
   {:error, %Predicator.Errors.ParseError{message: "Unexpected token", line: 1, column: 5}}
   
   # Legacy format (still supported for backward compatibility)
   {:error, :undefined_variable, %{variable: "x"}}
   {:error, :type_mismatch, %{expected: :number, got: :string}}
   {:error, :evaluation_error, %{reason: "Division by zero"}}
   ```

2. **Error Behavior** - **IMPLEMENTED**:
   - **Conditional expressions**: Return `false` on error (implemented)
   - **Value expressions**: Structured error information available for SCXML integration
   - **Location expressions**: Must validate assignability (pending property access implementation)

3. **SCXML Error Event** - **READY FOR INTEGRATION**:
   - Generate `error.execution` internal event when expression evaluation fails
   - Include error details in event data
   - **Implementation Notes**: Structured error types provide all necessary data for event generation

## Proposed API Extensions

### Value Expression Evaluation ✅ (Implemented via enhanced `evaluate` API)

```elixir
# Enhanced evaluate function now supports all value types (not just boolean)
Predicator.evaluate(expression, context, opts \\ [])

# Examples:
{:ok, "John Doe"} = Predicator.evaluate("user.first + ' ' + user.last", context)
{:ok, 150} = Predicator.evaluate("price * quantity", context)
{:ok, true} = Predicator.evaluate("score > 80", context)  # Boolean expressions still work
{:ok, 42} = Predicator.evaluate("age", %{"age" => 42})     # Variable access returns any type

# Error examples with new structured format:
{:error, %Predicator.Errors.UndefinedVariableError{variable: "missing"}} = 
  Predicator.evaluate("missing + 1", %{})
```

### Location Expression Evaluation

```elixir
# New function for location expressions (assignment targets)
Predicator.evaluate_location(location_expr, context, opts \\ [])

# Returns path information for assignment
{:ok, ["user", "profile", "settings", "theme"]} = 
  Predicator.evaluate_location("user.profile.settings['theme']", context)

{:ok, ["items", 0, "price"]} = 
  Predicator.evaluate_location("items[index].price", %{index: 0})
```

### Enhanced Context Support

```elixir
# Support for nested object context
context = %{
  "user" => %{
    "name" => "John Doe", 
    "age" => 30,
    "profile" => %{
      "settings" => %{"theme" => "dark"}
    }
  },
  "items" => [
    %{"name" => "Widget", "price" => 10.50},
    %{"name" => "Gadget", "price" => 25.00}
  ],
  "_event" => %{
    "name" => "user.click",
    "data" => %{"button" => "submit"}
  }
}
```

### Compilation Enhancements

```elixir
# Enhanced compilation with expression type detection
{:ok, compiled} = Predicator.compile("user.name", type: :value)
{:ok, compiled} = Predicator.compile("user.settings[key]", type: :location)
{:ok, compiled} = Predicator.compile("score > 80", type: :condition)

# Or auto-detect based on usage context
{:ok, compiled} = Predicator.compile("user.name + ' Smith'")
```

## Integration Points with SC.DataModel

The enhanced Predicator would integrate with SC's datamodel system:

```elixir
# SC.DataModel manages state, Predicator handles expressions
defmodule SC.DataModel do
  def evaluate_expression(expr, datamodel, type \\ :value) do
    context = get_evaluation_context(datamodel)
    
    case type do
      :value -> Predicator.evaluate_value(expr, context)
      :location -> Predicator.evaluate_location(expr, context)
      :condition -> Predicator.evaluate(expr, context)
    end
  end
  
  def assign_value(location_path, value, datamodel) do
    # Use location_path from Predicator.evaluate_location/2
    # to perform actual assignment in datamodel state
  end
end
```

## SCXML Examples Requiring Enhanced Predicator

### Data Elements

```xml
<datamodel>
  <data id="user" expr="{name: 'John', age: 30}"/>
  <data id="items" expr="[1, 2, 3]"/>
  <data id="counter" expr="0"/>
</datamodel>
```

### Assignment Actions

```xml
<assign location="user.name" expr="'John ' + surname"/>
<assign location="items[0]" expr="user.age * 2"/>
<assign location="user.profile.settings['theme']" expr="'dark'"/>
```

### Log Actions with Complex Expressions

```xml
<log label="Debug" expr="'User: ' + user.name + ', Items: ' + items.length"/>
<log expr="'Processing item ' + currentIndex + ' of ' + items.length"/>
```

### Conditional Transitions with Datamodel Access

```xml
<transition event="submit" cond="user.age >= 18 && form.isValid" target="process"/>
<transition event="update" cond="items.filter(x => x.active).length > 0" target="hasActive"/>
```

## Implementation Priority - **UPDATED STATUS**

1. **Phase 1**: Basic value expressions - **PARTIALLY COMPLETE**
   - ❌ Object property access (`obj.prop`, `obj['prop']`) - **NEXT PRIORITY**
   - ❌ Array indexing (`arr[0]`, `arr[index]`) - **NEXT PRIORITY**  
   - ✅ Basic arithmetic and string operations - **IMPLEMENTED**
   - ✅ Enhanced error handling - **IMPLEMENTED** (structured error types)
   - ✅ Value expression API - **IMPLEMENTED** (via enhanced `evaluate`)

2. **Phase 2**: Location expressions
   - Parse assignment targets into path structures
   - Validate assignability (no assignments to literals/computations)
   - Support for nested object and array assignments

3. **Phase 3**: Advanced operations
   - Method calls (`string.toUpperCase()`, `array.length`)
   - Array methods (`filter`, `map`, `find`)
   - Safe navigation (`obj?.prop`)
   - Nullish coalescing (`x ?? y`)

4. **Phase 4**: Performance and optimization
   - Expression compilation optimizations
   - Context caching strategies
   - Memory-efficient evaluation

## Testing Requirements - **PARTIALLY IMPLEMENTED**

Enhanced Predicator should handle these test cases:

```elixir
# Basic operations (✅ IMPLEMENTED with enhanced evaluate API)
assert {:ok, "John Doe"} = Predicator.evaluate("first + ' ' + last", %{"first" => "John", "last" => "Doe"})
assert {:ok, 30} = Predicator.evaluate("age * 2", %{"age" => 15})

# Object access (❌ PENDING - requires property access implementation)
# assert {:ok, "John"} = Predicator.evaluate("user.name", %{"user" => %{"name" => "John"}})
# assert {:ok, "dark"} = Predicator.evaluate("user.settings['theme']", context)

# Array access (❌ PENDING - requires bracket notation implementation)
# assert {:ok, 10} = Predicator.evaluate("items[0].price", %{"items" => [%{"price" => 10}]})

# Location expressions (❌ PENDING - requires location API)
# assert {:ok, ["user", "name"]} = Predicator.evaluate_location("user.name", context)
# assert {:ok, ["items", 0, "price"]} = Predicator.evaluate_location("items[0].price", context)

# Error handling (✅ IMPLEMENTED with structured errors)
assert {:error, %Predicator.Errors.UndefinedVariableError{variable: "nonexistent"}} = 
  Predicator.evaluate("nonexistent", %{})
assert {:error, %Predicator.Errors.TypeMismatchError{operation: "divide"}} = 
  Predicator.evaluate("'string' / 2", %{})
```

## Compatibility Considerations

- **Backward compatibility**: All existing Predicator APIs should continue working
- **Performance**: Enhanced features shouldn't impact existing boolean evaluation performance
- **Security**: Maintain existing security guarantees for expression evaluation
- **Dependencies**: Minimize new dependencies, leverage existing Elixir/OTP features

## Future Enhancements

- **Custom functions**: Allow registration of domain-specific functions
- **Async operations**: Support for async expression evaluation
- **Streaming**: Large array/object processing with streaming
- **Debugging**: Expression evaluation debugging and tracing tools

---

This document provides the foundation for enhancing Predicator to support SCXML datamodel requirements while maintaining its core strengths in secure, performant expression evaluation.
