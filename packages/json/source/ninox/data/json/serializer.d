/*
 * Copyright (C) 2024 Mai-Lapyst
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
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */

module ninox.data.json.serializer;

import ninox.data.buffer;
import ninox.data.custom_serializer;
import ninox.data.json.attributes;

import ninox.std.callable;
import ninox.std.variant;

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
alias callCustomSerializer = mkCallCustomSerializer!(JsonBuffer, "Json");

/// Internal: calls a custom deserializer based on the @JsonDeserialize uda given
/// 
/// Params:
///   parse = the parser to read from
/// 
/// Returns: the deserialized value
alias callCustomDeserializer = mkCallCustomDeserializer!(JsonParser, "Json");

/// Exception when any dumping/serialization goes wrong
class JsonDumpException : Exception {
    @nogc @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) {
        super(msg, file, line, nextInChain);
    }

    @nogc @safe pure nothrow this(string msg, Throwable nextInChain, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line, nextInChain);
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

import ninox.data.parser;

/// A parser for JSON
class JsonParser : DeserializerParser {
protected:
    override Exception buildParseException(string msg, string file, size_t line) {
        return new JsonParseException(msg, file, line);
    }

public:
    this(size_t function(char[], size_t) source) {
        super(source);
    }
    this(size_t delegate(char[], size_t) source) {
        super(source);
    }

    /// Consumes a whole JSON string
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

import ninox.data.traits;
alias KeyFromJsonProperty = KeyFromCustomProperty!(JsonProperty);
alias KeyFromJsonPropertyOverloads = KeyFromCustomPropertyOverloads!(JsonProperty);

alias SerializeValueCode = GenericSerializeValueCode!("Json", JsonSerialize, JsonRawValue);
alias UnserializeValueCode = GenericUnserializeValueCode!("Json", JsonDeserialize, JsonRawValue, "consumeRawJson");

alias JsonRuntimeSerializer = RuntimeSerializer!(JsonBuffer, JsonParser, "Json");

/// The JSON (de-)serializer
class JsonMapper : BaseMapper!(JsonBuffer, JsonParser, "Json") {
public:

    template JsonHandler() {
        alias IgnoreTypeAttr = JsonIgnoreType;
        alias SerializeAttr = JsonSerialize;
        alias SubTypesAttr = JsonSubTypes;
        alias TypeInfoAttr = JsonTypeInfo;

        alias Buffer = JsonBuffer;
        enum Format = "Json";

        enum PutTypeInfo(alias arg) = `buff.putString("` ~ arg ~ `");`;

        enum PutNullRef = `buff.putRaw("null");`;
        enum PutTuple = `
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
        `;

        enum PutObject = `
            buff.put('{');
            this.serializeInnerObject!T(buff, value);
            buff.put('}');
        `;

        template PutObjectWithTypeInfo(alias type_info_uda, string TypeInfoCode, string SubTypeCode)
        {
            static if (type_info_uda.include == JsonTypeInfo.As.WRAPPER_OBJECT) {
                enum PutObjectWithTypeInfo = `
                    buff.put('{');
                    buff.putKey("name");
                    ` ~ TypeInfoCode ~ `
                    buff.put(',');
                    buff.putKey("value");
                    buff.put('{');
                    ` ~ SubTypeCode ~ `
                    buff.put('}');
                    buff.put('}');
                `;
            }
            else static if (type_info_uda.include == JsonTypeInfo.As.WRAPPER_ARRAY) {
                enum PutObjectWithTypeInfo = `
                    buff.put('[');
                    ` ~ TypeInfoCode ~ `
                    buff.put(',');
                    buff.put('{');
                    ` ~ SubTypeCode ~ `
                    buff.put('}');
                    buff.put(']');
                `;
            }
            else static if (type_info_uda.include == JsonTypeInfo.As.PROPERTY) {
                enum PutObjectWithTypeInfo = `
                    buff.put('{');
                    buff.putKey(type_info_uda[0].property);
                    ` ~ TypeInfoCode ~ `
                    buff.put(',');
                    ` ~ SubTypeCode ~ `
                    buff.put('}');
                `;
            }
        }

        enum PutString = `buff.putString(to!string(value));`;

        enum PutArray = `
            buff.put('[');
            foreach (i, val; value) {
                if (i != 0) { buff.put(','); }
                this.serialize(buff, val);
            }
            buff.put(']');
        `;

        enum PutAssociativeArray = `
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
        `;

        enum PutEnum = `
            // TODO: make this configurable somehow...
            buff.putString(to!string(value));
        `;

        enum PutBasic = `buff.putRaw(to!string(value));`;
    }

    mixin GenericSerialize!(JsonHandler);

    private void serializeInnerObject(T)(JsonBuffer buff, auto ref T value)
    if (is(T == class) || is(T == struct)) {
        import std.traits;
        import std.meta : AliasSeq, Filter;
        import ninox.std.traits;
        import std.string : join;

        template FieldImpl(size_t i, alias Field)
        {
            static if (i > 0) {
                enum Sep = "buff.put(',');";
            } else {
                enum Sep = "";
            }
            enum Key = KeyFromJsonProperty!(T, Field.name, Field.member);
            enum Val = SerializeValueCode!(
                T, Field.member,
                "alias Elem = __traits(getMember, T, \"" ~ Field.name ~ "\");",
                "value." ~ Field.name,
                Field.name
            );
            enum FieldImpl = Sep ~ `buff.putKey("` ~ Key ~ `");` ~ Val;
        }

        enum FieldIsOfInterest(alias Field) = (
            !Field.has_UDA!JsonIgnore
            && !hasUDA!(Field.type, JsonIgnoreType)
            && Field.compiles
        );

        alias fields = Filter!(FieldIsOfInterest, GetFields!T);

        enum FieldCode = [ AliasSeq!( "", staticMapWithIndex!(FieldImpl, fields) ) ].join("\n");
        mixin(FieldCode);

        enum MemberIsGetter(alias Member) = (
            Member.compiles
            && (
                (is(Member.type == function) && (Member.has_UDA!JsonGetter || Member.has_UDA!JsonAnyGetter))
                || (isCallable!(Member.raw) && hasFunctionAttributes!(Member.raw, "@property"))
            )
        );

        alias getters = Filter!(MemberIsGetter, GetDerivedMembers!T);

        static if (fields.length > 0 && getters.length > 0) {
            buff.put(',');
        }

        template GetterImpl(size_t i, alias Member)
        {
            static if (i > 0) {
                enum Sep = "buff.put(',');";
            } else {
                enum Sep = "";
            }

            static if (is(Member.type == function)) {
                enum isGetter = Member.has_UDA!JsonGetter;
                enum isAnyGetter = Member.has_UDA!JsonAnyGetter;
                static assert (
                    !(isGetter && isAnyGetter),
                    "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ Member.name ~ "`: Cannot have both @JsonGetter and @JsonAnyGetter"
                );
                static if (isGetter) {
                    static assert(
                        is(ParameterTypeTuple!(Member.raw) == AliasSeq!()),
                        "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ Member.name ~ "`: Getter cannot have any parameters"
                    );

                    alias udas = Member.get_UDAs!JsonGetter;
                    static assert(
                        udas.length == 1,
                        "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ Member.name ~ "`: Cannot have multiple @JsonGetter"
                    );

                    alias uda = udas[0];
                    static if (is(uda == JsonGetter)) {
                        static assert(
                            0, "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ Member.name ~ "`: Need instance of @JsonGetter"
                        );
                    } else {
                        static assert(
                            uda.name != "",
                            "Error in getter `" ~ fullyQualifiedName!T ~ "." ~ Member.name ~ "`: Need name for @JsonGetter"
                        );

                        enum Val = SerializeValueCode!(
                            T, Member.raw,
                            "alias Elem = __traits(getMember, T, \"" ~ Member.name ~ "\");",
                            "value." ~ Member.name ~ "()",
                            Member.name
                        );

                        enum GetterImpl = Sep ~ "buff.putKey(\"" ~ uda.name ~ "\");" ~ Val;
                    }
                }
                else static if (isAnyGetter) {
                    alias RetT = ReturnType!(Member.raw);
                    static if (isAssociativeArray!(RetT) && isSomeString!(KeyType!RetT)) {
                        static assert(
                            is(ParameterTypeTuple!(Member.raw) == AliasSeq!()),
                            "Error in any-getter `" ~ fullyQualifiedName!T ~ "." ~ Member.name ~ "`: Any-Getter cannot have any parameters"
                        );

                        enum GetterImpl =
                            Sep
                            ~ "{"
                                ~ "auto map = value." ~ Member.name ~ "();"
                                ~ "size_t mi = 0;"
                                ~ "foreach (key, val; map) {"
                                    ~ "if (mi != 0) { buff.put(','); }"
                                    ~ "this.serialize(buff, key);"
                                    ~ "buff.put(':');"
                                    ~ "this.serialize(buff, val);"
                                    ~ "mi++;"
                                ~ "}"
                            ~ "}";
                    } else {
                        static assert(
                            0,
                            "Error in any-getter `" ~ fullyQualifiedName!T ~ "." ~ Member.name ~ "`: Wrong return type"
                        );
                    }
                }
                else {
                    static assert(0);
                }
            }
            else static if (isCallable!(Member.raw) && hasFunctionAttributes!(Member.raw, "@property")) {
                alias overloads = __traits(getOverloads, T, Member.name);
                alias getter = AliasSeq!();
                static foreach (overload; overloads) {
                    static if (!is(ReturnType!overload == void) && Parameters!overload.length == 0) {
                        getter = AliasSeq!(getter, overload);
                    }
                }

                static if (getter.length < 1) {
                    enum GetterImpl = "";
                } else {
                    enum Key = KeyFromJsonPropertyOverloads!(T, Member.name, overloads);
                    enum Val = SerializeValueCode!(
                        T, getter[0],
                        "alias Elem = GetterFromOverloads!(__traits(getOverloads, T, \"" ~ Member.name ~ "\"));",
                        "value." ~ Member.name,
                        Member.name
                    );
                    enum GetterImpl = Sep ~ "buff.putKey(\"" ~ Key ~ "\");" ~ Val;
                }
            }
            else {
                static assert(0);
            }
        }

        enum GetterCode = [ AliasSeq!( "", staticMapWithIndex!(GetterImpl, getters) ) ].join("\n");
        mixin(GetterCode);
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

    private void deserializeObjectInner(T)(auto ref T value, JsonParser parse)
    if (is(T == class) || is(T == struct)) {
        import std.traits;
        import std.meta : AliasSeq, Filter;

        char c;
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
                    } else static if (!__traits(compiles, mixin("T." ~ field_names[i]))) {
                        enum GenCasesStructFields = GenCasesStructFields!(i+1);
                    } else {

                        alias name = field_names[i];
                        enum Key = KeyFromJsonProperty!(T, name, T.tupleof[i]);

                        import std.conv : to;
                        enum Val = UnserializeValueCode!(
                            T, __traits(getMember, T, name), "alias Elem = __traits(getMember, T, \"" ~ name ~ "\");",
                            "value." ~ name ~ "=$;", name
                        );

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
                        static if (__traits(compiles, mixin("T." ~ name))) {
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

                                        enum Val = UnserializeValueCode!(
                                            T, member, "alias Elem = __traits(getMember, T, \"" ~ name ~ "\");",
                                            "value." ~ name ~ "($);", name
                                        );

                                        enum Aliases = GenAliasCases!(member);

                                        enum GenCasesStructMethods =
                                            "case \"" ~ uda.name ~ "\": " ~ Aliases ~ " {" ~ Val ~ "break; }"
                                            ~ GenCasesStructMethods!(i+1);
                                    }
                                } else {
                                    enum GenCasesStructMethods = GenCasesStructMethods!(i+1);
                                }
                            }
                            else static if (isCallable!member && hasFunctionAttributes!(member, "@property")) {
                                alias overloads = __traits(getOverloads, T, name);
                                alias setter = AliasSeq!();
                                static foreach (overload; overloads) {
                                    static if (Parameters!overload.length > 0) {
                                        setter = AliasSeq!(setter, overload);
                                    }
                                }

                                static if (setter.length < 1) {
                                    enum GenCasesStructMethods = GenCasesStructMethods!(i+1);
                                }
                                else {
                                    static assert (setter.length == 1, "Cannot have more than one setter...");
                                    enum Key = KeyFromJsonPropertyOverloads!(T, name, overloads);
                                    enum Val = UnserializeValueCode!(
                                        T, setter[0], "alias Elem = SetterFromOverloads!(__traits(getOverloads, T, \"" ~ name ~ "\"));",
                                        "value." ~ name ~ "=$;", name
                                    );
                                    enum Aliases = GenAliasCases!(setter[0]);
                                    enum GenCasesStructMethods =
                                        "case \"" ~ Key ~ "\": " ~ Aliases ~ " { " ~ Val ~ " break; }\n"
                                        ~ GenCasesStructMethods!(i+1);
                                }
                            }
                            else {
                                enum GenCasesStructMethods = GenCasesStructMethods!(i+1);
                            }
                        } else {
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
                        static if (__traits(compiles, mixin("T." ~ name))) {
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
                            debug (ninox_data) {
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
                            debug (ninox_data) {
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
            enum fullName = fullyQualifiedName!T;
            if (auto dumper = fullName in rtSerializers) {
                auto v = Variant();
                dumper.deserializeJson(parse, fullName, v);
                return v.get!T;
            }

            static if (is(T == class)) {
                if (parse.match("null")) {
                    parse.skip(4);
                    return null;
                }
            }

            alias type_info_uda = getUDAs!(T, JsonTypeInfo);
            static if (type_info_uda.length == 1) {
                static if (!is(T == class)) {
                    static assert (0, "Can only deserialize a class annotated with @JsonTypeInfo");
                }

                alias subtypes_udas = getUDAs!(T, JsonSubTypes);
                template CreateInstance(size_t i = 0) {
                    static if (i >= subtypes_udas[0].subtypes.length) {
                        enum CreateInstance = "";
                    }
                    else {
                        enum Type = "imported!\"" ~ subtypes_udas[0].subtypes[i].mod ~ "\"." ~ subtypes_udas[0].subtypes[i].type;
                        enum Name = subtypes_udas[0].subtypes[i].name;
                        pragma(msg, "Gen case for '" ~ Name ~ "' with type " ~ Type);
                        enum CreateInstance =
                            "case \"" ~ Name ~ "\": {"
                                ~ "auto value = new " ~ Type ~ "();"
                                ~ "this.deserializeObjectInner(value, parse);"
                                ~ "result = value;"
                                ~ "break;"
                            ~ "}" ~ CreateInstance!(i+1);
                    }
                }

                static if (type_info_uda[0].include == JsonTypeInfo.As.WRAPPER_OBJECT) {
                    parse.consumeChar('{');
                    parse.consumeString(); // should be "type"...
                    parse.consumeChar(':');
                    string decodedType = parse.consumeString();
                    parse.consumeChar(',');
                    parse.consumeString(); // should be "value"...
                    parse.consumeChar(':');
                    parse.consumeChar('{');

                    T result;
                    switch (decodedType) {
                        mixin(CreateInstance!());
                        default: {
                            throw new JsonParseException("Cannot deserialize: type '" ~ decodedType ~ "' not present in @JsonSubTypes!");
                        }
                    }
                    parse.consumeChar('}');
                    return result;
                }
                else static if (type_info_uda[0].include == JsonTypeInfo.As.WRAPPER_ARRAY) {
                    parse.consumeChar('[');
                    string decodedType = parse.consumeString();
                    parse.consumeChar(',');
                    parse.consumeChar('{');

                    T result;
                    switch (decodedType) {
                        mixin(CreateInstance!());
                        default: {
                            throw new JsonParseException("Cannot deserialize: type '" ~ decodedType ~ "' not present in @JsonSubTypes!");
                        }
                    }
                    parse.consumeChar(']');
                    return result;
                }
                else static if (type_info_uda[0].include == JsonTypeInfo.As.PROPERTY) {
                    parse.consumeChar('{');
                    parse.consumeString(); // should be type_info_uda[0].property ...
                    parse.consumeChar(':');
                    string decodedType = parse.consumeString();
                    parse.consumeChar(',');

                    T result;
                    switch (decodedType) {
                        mixin(CreateInstance!());
                        default: {
                            throw new JsonParseException("Cannot deserialize: type '" ~ decodedType ~ "' not present in @JsonSubTypes!");
                        }
                    }
                    return result;
                }
            }
            else static if (type_info_uda.length > 1) {
                static assert(0, "Cannot have more than one @JsonTypeInfo attribute on `" ~ fullyQualifiedName!T ~ "`");
            }
            else {
                parse.consumeChar('{');
                static if (is(T == class)) {
                    T value = new T();
                } else {
                    T value;
                }
                this.deserializeObjectInner(value, parse);
                return value;
            }
        }
        else static if (isSomeString!T) {
            return parse.consumeString();
        }
        else static if (isArray!T) {
            static if (is(T : E[], E)) {
                parse.consumeChar('[');
                static if (isStaticArray!T) {
                    E[T.sizeof / E.sizeof] r;
                    size_t i = 0;
                } else {
                    E[] r;
                }
                char c;
                while (true) {
                    c = parse.currentChar();
                    if (c == ']') { parse.nextChar(); break; }
                    else if (c == ',') { parse.nextChar(); continue; }
                    else if (c.isWhitespace) { parse.nextChar(); continue; }
                    else {
                        static if (isStaticArray!T) {
                            r[i] = this.deserialize!(E)(parse);
                            i++;
                        } else {
                            r ~= this.deserialize!(E)(parse);
                        }
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
