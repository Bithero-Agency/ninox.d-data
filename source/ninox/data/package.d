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
 * Main module
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */

module ninox.data;

public import ninox.data.buffer;

import std.traits : isSomeString;

/// Function to help serializing with an serializer
/// 
/// Params:
///   value = the value to serialize
///   serializer = the serializer
/// 
/// Returns: the string containing the serialized value
string serialize(S, T)(auto ref T value, auto ref S serializer) {
    return serializer.serialize(value);
}

/// Function to help deserializing with an serializer
/// 
/// Params:
///   inp = the input string
///   serializer = the serializer
/// 
/// Returns: the deserialized value
V deserialize(V, S, I)(I inp, auto ref S serializer)
if (isSomeString!I && !isSomeString!S)
{
    return serializer.deserialize!(V)(inp);
}
