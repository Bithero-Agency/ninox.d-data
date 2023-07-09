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
 * Module for a basic serialization buffer
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.data.buffer;

import ministd.callable;

/// Base escape function that does no escaping
void noEscape(alias Sink)(const(ubyte)[] chars) {
    Sink(chars);
}

/// Base class for all serialization buffers
/// 
/// This class accepts an sink to send data to once the buffer is full / is flushed.
/// Note: you always need to make sure to flush the buffer after use.
/// 
/// Params:
///   Esc = the escape function to use, default is `noEscape`
class SerializerBuffer(alias Esc = noEscape) {
private:
    Callable!(void, const(char)[]) sink;

    size_t len;
    char[4069 * 4] data = void;

public:
    this(void function(const(char)[]) sink) {
        this.sink = sink;
    }
    this(void delegate(const(char)[]) sink) {
        this.sink = sink;
    }

    void put(char c) {
        if (this.len == this.data.length) { this.flush(); }
        this.data[this.len++] = c;
    }

    void putRaw(in char[] str) {
        import std.range: chunks;
        import std.string: representation;

        foreach (chunk; str.representation.chunks(256)) {
            if (this.len + chunk.length >= this.data.length) { this.flush(); }
            foreach (b; chunk) {
                this.data[this.len++] = b;
            }
        }
    }

    void put(in char[] str) {
        import std.range: chunks;
        import std.string: representation;

        void appendData(const(ubyte)[] bytes) {
            if (this.len + bytes.length >= this.data.length) { this.flush(); }
            foreach (b; bytes) {
                this.data[this.len++] = b;
            }
        }

        foreach (chunk; str.representation.chunks(256)) {
            Esc!(appendData)(chunk);
        }
    }

    void flush() {
        this.sink(this.data[0 .. this.len]);
        this.len = 0;
    }
}

/// Basic escape function that does slash escaption like in JSON strings
void backslashEscape(alias Sink)(const(ubyte)[] chars) {
    size_t tmp = 0;
    foreach (i, c; chars) {
        switch (c) {
            case '\"':
            case '\\':
            case '\b':
            case '\f':
            case '\n':
            case '\r':
            case '\t':
            {
                Sink(chars[tmp .. i]);
                tmp = i + 1;

                Sink([ '\\', c ]);
                continue;
            }

            case '\0': .. case '\u0007':
            case '\u000e': .. case '\u001f':
            case '\u000b':
            case '\u00ff':
            {
                Sink(chars[tmp .. i]);
                tmp = i + 1;

                ubyte[2] spl;
                spl[0] = c >> 4;
                spl[1] = c & 0xF;
                Sink([
                    '\\', 'u', '0', '0',
                    cast(ubyte)( spl[0] < 10 ? spl[0] + '0' : spl[0] - 10 + 'A' ),
                    cast(ubyte)( spl[1] < 10 ? spl[1] + '0' : spl[1] - 10 + 'A' )
                ]);
                continue;
            }

            default:
                break;
        }
    }
    Sink(chars[tmp .. chars.length]);
}

unittest {
    import std.array: appender;
    import std.range.primitives: put;

    auto app = appender!(char[]);
    auto sink = (const(char)[] chars) => put(app, chars);

    auto buff = new SerializerBuffer!(backslashEscape)(sink);

    buff.put('h');
    buff.put('e');
    buff.put('l');
    buff.put('l');
    buff.put('o');

    buff.put(" zz\u001fzz\"zz");

    buff.flush();

    auto res = cast(string) app.data;

    assert(res == "hello zz\\u001Fzz\\\"zz", "buffer dosnt contain the right data!");
}