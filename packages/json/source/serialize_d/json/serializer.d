/*
 * Copyright (C) 2023 Mai-Lapyst
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/** 
 * Module for the core JSON (de-)serializer
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module serialize_d.json.serializer;

import serialize_d.buffer;
import serialize_d.json.attributes;

import ministd.callable;

/// Specialization of the base SerializerBuffer to handle JSON
/// 
/// Sets the escape function to `backslashEscape`,
/// and comes with some functions for quick building of JSON in any custom serializer.
class JsonBuffer : SerializerBuffer!(backslashEscape) {
private:
    JsonMapper serializer;

public:
    this(void function(const(char)[]) sink, JsonMapper serializer) {
        super(sink);
        this.serializer = serializer;
    }
    this(void delegate(const(char)[]) sink, JsonMapper serializer) {
        super(sink);
        this.serializer = serializer;
    }

    /// Starts a structure/object
    void beginStructure() { this.put('{'); }
    /// Ends a structure/object
    void endStructure() { this.put('}'); }

    /// Starts a array
    void beginArray() { this.put('['); }
    /// Ends a array
    void endArray() { this.put(']'); }

    /// Puts a JSON string
    /// 
    /// Params:
    ///   s = the string to use as content; will be escaped
    void putString(string s) {
        this.put('\"');
        this.put(s);
        this.put('\"');
    }
    /// Puts a key for an object (JSON string + colon)
    /// 
    /// Params:
    ///   s = the string to use as value for the key; will be escaped
    void putKey(string s) {
        this.put('\"');
        this.put(s);
        this.put('\"');
        this.put(':');
    }

    /// Serializes any value by utilizing the serializer this buffer comes from/with.
    /// 
    /// Params:
    ///   value = the value to serialize
    void serialize(T)(auto ref T value) {
        this.serializer.serialize(this, value);
    }
}

/// Internal: calls a custom serializer based on the @JsonSerialize uda given
/// 
/// Params:
///   buff = the buffer to write to
///   value = the value to serialize
private void callCustomSerializer(alias uda, V)(JsonBuffer buff, auto ref V value) {
    import std.traits;

    alias SerializerTy = TemplateArgsOf!(uda)[0];
    alias Args = TemplateArgsOf!(uda)[1 .. $];

    static if (is(SerializerTy == struct)) {
        enum Serializer = SerializerTy(Args);
        Serializer.serializeJson(buff, value);
    }
    else static if (is(SerializerTy == class)) {
        auto Serializer = new SerializerTy(Args);
        Serializer.serializeJson(buff, value);
    }
    else static if (isCallable!SerializerTy) {
        SerializerTy(buff, value, Args);
    }
    else {
        // last resort: just guess its a generic function...
        SerializerTy!(V)(buff, value, Args);
    }
}

/// Internal: calls a custom deserializer based on the @JsonDeserialize uda given
/// 
/// Params:
///   parse = the parser to read from
/// 
/// Returns: the deserialized value
private V callCustomDeserializer(alias uda, V)(JsonParser parse) {
    import std.traits;

    alias DeserializerTy = TemplateArgsOf!(uda)[0];
    alias Args = TemplateArgsOf!(uda)[1 .. $];

    static if (is(DeserializerTy == struct)) {
        enum Deserializer = DeserializerTy(Args);
        return Deserializer.deserializeJson!(V)(parse);
    }
    else static if (is(DeserializerTy == class)) {
        auto Deserializer = new DeserializerTy(Args);
        return Deserializer.deserializeJson!(V)(parse);
    }
    else static if (isCallable!DeserializerTy) {
        alias RetT = ReturnType!DeserializerTy;
        static assert(
            is(RetT == V),
            "Error: functional deserializer `" ~ fullyQualifiedName!DeserializerTy ~ "` has a returntype of `" ~ RetT.stringof ~ "` but needed `" ~ V.stringof ~ "`"
        );
        return DeserializerTy(parse, Args);
    }
    else {
        // last resort: just guess its a generic function...
        return DeserializerTy!(V)(parse, Args);
    }
}

/// Exception when any parsing/deserialization goes wrong
class JsonParseException : Exception {
    @nogc @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) {
        super(msg, file, line, nextInChain);
    }

    @nogc @safe pure nothrow this(string msg, Throwable nextInChain, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line, nextInChain);
    }
}

/// A parser for JSON
class JsonParser {
private:
    Callable!(size_t, char[], size_t) source;
    size_t len, pos;
    char[4069 * 4] data = void;

public:
    this(size_t function(char[], size_t) source) {
        this.source = source;
    }
    this(size_t delegate(char[], size_t) source) {
        this.source = source;
    }

    /// Fills up the internal buffer
    void fill() {
        this.len = this.source(this.data, 4069 * 4);
        if (this.len < 1) {
            throw new JsonParseException("End of file reached");
        }
        this.pos = 0;
    }
    /// Checks if filling is needed and fills the buffer (only when the buffer is completly empty!)
    void fillIfNeeded() {
        if (this.pos >= this.len) {
            this.fill();
        }
    }
    /// Checks if the internal buffer is at the end
    /// 
    /// Returns: true if the internal buffer is at the end; false otherwise
    bool isAtEnd() {
        return this.pos >= this.len;
    }

    /// Skips a specified amount of chars; alters the position
    /// 
    /// Params:
    ///   i = the amount of characters to skip
    void skip(size_t i) {
        this.pos += i;
        this.fillIfNeeded();
    }
    /// Skips all whitespaces
    void skipWhitespace() {
        char c;
        while (true) {
            c = this.currentChar();
            if (c.isWhitespace) {
                this.pos++;
            } else {
                return;
            }
        }
    }

    /// Consumes a character; alters the position
    /// 
    /// Params:
    ///   c = the caracter to consume
    void consumeChar(char c) {
        this.fillIfNeeded();
        if (this.data[this.pos] == c) {
            this.pos++;
            return;
        } else {
            throw new JsonParseException("require '" ~ c ~ "'");
        }
    }
    /// Consumes a fixed string; alters the position
    /// 
    /// Note: Fills the internal buffer if needed via `fillIfNeeded()`.
    /// Note: Cannot consume accross boundries of the internal buffer and new data of the source.
    /// 
    /// Params:
    ///   s = the string to consume
    void consume(string s) {
        this.fillIfNeeded();
        size_t bak_pos = this.pos;
        foreach (c; s) {
            if (this.data[this.pos] != c) {
                this.pos = bak_pos;
                throw new JsonParseException("require '" ~ s ~ "'");
            }
            this.pos++;
        }
    }

    /// Matches a fixed string; position is NOT altered
    /// 
    /// Note: Fills the internal buffer if needed via `fillIfNeeded()`.
    /// Note: Cannot match accross boundries of the internal buffer and new data of the source.
    /// 
    /// Params:
    ///   s = the string to match
    /// 
    /// Retruns: true if the string was matched; false otherwise
    bool match(string s) {
        this.fillIfNeeded();
        size_t bak_pos = this.pos;
        foreach (c; s) {
            if (this.data[this.pos] != c) {
                this.pos = bak_pos;
                return false;
            }
            this.pos++;
        }
        return true;
    }

    /// Gets the current char in the buffer; position is NOT altered
    /// 
    /// Note: Fills the internal buffer if needed via `fillIfNeeded()`.
    /// 
    /// Returns: the char at the current position in the internal buffer
    char currentChar() {
        this.fillIfNeeded();
        return this.data[this.pos];
    }

    /// Gets the current char in the buffer and increases the position
    /// 
    /// Fills the internal buffer if needed via `fillIfNeeded()`.
    /// 
    /// Returns: the char at the current position in the internal buffer
    char nextChar() {
        this.fillIfNeeded();
        return this.data[this.pos++];
    }

    /// Consumes a whole JSON string
    /// 
    /// Note: Cannot consume accross boundries of the internal buffer and new data of the source.
    /// 
    /// Returns: the content of the JSON string; escape characters are resolved
    string consumeString() {
        this.consumeChar('"');

        string r;
        char c;
        while (true) {
            c = this.nextChar();
            if (c == '"') {
                break;
            } else if (c == '\\') {
                c = this.nextChar();
                switch (c) {
                    case '\"':
                    case '\\':
                    {
                        r ~= c;
                        continue;
                    }

                    case 'b': { r ~= '\b'; continue; }
                    case 'f': { r ~= '\f'; continue; }
                    case 'n': { r ~= '\n'; continue; }
                    case 'r': { r ~= '\r'; continue; }
                    case 't': { r ~= '\t'; continue; }

                    case 'u': {
                        this.consumeChar('0');
                        this.consumeChar('0');

                        ubyte[2] spl;

                        c = this.nextChar();
                        spl[0] = cast(ubyte)(c < 'A' ? c - '0' : c - 'A' + 10);

                        c = this.nextChar();
                        spl[1] = cast(ubyte)(c < 'A' ? c - '0' : c - 'A' + 10);

                        c = cast(char)((spl[0] << 4) | spl[1]);
                        r ~= c;
                        continue;
                    }

                    default:
                        throw new JsonParseException("Invalid escape sequence: \\" ~ c);
                }
            } else {
                r ~= c;
            }
        }

        return r;
    }

    /// Consumes a JSON boolean
    /// 
    /// Note: Cannot consume accross boundries of the internal buffer and new data of the source.
    /// 
    /// Returns: true if a "true" was consumed, false if a "false" was consumed.
    /// 
    /// Throws: JsonParseException if neither a "true" nor a "false" can be consumed.
    bool consumeBoolean() {
        char c = this.currentChar();
        if (c == 't') {
            this.consume("true");
            return true;
        } else if (c == 'f') {
            this.consume("false");
            return false;
        } else {
            throw new JsonParseException("require either 'true' or 'false'");
        }
    }

    /// Consumes an JSON integer
    /// 
    /// Note: Cannot consume accross boundries of the internal buffer and new data of the source.
    /// 
    /// Returns: a int of type T
    T consumeInt(T)() {
        string s;
        char c;
        while (true) {
            c = this.currentChar();
            if (c >= '0' && c <= '9') {
                this.pos++;
                s ~= c;
                if (this.isAtEnd()) { break; }
                continue;
            } else {
                break;
            }
        }

        import std.conv : to;
        return to!T(s);
    }

    /// Internal: helper to determine if a character is numeric or not
    private static bool isNumeric(char c) {
        return c >= '0' && c <= '9';
    }

    /// Consumes a JSON number raw
    /// 
    /// Note: Cannot consume accross boundries of the internal buffer and new data of the source.
    /// 
    /// Returns: the raw number string of a JSON number
    string consumeNumberRaw() {
        char c = this.nextChar();
        if (c != '-' && !isNumeric(c)) {
            throw new JsonParseException("Number must start with either a dash or a digit");
        }

        string s;
        s ~= c;

        // number
        while (true) {
            c = this.currentChar();
            if (isNumeric(c)) {
                this.pos++;
                s ~= c;
                continue;
            }
            break;
        }

        if (c != '.') { return s; }

        this.pos++;
        s ~= c;

        // fraction
        while (true) {
            c = this.currentChar();
            if (isNumeric(c)) {
                this.pos++;
                s ~= c;
                continue;
            }
            break;
        }

        if (c != 'e' && c != 'E') { return s; }

        this.pos++;
        s ~= c;

        // exponent
        c = this.currentChar();
        if (c != '+' && c != '-' && !isNumeric(c)) {
            throw new JsonParseException("Need either +/- or a digit for exponent");
        }
        while (true) {
            c = this.currentChar();
            if (isNumeric(c)) {
                this.pos++;
                s ~= c;
                continue;
            }
            break;
        }

        return s;
    }

    /// Consumes raw JSON
    /// 
    /// Note: Cannot consume accross boundries of the internal buffer and new data of the source.
    /// 
    /// Returns: a string with raw JSON
    string consumeRawJson() {
        char c = this.currentChar();
        if (c == '{' || c == '[') {
            // char outmost = c;
            char[] stack;

            string s = "";
            while (true) {
                c = this.nextChar();
                s ~= c;

                if (c == '{') {
                    // push to stack
                    stack ~= '}';
                }
                else if (c == '[') {
                    // push to stack
                    stack ~= ']';
                }
                else if (c == '}' || c == ']') {
                    // pop from stack!
                    if (c == stack[$-1]) {
                        stack = stack[0 .. $-1];
                    } else {
                        throw new JsonParseException("Cannot close; expected '" ~ stack[$-1] ~ "', got '" ~ c ~ "'");
                    }

                    if (stack.length <= 0) {
                        break;
                    }
                }
            }
            return s;
        }
        else {
            if ((c >= '0' && c <= '9') || c == '-') {
                return this.consumeNumberRaw();
            }
            else if (c == '"') {
                this.pos++;

                // consume string
                string s = "\"";
                while (true) {
                    c = this.nextChar();
                    s ~= c;
                    if (c == '\"') { break; }
                }
                return s;
            }
            else {
                switch (c) {
                    case 't': {
                        consume("true");
                        return "true";
                    }
                    case 'f': {
                        consume("false");
                        return "false";
                    }
                    case 'n': {
                        consume("null");
                        return "null";
                    }
                    default:
                        throw new JsonParseException("Unknown token: '" ~ c ~ "'");
                }
            }
        }
    }

}

private bool isWhitespace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/// The JSON (de-)serializer
class JsonMapper {
public:

    /// Serializes any value into a string containg JSON
    /// 
    /// Params:
    ///   value = the value to serialize
    /// 
    /// Returns: a string containing the serialized value in JSON
    string serialize(T)(auto ref T value) {
        import std.array: appender;
        import std.range.primitives: put;

        auto app = appender!(char[]);
        auto sink = (const(char)[] chars) => put(app, chars);
        auto buff = new JsonBuffer(sink, this);

        this.serialize(buff, value);

        buff.flush();

        return cast(string) app.data;
    }

    /// Serializes any value into the given buffer
    /// 
    /// Params:
    ///   buff = the buffer to serialize into
    ///   value = the value to serialize
    void serialize(T)(JsonBuffer buff, auto ref T value) {
        import std.traits;
        import std.meta : AliasSeq, Filter;
        import std.conv : to;
        import std.typecons : Nullable, Tuple;
        import std.variant : VariantN;

        static if (hasUDA!(T, JsonIgnoreType)) {
            throw new RuntimeException("Cannot serialize a value of type `" ~ fullyQualifiedName!T ~ "`: is annotated with @JsonIgnoreType");
        }
        else static if (hasUDA!(T, JsonSerialize)) {
            alias udas = getUDAs!(T, JsonSerialize);
            static assert (udas.length == 1, "Cannot serialize type `" ~ fullyQualifiedName!T ~ "`: got more than one @JsonSerialize attributes");

            static if (isInstanceOf!(JsonSerialize, udas[0])) {
                alias uda = udas[0];
            } else {
                alias uda = typeof(udas[0]);
            }

            callCustomSerializer!(uda)(buff, value);
        }
        else static if (isInstanceOf!(Nullable, T)) {
            if (value.isNull) {
                buff.putRaw("null");
            } else {
                this.serialize(buff, value.get);
            }
        }
        else static if (isInstanceOf!(Tuple, T)) {
            buff.put('{');
            static foreach (i, fieldName; value.fieldNames) {
                static if (i != 0) { buff.put(','); }
                static if (fieldName == "") {
                    buff.putKey(to!string(i));
                    this.serialize(buff, mixin("value[" ~ to!string(i) ~ "]"));
                }
                else {
                    buff.putKey(fieldName);
                    this.serialize(buff, mixin("value." ~ fieldName));
                }
            }
            buff.put('}');
        }
        else static if (is(T == class) || is(T == struct)) {
            static if (is(T == class)) {
                if (value is null) {
                    buff.putRaw("null");
                    return;
                }
            }

            buff.put('{');

            alias field_names = FieldNameTuple!T;
            alias field_types = FieldTypeTuple!T;

            template FieldImpl(size_t i = 0) {
                static if (i >= field_names.length) {
                    enum FieldImpl = "";
                } else static if (hasUDA!(T.tupleof[i], JsonIgnore)) {
                    enum FieldImpl = FieldImpl!(i+1);
                } else static if (hasUDA!(field_types[i], JsonIgnoreType)) {
                    enum FieldImpl = FieldImpl!(i+1);
                } else {
                    static if (i > 0) {
                        enum Sep = "buff.put(',');";
                    } else {
                        enum Sep = "";
                    }

                    alias name = field_names[i];

                    static if (hasUDA!(T.tupleof[i], JsonProperty)) {
                        alias udas = getUDAs!(T.tupleof[i], JsonProperty);
                        static assert(udas.length == 1, "Field `" ~ fullyQualifiedName!T ~ "." ~ name ~ "` can only have one @JsonProperty");

                        alias uda = udas[0];
                        static if (is(uda == JsonProperty)) {
                            enum Key = name;
                        } else {
                            static if (uda.name == "") {
                                enum Key = name;
                            } else {
                                enum Key = uda.name;
                            }
                        }
                    } else {
                        enum Key = name;
                    }

                    alias ty = field_types[i];
                    static if (hasUDA!(T.tupleof[i], JsonSerialize)) {
                        import std.conv : to;
                        enum Val =
                            "{ " ~
                                "alias T = imported!\"" ~ moduleName!T ~ "\"." ~ T.stringof ~ ";" ~
                                "alias udas = getUDAs!(T.tupleof[" ~ to!string(i) ~ "], JsonSerialize);" ~
                                "static assert (udas.length == 1, \"Cannot serialize member `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: got more than one @JsonSerialize attributes\");" ~
                                "callCustomSerializer!(udas)(buff, value." ~ name ~ ");" ~
                            " }";
                    } else static if (isSomeString!(ty) && hasUDA!(T.tupleof[i], JsonRawValue)) {
                        enum Val = "buff.putRaw(value." ~ name ~ ");";
                    } else {
                        enum Val = "this.serialize(buff, value." ~ name ~ ");";
                    }

                    enum FieldImpl = Sep ~ "buff.putKey(\"" ~ Key ~ "\");" ~ Val ~ FieldImpl!(i+1);
                }
            }
            mixin(FieldImpl!());

            template CountFields(size_t i = 0) {
                static if (i >= field_names.length) {
                    enum CountFields = 0;
                } else static if (hasUDA!(T.tupleof[i], JsonIgnore)) {
                    enum CountFields = CountFields!(i+1);
                } else static if (hasUDA!(field_types[i], JsonIgnoreType)) {
                    enum CountFields = CountFields!(i+1);
                } else {
                    enum CountFields = 1 + CountFields!(i+1);
                }
            }

            alias allMembers = __traits(allMembers, T);

            template CountGetter(size_t i = 0) {
                static if (i >= allMembers.length) {
                    enum CountGetter = 0;
                }
                else {
                    enum name = allMembers[i];
                    mixin ("alias member = T." ~ name ~ ";");
                    static if (is(typeof(member) == function)) {
                        static if (hasUDA!(member, JsonGetter) || hasUDA!(member, JsonAnyGetter)) {
                            enum CountGetter = 1 + CountGetter!(i+1);
                        } else {
                            enum CountGetter = CountGetter!(i+1);
                        }
                    }
                    else {
                        enum CountGetter = CountGetter!(i+1);
                    }
                }
            }

            static if (CountFields!() > 0 && CountGetter!() > 0) {
                buff.put(',');
            }

            template GetterImpl(size_t i = 0, size_t j = 0) {
                static if (i >= allMembers.length) {
                    enum GetterImpl = "";
                }
                else {
                    enum name = allMembers[i];
                    mixin ("alias member = T." ~ name ~ ";");
                    static if (is(typeof(member) == function)) {
                        enum isGetter = hasUDA!(member, JsonGetter);
                        enum isAnyGetter = hasUDA!(member, JsonAnyGetter);
                        static assert (
                            !(isGetter && isAnyGetter),
                            "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Cannot have both @JsonGetter and @JsonAnyGetter"
                        );

                        static if (j > 0) {
                            enum Sep = "buff.put(',');";
                        } else {
                            enum Sep = "";
                        }

                        static if (isGetter) {
                            static assert(
                                is(ParameterTypeTuple!member == AliasSeq!()),
                                "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Getter cannot have any parameters"
                            );

                            alias udas = getUDAs!(member, JsonGetter);
                            static assert(
                                udas.length == 1,
                                "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Cannot have multiple @JsonGetter"
                            );

                            alias uda = udas[0];
                            static if (is(uda == JsonGetter)) {
                                static assert(
                                    0, "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Need instance of @JsonGetter"
                                );
                            } else {
                                static assert(
                                    uda.name != "",
                                    "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Need name for @JsonGetter"
                                );

                                static if (hasUDA!(member, JsonRawValue)) {
                                    static assert (
                                        isSomeString!(ReturnType!member),
                                        "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Getter needs to return a string-like type when annotated with @JsonRawValue"
                                    );

                                    enum GetterImpl =
                                        Sep
                                        ~ "buff.putKey(\"" ~ uda.name ~ "\");"
                                        ~ "buff.putRaw(value." ~ name ~ "());"
                                        ~ GetterImpl!(i+1, j+1);
                                }
                                else {
                                    enum GetterImpl =
                                        Sep
                                        ~ "buff.putKey(\"" ~ uda.name ~ "\");"
                                        ~ "this.serialize(buff, value." ~ name ~ "());"
                                        ~ GetterImpl!(i+1, j+1);
                                }
                            }
                        } else static if (isAnyGetter) {
                            alias RetT = ReturnType!member;
                            static if (isAssociativeArray!(RetT) && isSomeString!(KeyType!RetT)) {
                                static assert(
                                    is(ParameterTypeTuple!member == AliasSeq!()),
                                    "Error in any-getter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Any-Getter cannot have any parameters"
                                );

                                enum GetterImpl =
                                    Sep
                                    ~ "{"
                                        ~ "auto map = value." ~ name ~ "();"
                                        ~ "size_t mi = 0;"
                                        ~ "foreach (key, val; map) {"
                                            ~ "if (mi != 0) { buff.put(','); }"
                                            ~ "this.serialize(buff, key);"
                                            ~ "buff.put(':');"
                                            ~ "this.serialize(buff, val);"
                                            ~ "mi++;"
                                        ~ "}"
                                    ~ "}"
                                    ~ GetterImpl!(i+1, j+1);
                            } else {
                                static assert(
                                    0,
                                    "Error in any-getter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Wrong return type"
                                );
                            }
                        } else {
                            enum GetterImpl = GetterImpl!(i+1, j);
                        }
                    }
                    else {
                        enum GetterImpl = GetterImpl!(i+1, j);
                    }
                }
            }
            mixin(GetterImpl!());

            buff.put('}');
        }
        else static if (isSomeString!T) {
            buff.putString(to!string(value));
        }
        else static if (isArray!T) {
            buff.put('[');
            foreach (i, val; value) {
                if (i != 0) { buff.put(','); }
                this.serialize(buff, val);
            }
            buff.put(']');
        }
        else static if (isAssociativeArray!T) {
            static if (isSomeString!(KeyType!T)) {
                buff.put('{');
                size_t i = 0;
                foreach (key, val; value) {
                    if (i != 0) { buff.put(','); }
                    this.serialize(buff, key);
                    buff.put(':');
                    this.serialize(buff, val);
                    i++;
                }
                buff.put('}');
            } else {
                buff.put('[');
                size_t i = 0;
                foreach (key, val; value) {
                    if (i != 0) { buff.put(','); }
                    buff.put('[');
                    this.serialize(buff, key);
                    buff.put(',');
                    this.serialize(buff, val);
                    buff.put(']');
                    i++;
                }
                buff.put(']');
            }
        }
        else static if (is(T == enum)) {
            // TODO: make this configurable somehow...
            buff.putString(to!string(value));
        }
        else static if (isBasicType!T) {
            // TODO: check if this is ok
            buff.putRaw(to!string(value));
        }
        else {
            static assert(0, "Cannot serialize: " ~ fullyQualifiedName!T);
        }
    }

    /// Deserializes a string into the requested type
    /// 
    /// Params:
    ///   str = the string to deserialize
    /// 
    /// Returns: the deserialized value of the requested type
    T deserialize(T)(string str) {
        size_t pos = 0;
        auto parse = new JsonParser(
            (char[] buff, size_t buffSize) {
                size_t r = str.length - pos;
                if (r > buffSize) {
                    r = buffSize;
                }
                for (auto i = 0; i < r; i++) {
                    buff[i] = str[pos++];
                }
                return r;
            }
        );
        return this.deserialize!(T)(parse);
    }

    /// Deserializes from a JsonParser into the requested type
    /// 
    /// Params:
    ///   parse = the JsonParser to read from
    /// 
    /// Returns: the deserialized value of the requested type
    T deserialize(T)(JsonParser parse) {
        import std.traits;
        import std.meta : AliasSeq, Filter;
        import std.conv : to;
        import std.typecons : Nullable, nullable, Tuple;

        static if (hasUDA!(T, JsonIgnoreType)) {
            throw new RuntimeException("Cannot deserialize type `" ~ fullyQualifiedName!T ~ "`: is annotated with @JsonIgnoreType");
        }
        else static if (hasUDA!(T, JsonDeserialize)) {
            alias udas = getUDAs!(T, JsonDeserialize);
            static assert (udas.length == 1, "Cannot deserialize type `" ~ fullyQualifiedName!T ~ "`: got more than one @JsonDeserialize attributes");

            static if (isInstanceOf!(JsonSerialize, udas[0])) {
                alias uda = udas[0];
            } else {
                alias uda = typeof(udas[0]);
            }

            return callCustomDeserializer!(uda, T)(parse);
        }
        else static if (isInstanceOf!(Nullable, T)) {
            if (parse.match("null")) {
                return T();
            } else{
                alias Ty = TemplateArgsOf!(T)[0];
                auto val = this.deserialize!(Ty)(parse);
                return val.nullable;
            }
        }
        else static if (isInstanceOf!(Tuple, T)) {
            parse.consumeChar('{');
            char c;
            T value;
            while (true) {
                c = parse.currentChar();
                if (c == '}') { parse.nextChar(); break; }
                else if (c == ',') { parse.nextChar(); continue; }
                else if (c.isWhitespace) { parse.nextChar(); continue; }
                else {
                    auto key = parse.consumeString();
                    parse.skipWhitespace();
                    parse.consumeChar(':');
                    parse.skipWhitespace();

                    alias fieldNames = T.fieldNames;
                    template GenCasesTuple(size_t i = 0) {
                        static if (i >= fieldNames.length) {
                            enum GenCasesTuple = "";
                        }
                        else {
                            import std.conv : to;
                            alias fieldName = fieldNames[i];
                            static if (fieldName == "") {
                                enum Key = to!string(i);
                                enum Setter = "value[" ~ to!string(i) ~ "]";
                            } else {
                                enum Key = fieldName;
                                enum Setter = "value." ~ fieldName;
                            }
                            enum GenCasesTuple =
                                "case \"" ~ Key ~ "\": { " ~
                                    "alias ty = typeof(" ~ Setter ~ ");" ~
                                    Setter ~ " = this.deserialize!(ty)(parse);" ~
                                    "break;" ~
                                "}" ~
                                GenCasesTuple!(i+1);
                        }
                    }

                    switch (key) {
                        mixin(GenCasesTuple!());
                        default: {
                            auto rawVal = parse.consumeRawJson();
                            debug (serialize_d) {
                                import std.stdio;
                                writeln("[JsonMapper.deserialize!" ~ fullyQualifiedName!T ~ "] found unknown key '" ~ key ~ "' with value " ~ rawVal);
                            }
                            break;
                        }
                    }
                }
            }
            return value;
        }
        else static if (is(T == class) || is(T == struct)) {
            static if (is(T == class)) {
                if (parse.match("null")) {
                    parse.skip(4);
                    return null;
                }
            }

            parse.consumeChar('{');
            char c;
            static if (is(T == class)) {
                T value = new T();
            } else {
                T value;
            }

            while (true) {
                c = parse.currentChar();
                if (c == '}') { parse.nextChar(); break; }
                else if (c == ',') { parse.nextChar(); continue; }
                else if (c.isWhitespace) { parse.nextChar(); continue; }
                else {
                    string key = parse.consumeString();
                    parse.skipWhitespace();
                    parse.consumeChar(':');
                    parse.skipWhitespace();

                    template GenAliasCases(alias sym) {
                        static if (hasUDA!(sym, JsonAlias)) {
                            alias alias_udas = getUDAs!(sym, JsonAlias);
                            template CollectAliasCases(size_t i = 0) {
                                static if (i >= alias_udas.length) {
                                    enum CollectAliasCases = "";
                                } else {
                                    alias alias_uda = alias_udas[i];
                                    template CollectAliasCasesInner(size_t i = 0) {
                                        static if (i >= alias_uda.names.length) {
                                            enum CollectAliasCasesInner = "";
                                        } else {
                                            enum CollectAliasCasesInner =
                                                "case \"" ~ alias_uda.names[i] ~ "\": "
                                                ~ CollectAliasCasesInner!(i+1);
                                        }
                                    }
                                    enum CollectAliasCases = CollectAliasCasesInner!() ~ CollectAliasCases!(i + 1);
                                }
                            }
                            enum GenAliasCases = CollectAliasCases!();
                        } else {
                            enum GenAliasCases = "";
                        }
                    }

                    alias field_names = FieldNameTuple!T;
                    alias field_types = FieldTypeTuple!T;
                    template GenCasesStructFields(size_t i = 0) {
                        static if (i >= field_names.length) {
                            enum GenCasesStructFields = "";
                        } else static if (hasUDA!(T.tupleof[i], JsonIgnore)) {
                            enum GenCasesStructFields = GenCasesStructFields!(i+1);
                        } else static if (hasUDA!(field_types[i], JsonIgnoreType)) {
                            enum GenCasesStructFields = GenCasesStructFields!(i+1);
                        } else {

                            alias name = field_names[i];
                            static if (hasUDA!(T.tupleof[i], JsonProperty)) {
                                alias udas = getUDAs!(T.tupleof[i], JsonProperty);
                                static assert(udas.length == 1, "Field `" ~ fullyQualifiedName!T ~ "." ~ name ~ "` can only have one @JsonProperty");

                                alias uda = udas[0];
                                static if (is(uda == JsonProperty)) {
                                    enum Key = name;
                                } else {
                                    static if (uda.name == "") {
                                        enum Key = name;
                                    } else {
                                        enum Key = uda.name;
                                    }
                                }
                            } else {
                                enum Key = name;
                            }

                            alias ty = field_types[i];
                            static if (hasUDA!(T.tupleof[i], JsonDeserialize)) {
                                import std.conv : to;
                                enum Val =
                                    "{ " ~
                                        "alias T = imported!\"" ~ moduleName!T ~ "\"." ~ T.stringof ~ ";" ~
                                        "alias udas = getUDAs!(T.tupleof[" ~ to!string(i) ~ "], JsonDeserialize);" ~
                                        "static assert (udas.length == 1, \"Cannot deserialize member `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: got more than one @JsonDeserialize attributes\");" ~
                                        "value." ~ name ~ " = callCustomDeserializer!(udas, typeof(T.tupleof[" ~ to!string(i) ~ "]))(parse);" ~
                                    " }";
                            } else static if (isSomeString!(ty) && hasUDA!(T.tupleof[i], JsonRawValue)) {
                                enum Val = "value." ~ name ~ " = parse.consumeRawJson();";
                            } else {
                                mixin("alias member = T." ~ name ~ ";");
                                alias memberTy = typeof(member);
                                static if (isBuiltinType!memberTy && !is(memberTy == enum)) {
                                    enum Val =
                                        "value." ~ name ~ " = this.deserialize!(" ~ fullyQualifiedName!memberTy ~ ")(parse);";
                                } else {
                                    enum Val =
                                        "import " ~ moduleName!memberTy ~ "; " ~
                                        "value." ~ name ~ " = this.deserialize!(" ~ fullyQualifiedName!memberTy ~ ")(parse);";
                                }
                            }

                            enum Aliases = GenAliasCases!(T.tupleof[i]);

                            enum GenCasesStructFields =
                                "case \"" ~ Key ~ "\": " ~ Aliases ~ " { " ~ Val ~ " break; }\n"
                                ~ GenCasesStructFields!(i+1);
                        }
                    }

                    alias allMembers = __traits(allMembers, T);
                    template GenCasesStructMethods(size_t i = 0) {
                        static if (i >= allMembers.length) {
                            enum GenCasesStructMethods = "";
                        }
                        else {
                            enum name = allMembers[i];
                            mixin ("alias member = T." ~ name ~ ";");
                            static if (is(typeof(member) == function)) {
                                enum isSetter = hasUDA!(member, JsonSetter);
                                enum isAnySetter = hasUDA!(member, JsonAnySetter);
                                static assert (
                                    !(isSetter && isAnySetter),
                                    "Error in setter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Cannot have both @JsonSetter and @JsonAnySetter"
                                );

                                static if (isSetter) {
                                    static assert(
                                        !is(ParameterTypeTuple!member == AliasSeq!()),
                                        "Error in setter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Setter must have atleast one parameter"
                                    );
                                    // TODO: check if has only one param...

                                    alias udas = getUDAs!(member, JsonSetter);
                                    static assert(
                                        udas.length == 1,
                                        "Error in setter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Cannot have multiple @JsonSetter"
                                    );

                                    alias uda = udas[0];
                                    static if (is(uda == JsonSetter)) {
                                        static assert(
                                            0, "Error in setter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Need instance of @JsonSetter"
                                        );
                                    } else {
                                        static assert(
                                            uda.name != "",
                                            "Error in setter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Need name for @JsonSetter"
                                        );

                                        static if (hasUDA!(member, JsonRawValue)) {
                                            static assert(
                                                is(ParameterTypeTuple!member == AliasSeq!( string )),
                                                "Error in setter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Need parameter of type string if annotated with @JsonRawValue"
                                            );

                                            enum Val = "parse.consumeRawJson()";
                                        }
                                        else {
                                            enum Val = "this.deserialize!(ParameterTypeTuple!member)(parse)";
                                        }

                                        enum Aliases = GenAliasCases!(member);

                                        enum GenCasesStructMethods =
                                            "case \"" ~ uda.name ~ "\": " ~ Aliases ~ " {"
                                                ~ "alias member = T." ~ name ~ ";"
                                                ~ "value." ~ name ~ "(" ~ Val ~ ");"
                                                ~ "break;"
                                            ~ "}"
                                            ~ GenCasesStructMethods!(i+1);
                                    }
                                } else {
                                    enum GenCasesStructMethods = GenCasesStructMethods!(i+1);
                                }
                            }
                            else {
                                enum GenCasesStructMethods = GenCasesStructMethods!(i+1);
                            }
                        }
                    }

                    template GenCaseDefaultStruct(size_t i = 0) {
                        static if (i >= allMembers.length) {
                            enum GenCaseDefaultStruct = "";
                        }
                        else {
                            enum name = allMembers[i];
                            mixin ("alias member = T." ~ name ~ ";");
                            static if (is(typeof(member) == function)) {
                                enum isAnySetter = hasUDA!(member, JsonAnySetter);
                                static if (isAnySetter) {
                                    enum Rest = GenCaseDefaultStruct!(i+1);
                                    static if (Rest != "") {
                                        static assert(0, "Cannot have multiple @JsonAnySetter in one class/struct");
                                    }

                                    alias ParamT = ParameterTypeTuple!member;
                                    static if (ParamT.length == 1 && isAssociativeArray!(ParamT) && isSomeString!(KeyType!ParamT)) {
                                        static assert(
                                            0,
                                            "Error in any-setter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Associative array as param is NIY"
                                        );
                                    } else static if (ParamT.length == 2 && is(ParamT == AliasSeq!( string, JsonParser ))) {
                                        enum GenCaseDefaultStruct =
                                            "default: {" ~
                                                "value." ~ name ~ "(key, parse);" ~
                                                "break;" ~
                                            "}";
                                    } else {
                                        static assert(
                                            0,
                                            "Error in any-setter `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: Wrong parameter type"
                                        );
                                    }
                                } else {
                                    enum GenCaseDefaultStruct = GenCaseDefaultStruct!(i+1);
                                }
                            }
                            else {
                                enum GenCaseDefaultStruct = GenCaseDefaultStruct!(i+1);
                            }
                        }
                    }
                    enum __code = GenCaseDefaultStruct!();
                    switch (key) {
                        mixin(GenCasesStructFields!());
                        mixin(GenCasesStructMethods!());
                        static if (__code == "") {
                            default: {
                                auto rawVal = parse.consumeRawJson();
                                debug (serialize_d) {
                                    import std.stdio;
                                    writeln("[JsonMapper.deserialize!" ~ fullyQualifiedName!T ~ "] found unknown key '" ~ key ~ "' with value " ~ rawVal);
                                }
                                break;
                            }
                        } else {
                            mixin(__code);
                        }
                    }
                }
            }
            return value;
        }
        else static if (isSomeString!T) {
            return parse.consumeString();
        }
        else static if (isArray!T) {
            static if (is(T : E[], E)) {
                parse.consumeChar('[');
                E[] r;
                char c;
                while (true) {
                    c = parse.currentChar();
                    if (c == ']') { parse.nextChar(); break; }
                    else if (c == ',') { parse.nextChar(); continue; }
                    else if (c.isWhitespace) { parse.nextChar(); continue; }
                    else {
                        r ~= this.deserialize!(E)(parse);
                    }
                }
                return r;
            } else {
                static assert(0, "Unknown element type of array!");
            }
        }
        else static if (isAssociativeArray!T) {
            static if (isSomeString!(KeyType!T)) {
                parse.consumeChar('{');
                T r;
                char c;
                while (true) {
                    c = parse.currentChar();
                    if (c == '}') { parse.nextChar(); break; }
                    else if (c == ',') { parse.nextChar(); continue; }
                    else if (c.isWhitespace) { parse.nextChar(); continue; }
                    else {
                        string key = parse.consumeString();
                        parse.consumeChar(':');
                        r[key] = this.deserialize!(ValueType!T)(parse);
                    }
                }
                return r;
            } else {
                parse.consumeChar('[');
                T r;
                char c;
                while (true) {
                    c = parse.currentChar();
                    if (c == ']') { parse.nextChar(); break; }
                    else if (c == ',') { parse.nextChar(); continue; }
                    else if (c.isWhitespace) { parse.nextChar(); continue; }
                    else {
                        parse.consumeChar('[');
                        auto key = this.deserialize!(KeyType!T)(parse);
                        parse.consumeChar(',');
                        r[key] = this.deserialize!(ValueType!T)(parse);
                        parse.consumeChar(']');
                    }
                }
                return r;
            }
        }
        else static if (is(T == enum)) {
            auto val = parse.consumeString();

            alias members = EnumMembers!T;
            template GenCasesEnum(size_t i = 0) {
                static if (i >= members.length) {
                    enum GenCasesEnum = "";
                }
                else {
                    enum GenCasesEnum =
                        "case \"" ~ members[i].stringof ~ "\":"
                            ~ "return imported!\"" ~ moduleName!T ~ "\"." ~ T.stringof ~ "." ~ members[i].stringof ~ ";"
                        ~ GenCasesEnum!(i+1);
                }
            }
            switch (val) {
                mixin(GenCasesEnum!());
                default:
                    throw new JsonParseException("Cannot deserialize value '" ~ val ~ "' into a enum member of `" ~ fullyQualifiedName!T ~ "`");
            }
        }
        else static if (isBasicType!T) {
            static if (is(T == bool)) {
                return parse.consumeBoolean();
            }
            else static if (isFloatingPoint!T) {
                import std.conv : to;
                return to!T( parse.consumeNumberRaw() );
            }
            else static if (isNumeric!T) {
                return parse.consumeInt!(T)();
            }
            else {
                static assert(0, "Cannot deserialize basic type: " ~ T.stringof);
            }
        }
        else {
            static assert(0, "Cannot deserialize: " ~ fullyQualifiedName!T);
        }
    }

}