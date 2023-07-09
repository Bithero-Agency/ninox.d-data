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
 * Module for all json UDA's
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.data.json.attributes;

// --------------------------------------------------------------------------------
//  Serialization
// --------------------------------------------------------------------------------

/// UDA to allow to serialize arbitary keys into an object
struct JsonAnyGetter {}

/// UDA to use an method for serialization of an key in a object
struct JsonGetter {
    string name;
}

// UDA to order properties
// struct JsonPropertyOrder {
//     string[] order;
//     bool alphabetic = false;
// }

/// UDA to allow strings to be treated as raw json
struct JsonRawValue {}

// UDA used to tell the serializer to use the annotated thing
//  for serialization instead of the default way.
// struct JsonValue {}

/// UDA to specify a custom serializer
struct JsonSerialize(alias T, Args...) {}

// --------------------------------------------------------------------------------
//  Deserialization
// --------------------------------------------------------------------------------

// struct JsonCreator {}

/// UDA to allow to deserialize arbitary keys into a structure
struct JsonAnySetter {}

/// UDA to use an method for deserialization of an key into to structure
struct JsonSetter {
    string name;
}

/// UDA to specify a custom deserializer
struct JsonDeserialize(alias T, Args...) {}

// UDA to specify alias keys when deserializing
struct JsonAlias {
    string[] names;
}

// --------------------------------------------------------------------------------
//  Other
// --------------------------------------------------------------------------------

// UDA allow to define properties to be ignored on a class/structure level
// struct JsonIgnoreProperties {
//     string[] names;
// }

/// UDA to allow ignoring members
struct JsonIgnore {}

/// UDA to allow a class to be ignored fully
struct JsonIgnoreType {}

// --------------------------------------------------------------------------------

struct JsonTypeInfo {
    enum Id { CLASS, NAME }
    Id use;

    enum As { PROPERTY, WRAPPER_OBJECT, WRAPPER_ARRAY }
    As include;

    string property;
}

template mkJsonSubType(alias T, string name) {
    import std.traits : moduleName, fullyQualifiedName;
    import ninox.data.json : JsonSubTypes;
    import std.string : replace;
    enum JsonSubTypes.Type mkJsonSubType = {
        mod: moduleName!T,
        type: replace( fullyQualifiedName!T, moduleName!T ~ ".", "" ),
        name: name
    };
}

struct JsonSubTypes {
    struct Type {
        string mod;
        string type;
        string name;
    }
    Type[] subtypes;
}

// --------------------------------------------------------------------------------

/// UDA to allow specifing data for properties
struct JsonProperty {
    string name;
    // bool required = false;
}

// UDA to allow for unwrapping/flattening
// struct JsonUnwrapped {
//     string prefix;
//     string suffix;
// }
