# ninox-d_data:json

JSON serialization support.

## Getting started

The serializer is build in a way, that you easily can start using it without any special attributes (UDA's):

```d
import ninox.data.json;
import std.stdio;

class MyObj {
    int i = 42;
    float f = 0.1234;
    bool b = true;
    string s = "hello\nworld";
}

void main() {
    JsonMapper m = new JsonMapper();

    MyObj obj = new MyObj();
    string s = m.serialize(obj);

    writeln(s);

    MyObj obj2 = m.deserialize!(MyObj)(s);
}
```

## Advanced usage

There is a whole range of attributes one can use to modify the behaviour of the serializer:

- `@JsonAnyGetter`: allows to serialize arbitary keys, and needs to be added to a method:
    ```d
    class MyObj {
        @JsonAnyGetter
        int[string] getAnything() {
            return [
                'hello': 42,
            ];
        }
    }
    ```
    Note: the returntype must **always** be a associative array with a string as key type.

- `@JsonAnySetter`: allows to deserialize arbitary keys; in practice this means all keys left after fields / getters have gotten their:
    ```d
    class MyObj {
        @JsonAnySetter
        void setAnything(string key, JsonParser parse) {}
    }
    ```
    Note: the setter always gets the key as a string and the `JsonParser` instance to parse the value it wants to get.

- `@JsonGetter(name: "")`: allows to use a getter function for a property:
    ```d
    class Person {
        @JsonGetter("name")
        string getName() {
            return "John Doe";
        }
    }
    ```
    Note: the method **must** have a return type other than void, and the method cannot have any parameters.

- `@JsonSetter(name: "")`: allows to use a setter function for a property:
    ```d
    class Person {
        @JsonSetter("name")
        void getName(string name) {}
    }
    ```
    Note: the method **must** have only one parameter. Returntype is ignored.

- `@JsonRawValue`: allows fields / getters to return raw JSON:
    ```d
    class MyObj {
        @JsonRawValue
        string raw = "{\"hello\":42}";

        @JsonRawValue
        @JsonGetter("raw2")
        string getRaw2() {
            return "{\"hello\":42}";
        }
    }
    ```
    Note: the serializer **does not** ensure that the raw JSON is valid in any way.

- `@JsonSerialize`: specify a class (or function) that should be used to serialize the type / value:
    ```d
    class MyClassSerializer {
        this(int i) {}
        void serializeJson(T)(JsonBuffer buff, auto ref T value) {}
    }

    void myFuncSerializer(T)(JsonBuffer buff, auto ref T value, int i) {}

    @JsonSerialize!(MyClassSerializer, 42)
    class A {}

    class B {
        @JsonSerialize!(myFuncSerializer, 42)
        string s;
    }
    ```
    Note: everything after the first template argument is optional and will be used to initialize classes/structs or given after the buffer and the value for functions.

- `@JsonDeserialize`: specify a class (or function) that should be used to deserialize the type / value:
    ```d
    class MyClassDeserializer {
        this(int i) {}
        V deserializeJson(V)(JsonParser parse) {
            // ...
        }
    }

    V myFuncDeserializer(V)(JsonParser parse, int i) {
        // ...
    }

    @JsonDeserialize!(MyClassDeserializer, 42)
    class A {}

    class B {
        @JsonDeserialize!(myFuncDeserializer, 42)
        string s;
    }
    ```
    Note: everything after the first template argument is optional and will be used to initialize classes/structs or given after the buffer and the value for functions.

- `@JsonAlias`: specifies additional aliases which are also used when deserialized:
    ```d
    class MyObj {
        @JsonAlias([ "full_name" ])
        string name;
    }
    ```
    This has the effect that the json `{"name":"John Doe"}` and `{"full_name":"John Doe"}` are deserialized into the a object where `obj.name == "John Doe"`.
    Note: in a JSON object that has *both* keys, the key that comes last will override any values set before, so if you have `{"name":"John Doe","full_name":"Juliet"}`, then the resulting value will be `Juliet`.

- `@JsonIgnore`: this allows you to simply ignore fields in a structure (will not be serialized and/or deserialized).

- `@JsonIgnoreType`: like `@JsonIgnore` but for entire types; but this on a class/struct and it will not be serialized, and also no fields that have this type.

- `@JsonProperty(name: "")`: used to 'rename' a field for serialization:
    ```d
    class MyObj {
        @JsonProperty("name")
        string full_name;
    }
    ```

- `@JsonTypeInfo` & `@JsonSubTypes`: used to be able to serialize type information into the resulting json and also loading types from it:
    ```d
    @JsonTypeInfo(
        use: JsonTypeInfo.Id.NAME,
        include: JsonTypeInfo.As.PROPERTY,
        property: "type"
    )
    @JsonSubTypes([
        mkJsonSubType!(AuthType.Basic, "basic"),
        mkJsonSubType!(AuthType.Bearer, "bearer"),
    ])
    class AuthType {
        static class Basic : AuthType {
            string user, pass;
        }
        static class Bearer : AuthType {
            string token;
        }
    }
    void main() {
        JsonMapper mapper = new JsonMapper();

        AuthType a = new AuthType.Bearer();
        (cast(AuthType.Bearer)a).token = "zzzz";
        string s = a.serialize(mapper);

        AuthType b = s.deserialize!(AuthType)(mapper);
    }
    ```
    The bearer subclass in variable `a` gets serialized to: `{"type":"bearer","token":"zzzz"}`.

    Note: there are also `JsonTypeInfo.As.WRAPPER_OBJECT` and `JsonTypeInfo.As.WRAPPER_ARRAY`. When used the above example would result in `{"name":"bearer","value":{"token":"zzzz"}}` and `["bearer",{"token":"zzzz"}]` respectively.

    Note: currently the order of properties / elements is important: the data that denotes the type needs to always come first.

    Note: currently all classes that should be deserializeable via this feature needs an default constructor; i.e. `this() {}`.

## Roadmap

- support pretty printing
- support more attributes (see `source/ninox/data/json/attributes.d`)