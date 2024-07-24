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
 * Module for a basic deserialization parser
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */

module ninox.data.parser;

import ninox.std.callable;
import std.ascii : isWhite;

abstract class DeserializerParser {
protected:
    enum BufferSize = 4069 * 4;

    Callable!(size_t, char[], size_t) source;
    size_t len, pos;
    char[BufferSize] data = void;

public:
    this(size_t function(char[], size_t) source) {
        this.source = source;
    }
    this(size_t delegate(char[], size_t) source) {
        this.source = source;
    }

    /// Fills up the internal buffer
    void fill(bool handleEOF = true) {
        this.len = this.source(this.data, BufferSize);
        if (handleEOF && this.len < 1) {
            throw this.buildParseException("End of file reached");
        }
        this.pos = 0;
    }

    /// Checks if filling is needed and fills the buffer (only when the buffer is completly empty!)
    pragma(inline) void fillIfNeeded(bool handleEOF = true) {
        if (this.pos >= this.len) {
            this.fill(handleEOF);
        }
    }

    /// Checks if the parser is at the end
    /// 
    /// Returns: true if the parser is at the end; false otherwise
    bool isAtEnd() {
        this.fillIfNeeded(false);
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
            if (c.isWhite) {
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
            throw this.buildParseException("require '" ~ c ~ "'");
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
                throw this.buildParseException("require '" ~ s ~ "'");
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

protected:
    Exception buildParseException(string msg, string file = __FILE__, size_t line = __LINE__);
}
