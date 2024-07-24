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
