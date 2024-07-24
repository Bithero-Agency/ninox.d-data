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
