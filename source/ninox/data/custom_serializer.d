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
 * Module for a basic custom (de-)serializers
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */

module ninox.data.custom_serializer;

import ninox.std.callable;
import ninox.std.traits : RefT;
import ninox.std.variant;

package (ninox.data):

template mkCallCustomSerializer(Buffer, string Format) {
    void mkCallCustomSerializer(alias uda, V)(Buffer buff, auto ref V value) {
        import std.traits;

        alias SerializerTy = TemplateArgsOf!(uda)[0];
        alias Args = TemplateArgsOf!(uda)[1 .. $];

        static if (is(SerializerTy == struct)) {
            enum Serializer = SerializerTy(Args);
            mixin("Serializer.serialize" ~ Format ~ "(buff, value);");
        }
        else static if (is(SerializerTy == class)) {
            auto Serializer = new SerializerTy(Args);
            mixin("Serializer.serialize" ~ Format ~ "(buff, value);");
        }
        else static if (isCallable!SerializerTy) {
            SerializerTy(buff, value, Args);
        }
        else {
            // last resort: just guess its a generic function...
            SerializerTy!(V)(buff, value, Args);
        }
    }
}

template mkCallCustomDeserializer(Parser, string Format) {
    V mkCallCustomDeserializer(alias uda, V)(Parser parse) {
        import std.traits;

        alias DeserializerTy = TemplateArgsOf!(uda)[0];
        alias Args = TemplateArgsOf!(uda)[1 .. $];

        static if (is(DeserializerTy == struct)) {
            enum Deserializer = DeserializerTy(Args);
            mixin("return Deserializer.deserialize" ~ Format ~ "!(V)(parse);");
        }
        else static if (is(DeserializerTy == class)) {
            auto Deserializer = new DeserializerTy(Args);
            mixin("return Deserializer.deserialize" ~ Format ~ "!(V)(parse);");
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
}

interface RuntimeSerializer(Buffer, Parser, string Format) {
    mixin("void serialize" ~ Format ~ "(Buffer buff, string typeName, ref Variant obj);");
    mixin("void deserialize" ~ Format ~ "(Parser parse, string typeName, ref Variant obj);");
}

class FunctionalRuntimeSerializer(Buffer, Parser, string Format)
    : RuntimeSerializer!(Buffer, Parser, Format)
{
    alias SerializeTy = Callable!(void, Buffer, string, RefT!Variant);
    alias DeserializeTy = Callable!(void, Parser, string, RefT!Variant);

    this(
        SerializeTy serialize,
        DeserializeTy deserialize,
    ) {
        this._serialize = serialize;
        this._deserialize = deserialize;
    }

    mixin(`void serialize` ~ Format ~ `(Buffer buff, string typeName, ref Variant obj) {
        this._serialize(buff, typeName, obj);
    }`);
    mixin(`void deserialize` ~ Format ~ `(Parser parse, string typeName, ref Variant obj) {
        this._deserialize(parse, typeName, obj);
    }`);

private:
    SerializeTy _serialize;
    DeserializeTy _deserialize;
}

class BaseMapper(Buffer, Parser, string Format) {
public:
    alias RtSerializer = RuntimeSerializer!(Buffer, Parser, Format);
    alias FunctionalRtSerializer = FunctionalRuntimeSerializer!(Buffer, Parser, Format);

protected:
    RtSerializer[string] rtSerializers;

public:

    /** 
     * Adds a new runtime serializer to the mapper to be used for (de-)serialization of `T`.
     * 
     * Params:
     *   serializer = The runtime serializer to use.
     */
    pragma(inline)
    void withSerializer(T)(RtSerializer serializer)
        if (is(T == struct) || is(T == class))
    {
        import std.traits;
        rtSerializers[fullyQualifiedName!T] = serializer;
    }

    static immutable TypeSerialize = [
        "fn": "void function(Buffer, string, ref Variant)",
        "dg": "void delegate(Buffer, string, ref Variant)",
        "cb": "FunctionalRtSerializer.SerializeTy",
    ];
    static immutable TypeDeserialize = [
        "fn": "void function(Parser, string, ref Variant)",
        "dg": "void delegate(Parser, string, ref Variant)",
        "cb": "FunctionalRtSerializer.DeserializeTy",
    ];
    static foreach (tyS; ["fn", "dg", "cb"]) {
        static foreach (tyD; ["fn", "dg", "cb"]) {
            void withSerializer(T)(
                mixin(TypeSerialize[tyS]) serialize,
                mixin(TypeDeserialize[tyD]) deserialize
            ) {
                static if (tyS == "cb") { enum ExprSerialize = "serialize"; }
                else { enum ExprSerialize = "FunctionalRtSerializer.SerializeTy(serialize)"; }

                static if (tyD == "cb") { enum ExprDeserialize = "deserialize"; }
                else { enum ExprDeserialize = "FunctionalRtSerializer.DeserializeTy(deserialize)"; }

                this.withSerializer!(T)(
                    new FunctionalRtSerializer(mixin(ExprSerialize), mixin(ExprDeserialize))
                );
            }
        }
    }

    /** 
     * Checks if there is an runtime serializer present for `T`.
     * 
     * Returns: `true` if there is a serializer present; `false` otherwise.
     */
    bool hasSerializer(T)() {
        return (fullyQualifiedName!T in rtSerializers) !is null;
    }

}

template SerializeTypeInfo(alias T, alias TypeInfoAttr, alias PutTypeInfo, alias uda, subtypes_udas...)
{
    import std.traits;
    static if (uda.use == TypeInfoAttr.Id.CLASS) {
        enum SerializeTypeInfo = PutTypeInfo!(fullyQualifiedName!T);
    }
    else static if (uda.use == TypeInfoAttr.Id.NAME) {
        static if (subtypes_udas.length == 0) {
            static assert(0, "Need @" ~ __traits(identifier, TypeInfoAttr) ~ " for `" ~ fullyQualifiedName!T ~ "`");
        }
        else static if (subtypes_udas.length > 1) {
            static assert(0, "To many @" ~ __traits(identifier, TypeInfoAttr) ~ " for `" ~ fullyQualifiedName!T ~ "`");
        }
        else {
            template GenSubTypeSwitching(size_t i = 0) {
                static if (i >= subtypes_udas[0].subtypes.length) {
                    enum GenSubTypeSwitching = "";
                }
                else {
                    enum Rest = GenSubTypeSwitching!(i+1);
                    enum Type = "imported!\"" ~ subtypes_udas[0].subtypes[i].mod ~ "\"." ~ subtypes_udas[0].subtypes[i].type;
                    enum Code = "if (cast(" ~ Type ~ ") value) { " ~ PutTypeInfo!(subtypes_udas[0].subtypes[i].name) ~ " }";
                    static if (Rest == "") {
                        enum GenSubTypeSwitching = Code;
                    } else {
                        enum GenSubTypeSwitching = Code ~ " else " ~ Rest;
                    }
                }
            }

            enum SerializeTypeInfo =
                GenSubTypeSwitching!()
                ~ "else { assert(0, \"Could not determine logical name / subtype of `" ~ fullyQualifiedName!T ~ "`\"); }";
        }
    }
}

template GenericSerialize(alias Handler)
{
    string serialize(T)(auto ref T value) {
        import std.array: appender;
        import std.range.primitives: put;

        auto app = appender!(char[]);
        auto sink = (const(char)[] chars) => put(app, chars);
        auto buff = new Handler!().Buffer(sink, this);

        this.serialize(buff, value);

        buff.flush();

        return cast(string) app.data;
    }

    void serialize(T)(Handler!().Buffer buff, auto ref T value) {
        import std.traits;
        import std.meta : AliasSeq, Filter;
        import std.conv : to;
        import std.typecons : Nullable, Tuple;

        static if (hasUDA!(T, Handler!().IgnoreTypeAttr)) {
            throw new RuntimeException("Cannot serialize a value of type `" ~ fullyQualifiedName!T ~ "`: is annotated with @" ~ __traits(identifier, Handler!().IgnoreTypeAttr));
        }
        else static if (hasUDA!(T, Handler!().SerializeAttr)) {
            alias udas = getUDAs!(T, Handler!().SerializeAttr);
            static assert (udas.length == 1, "Cannot serialize type `" ~ fullyQualifiedName!T ~ "`: got more than one @" ~ __traits(identifier, Handler!().SerializeAttr) ~ " attributes");

            static if (isInstanceOf!(Handler!().SerializeAttr, udas[0])) {
                alias uda = udas[0];
            } else {
                alias uda = typeof(udas[0]);
            }

            callCustomSerializer!(uda)(buff, value);
        }
        else static if (isInstanceOf!(Nullable, T)) {
            if (value.isNull) {
                mixin(Handler!().PutNullRef);
            } else {
                this.serialize(buff, value.get);
            }
        }
        else static if (isInstanceOf!(Tuple, T)) {
            mixin(Handler!().PutTuple);
        }
        else static if (is(T == class) || is(T == struct)) {
            enum fullName = fullyQualifiedName!T;
            if (auto dumper = fullName in rtSerializers) {
                auto v = Variant(value);
                mixin("dumper.serialize" ~ Handler!().Format ~ "(buff, fullName, v);");
                return;
            }

            static if (is(T == class)) {
                if (value is null) {
                    mixin(Handler!().PutNullRef);
                    return;
                }
            }

            alias subtypes_udas = getUDAs!(T, Handler!().SubTypesAttr);
            alias type_info_uda = getUDAs!(T, Handler!().TypeInfoAttr);
            static if (type_info_uda.length == 1) {
                template GenSubTypeSerialization(size_t i = 0) {
                    static if (i >= subtypes_udas[0].subtypes.length) {
                        enum GenSubTypeSerialization = "";
                    }
                    else {
                        enum Rest = GenSubTypeSerialization!(i+1);
                        enum Type = "imported!\"" ~ subtypes_udas[0].subtypes[i].mod ~ "\"." ~ subtypes_udas[0].subtypes[i].type;
                        enum Code = "if (auto v = cast(" ~ Type ~ ") value) { this.serializeInnerObject(buff, v); }";
                        static if (Rest == "") {
                            enum GenSubTypeSerialization = Code;
                        } else {
                            enum GenSubTypeSerialization = Code ~ " else " ~ Rest;
                        }
                    }
                }

                mixin(Handler!().PutObjectWithTypeInfo!(
                    type_info_uda[0],
                    SerializeTypeInfo!(
                        T,
                        Handler!().TypeInfoAttr,
                        Handler!().PutTypeInfo,
                        type_info_uda[0], subtypes_udas
                    ),
                    GenSubTypeSerialization!()
                ));
            }
            else static if (type_info_uda.length > 1) {
                static assert(0, "Cannot have more than one @" ~ __traits(identifier, Handler!().TypeInfoAttr!()) ~ " attribute on `" ~ fullyQualifiedName!T ~ "`");
            }
            else {
                mixin(Handler!().PutObject);
            }
        }
        else static if (isSomeString!T) {
            mixin(Handler!().PutString);
        }
        else static if (isArray!T) {
            mixin(Handler!().PutArray);
        }
        else static if (isAssociativeArray!T) {
            mixin(Handler!().PutAssociativeArray);
        }
        else static if (is(T == enum)) {
            mixin(Handler!().PutEnum);
        }
        else static if (isBasicType!T) {
            mixin(Handler!().PutBasic);
        }
        else {
            static assert(0, "Cannot serialize: " ~ fullyQualifiedName!T);
        }
    }
}
