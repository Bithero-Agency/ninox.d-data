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
 * Module for a basic traits / templates
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */

module ninox.data.traits;

package(ninox.data):

template SetterFromOverloads(overloads...)
{
    import std.meta, std.traits;
    alias setter = AliasSeq!();
    static foreach (overload; overloads) {
        static if (is(ReturnType!overload == void) && Parameters!overload.length == 1) {
            setter = AliasSeq!(setter, overload);
        }
    }
    static assert(setter.length == 1, "Could not find setter from overload set");
    alias SetterFromOverloads = setter[0];
}

template GetterFromOverloads(overloads...)
{
    import std.meta, std.traits;
    alias getter = AliasSeq!();
    static foreach (overload; overloads) {
        static if (!is(ReturnType!overload == void) && Parameters!overload.length == 0) {
            getter = AliasSeq!(getter, overload);
        }
    }
    static assert(getter.length == 1, "Could not find getter from overload set");
    alias GetterFromOverloads = getter[0];
}

template GetTypeForDeserialization(alias Elem)
{
    import std.traits;
    static if (isCallable!Elem) {
        alias GetTypeForDeserialization = Parameters!Elem;
    }
    else {
        alias GetTypeForDeserialization = typeof(Elem);
    }
}

template KeyFromCustomProperty(CustomPropertyTy) {
    template KeyFromCustomProperty(alias T, string name, alias E) {
        import std.traits;
        static if (hasUDA!(E, CustomPropertyTy)) {
            alias udas = getUDAs!(E, CustomPropertyTy);
            static assert(udas.length == 1, "Field `" ~ fullyQualifiedName!T ~ "." ~ name ~ "` can only have one @" ~ CustomPropertyTy.stringof);

            alias uda = udas[0];
            static if (is(uda == CustomPropertyTy)) {
                enum KeyFromCustomProperty = name;
            } else {
                static if (uda.name == "") {
                    enum KeyFromCustomProperty = name;
                } else {
                    enum KeyFromCustomProperty = uda.name;
                }
            }
        } else {
            enum KeyFromCustomProperty = name;
        }
    }
}

template KeyFromCustomPropertyOverloads(CustomPropertyTy) {
    template KeyFromCustomPropertyOverloads(alias T, string name, overloads...)
    {
        import std.meta, std.traits;
        template Inner(size_t i = 0) {
            static if (i >= overloads.length) {
                alias Inner = AliasSeq!();
            } else {
                alias overload = overloads[i];
                alias udas = getUDAs!(overload, CustomPropertyTy);
                static if (udas.length > 0) {
                    static assert(udas.length == 1, "Property `" ~ fullyQualifiedName!T ~ "." ~ name ~ "` can only have one @" ~ CustomPropertyTy.stringof);
                    static if (!is(udas[0] == CustomPropertyTy) && udas[0].name != "") {
                        alias Inner = AliasSeq!(udas[0].name, Inner!(i+1));
                    } else {
                        alias Inner = Inner!(i+1);
                    }
                } else {
                    alias Inner = Inner!(i+1);
                }
            }
        }
        alias Keys = Inner!(0);
        static assert(Keys.length <= 1, "Property overload set `" ~ fullyQualifiedName!T ~ "." ~ name ~ "` can only have one @" ~ CustomPropertyTy.stringof);
        static if (Keys.length < 1) {
            enum KeyFromCustomPropertyOverloads = name;
        } else {
            enum KeyFromCustomPropertyOverloads = Keys[0];
        }
    }
}

template GenericSerializeValueCode(string FormatName, alias SerializeTy, alias RawValueTy)
{
    template GenericSerializeValueCode(alias T, alias Elem, string getElemCode, string getRawValCode, string name)
    {
        import std.traits;
        static if (hasUDA!(Elem, SerializeTy)) {
            import std.conv : to;
            enum GenericSerializeValueCode =
                "{ " ~
                    "alias T = imported!\"" ~ moduleName!T ~ "\"." ~ T.stringof ~ ";" ~
                    getElemCode ~
                    "alias udas = getUDAs!(Elem, " ~ SerializeTy.stringof ~ ");" ~
                    "static assert (udas.length == 1, \"Cannot serialize member `" ~ fullyQualifiedName!T ~ "." ~ name ~ "`: got more than one @" ~ SerializeTy.stringof ~ " attributes\");" ~
                    "callCustomSerializer!(udas)(buff, " ~ getRawValCode ~ ");" ~
                " }";
        } else static if (hasUDA!(Elem, RawValueTy)) {
            alias ty = typeof(Elem);
            static if (is(ty == function)) {
                static assert(
                    isSomeString!(ReturnType!ty),
                    "Cannot use member `" ~ fullyQualifiedName!T ~ "." ~ name ~ "` for raw " ~ FormatName ~ ": getter needs to return a string-like type"
                );
            } else {
                static assert(
                    isSomeString!ty,
                    "Cannot use member `" ~ fullyQualifiedName!T ~ "." ~ name ~ "` for raw " ~ FormatName ~ ": is not of string-like type"
                );
            }

            enum GenericSerializeValueCode = "buff.putRaw(" ~ getRawValCode ~ ");";
        } else {
            enum GenericSerializeValueCode = "this.serialize(buff, " ~ getRawValCode ~ ");";
        }
    }
}
