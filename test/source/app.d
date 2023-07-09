import std.stdio;

import std.typecons : Nullable, nullable, Tuple;
import std.variant : Variant;

import ninox.data;
import ninox.data.json;

enum State { Invalid, Open, HalfOpen, Closed }

struct Vector3I {
    int x, y, z;
}

class MySerializer {
    void serializeJson(T)(JsonBuffer buff, T obj) {
        pragma(msg, "Calling MySerializer.serializeJson with T = " ~ T.stringof);
        buff.putRaw("\"hello world\"");
    }

    T deserializeJson(T)(JsonParser parse) {
        pragma(msg, "Calling MySerializer.deserializeJson with T = " ~ T.stringof);
        parse.consumeString();
        return new T();
    }
}

void myFuncSerializer(T)(JsonBuffer buff, auto ref T obj, int i) {
    buff.putRaw("\"hello world\"");
}
V myFuncDeserializer(V)(JsonParser parse, int i) {
    writeln("Called myFuncDeserializer");
    return parse.consumeString();
}

@JsonIgnoreType
class IgnoredType {}

class Something { }

class MyObj {
    int i = 42;
    string s = "hel\"lo";
    bool b1 = true;
    bool b2 = false;
    float f = 0.12345;
    State _enum = State.Open;
    int[] nums = [11, 22, 33];
    int[string] map;
    int[int] map2;
    Vector3I v = Vector3I(11, 22, 33);
    Nullable!int n_i1 = 42.nullable;
    Nullable!int n_i2;
    Tuple!(int, "x", int, "y") point1;
    Tuple!(int, "x", int) point2;

    @JsonRawValue
    string raw = "{\"hello\":42}";

    @JsonIgnore
    string ignored1;

    IgnoredType ignored2;

    @JsonProperty("something")
    Something some = new Something();

    @JsonSerialize!(MySerializer)
    @JsonDeserialize!(MySerializer)
    Something other = new Something();

    @JsonSerialize!(myFuncSerializer, 1)
    @JsonDeserialize!(myFuncDeserializer, 1)
    string funcSerialize;

    @JsonAlias([ "aliased2", "aliased3" ])
    @JsonSetter("aliased")
    void setAliased(string v) {
        writeln("setAliased = ", v);
    }

    this() {
        this.map = [
            "hello": 42,
            "world": 96,
        ];
        this.map2 = [
            10: 20,
            20: 40,
        ];
    }

    @JsonGetter("name")
    string getName() {
        return "John Doe";
    }

    @JsonGetter("raw2")
    @JsonRawValue
    string getRaw2() {
        return "{\"hello\":42}";
    }

    @JsonAnyGetter
    int[string] getAnything() {
        int[string] ret = [
            "__anything": 42,
        ];
        return ret;
    }

    @JsonSetter("name")
    void setName(string name) {
        writeln("MyObj.setName(name = '", name, "')");
    }

    @JsonSetter("raw2")
    @JsonRawValue
    void setRaw2(string value) {
        writeln("MyObj.setRaw2(value = '", value, "')");
    }

    @JsonAnySetter
    void setAnything(string key, JsonParser parse) {
        auto rawValue = parse.consumeRawJson();
        writeln("MyObj.setAnything(key = '", key, "') rawValue: ", rawValue);
    }
}


@JsonTypeInfo(
    use: JsonTypeInfo.Id.NAME,
    include: JsonTypeInfo.As.PROPERTY,
    property: "type"
)
@JsonSubTypes([
    mkJsonSubType!(AuthType.Basic, "basic"),
    mkJsonSubType!(AuthType.Bearer, "bearer"),
])
abstract class AuthType {
    abstract void printOut();

    static class Basic : AuthType {
        this() {}

        string user, pass;
        override void printOut() {
            writeln("Basic { user: '", this.user, "', pass: '", this.pass, "' }");
        }
    }
    static class Bearer : AuthType {
        this() {}

        string token;
        override void printOut() {
            writeln("Bearer { token: '", this.token, "' }");
        }
    }
}

void main() {
    JsonMapper mapper = new JsonMapper();

    MyObj obj = new MyObj();
    obj.i = 5000;
    string res = obj.serialize(mapper);

    writeln(res);
    writeln("--------------------------------------");

    string r1 = mapper.deserialize!(string)("\"hello\"");
    writeln(r1);

    int r3 = mapper.deserialize!(int)("1024");
    writeln(r3);

    int[] r2 = mapper.deserialize!(int[])("[11, 22, 33]");
    writeln(r2);

    //MyObj obj2 = mapper.deserialize!(MyObj)(res);

    MyObj obj2 = res.deserialize!(MyObj)(mapper);
    writeln(obj2.i);

    writeln("--------------------------------------");

    {
        AuthType a = new AuthType.Bearer();
        (cast(AuthType.Bearer)a).token = "zzzz";
        string s = a.serialize(mapper);
        writeln(s);

        AuthType b = s.deserialize!(AuthType)(mapper);
        if (b is null) {
            writeln("b is null :O");
        } else {
            b.printOut();
        }
    }

}
