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

    bool hasSerializer(T)() {
        return (fullyQualifiedName!T in rtSerializers) !is null;
    }

}
