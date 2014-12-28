/**
	Punycode converter. This module is based on the original implementation in RFC 3492, and the JavaScript implementation by Mathias Bynens.

	License: MIT
*/
module punycode;


import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.exception;
import std.traits;


/**
	Converts an UTF string to a Punycode string.

	Throws:
		PunycodeException if an internal error occured.

	Standards:
		$(LINK2 https://www.ietf.org/rfc/rfc3492.txt, RFC 3492)
*/
S punyEncode(S)(S str)
	if (isSomeString!S)
{
	static char encodeDigit(uint x)
	{
		if (x <= 25) return cast(char)('a' + x);
		else if (x <= 35) return cast(char)('0' + x - 26);
		assert(0);
	}

	auto dstr = str.to!dstring;

	auto ret = appender!S;

	ret ~= dstr.filter!isASCII;
	assert(ret.data.length <= uint.max);

	auto handledLength = cast(uint)ret.data.length;
	immutable basicLength = handledLength;

	if (handledLength > 0) ret ~= '-';

	if (handledLength == dstr.length) return ret.data;

	import std.functional : not;
	auto ms = (() @trusted => (cast(uint[])(dstr.filter!(not!isASCII).array)).sort!"a < b")();

	dchar n = initialN;
	uint delta = 0;
	uint bias = initialBias;
	while (handledLength < dstr.length)
	{
		dchar m = void;
		while ((m = ms.front) < n) ms.popFront();

		enforceEx!PunycodeException((m - n) * (handledLength + 1) <= uint.max - delta, "Arithmetic overflow");
		delta += (m - n) * (handledLength + 1);

		n = m;

		foreach (immutable(dchar) c; dstr)
		{
			if (c < n)
			{
				enforceEx!PunycodeException(delta != uint.max, "Arithmetic overflow");
				delta++;
			}
			else if (c == n)
			{
				auto q = delta;

				for (auto k = base;;k += base)
				{
					immutable t = k <= bias ? tmin :
						k >= bias + tmax ? tmax : k - bias;

					if (q < t) break;

					ret ~= encodeDigit(t + (q - t) % (base - t));
					q = (q - t) / (base - t);
				}

				ret ~= encodeDigit(q);

				bias = adaptBias(delta, cast(uint)handledLength + 1, handledLength == basicLength);
				delta = 0;
				handledLength++;
			}
		}
		delta++;
		n++;
	}

	return ret.data;
}

///
/+pure+/ @safe
unittest
{
	assert(punyEncode("mañana") == "maana-pta");
}


/**
	Converts a Punycode string to an UTF string.

	Throws:
		PunycodeException if an internal error occured.

		InvalidPunycodeException if an invalid Punycode string was passed.

	Standards:
		$(LINK2 https://www.ietf.org/rfc/rfc3492.txt, RFC 3492)
*/
S punyDecode(S)(in S str)
	if (isSomeString!S)
{
	static uint decodeDigit(dchar c)
	{
		if (c.isUpper) return c - 'A';
		if (c.isLower) return c - 'a';
		if (c.isDigit) return c - '0' + 26;
		throw new InvalidPunycodeException("Invalid Punycode");
	}

	auto dstr = str.to!dstring;
	assert(dstr.length <= uint.max);

	dchar[] ret;

	dchar n = initialN;
	uint i = 0;
	uint bias = initialBias;

	import std.string : lastIndexOf;
	immutable delimIdx = dstr.lastIndexOf('-');
	if (delimIdx != -1)
	{
		enforceEx!InvalidPunycodeException(dstr[0 .. delimIdx].all!isASCII, "Invalid Punycode");
		ret = dstr[0 .. delimIdx].dup;
	}

	auto idx = (delimIdx == -1 || delimIdx == 0) ? 0 : delimIdx + 1;

	while (idx < dstr.length)
	{
		immutable oldi = i;
		uint w = 1;

		for (auto k = base;;k += base)
		{
			enforceEx!InvalidPunycodeException(idx < dstr.length);

			immutable digit = decodeDigit(dstr[idx]);
			idx++;

			enforceEx!PunycodeException(digit * w <= uint.max - i, "Arithmetic overflow");
			i += digit * w;

			immutable t = k <= bias ? tmin :
				k >= bias + tmax ? tmax : k - bias;
			if (digit < t) break;

			enforceEx!PunycodeException(w <= uint.max / (base - t), "Arithmetic overflow");
			w *= base - t;
		}

		enforceEx!PunycodeException(ret.length < uint.max-1, "Arithmetic overflow");

		bias = adaptBias(i - oldi, cast(uint) ret.length + 1, oldi == 0);

		enforceEx!PunycodeException(i / (ret.length + 1) <= uint.max - n, "Arithmetic overflow");
		n += i / (ret.length + 1);

		i %= ret.length + 1;

		(() @trusted => ret.insertInPlace(i, n))();

		i++;
	}

	return ret.to!S;
}

///
@safe /+pure+/
unittest
{
	assert(punyDecode("maana-pta") == "mañana");
}


@safe /+pure+/
unittest
{
	static void assertConvertible(S)(S plain, S punycode)
	{
		assert(punyEncode(plain) == punycode);
		assert(punyDecode(punycode) == plain);
	}

	assertCTFEable!({
		assertConvertible("", "");
		assertConvertible("ASCII0123", "ASCII0123-");
		assertConvertible("Punycodeぴゅにこーど", "Punycode-p73grhua1i6jv5d");
		assertConvertible("Punycodeぴゅにこーど"w, "Punycode-p73grhua1i6jv5d"w);
		assertConvertible("Punycodeぴゅにこーど"d, "Punycode-p73grhua1i6jv5d"d);
		assertConvertible("ぴゅにこーど", "28j1be9azfq9a");
		assertConvertible("他们为什么不说中文", "ihqwcrb4cv8a8dqg056pqjye");
		assertConvertible("☃-⌘", "--dqo34k");
		assertConvertible("-> $1.00 <-", "-> $1.00 <--");
		assertThrown!InvalidPunycodeException(punyDecode("aaa-*"));
		assertThrown!InvalidPunycodeException(punyDecode("aaa-p73grhua1i6jv5dd"));
		assertThrown!InvalidPunycodeException(punyDecode("ü-"));
		assert(collectExceptionMsg(punyDecode("aaa-99999999")) == "Arithmetic overflow");
	});
}


/**
	Exception thrown by punycode module.
  */
class PunycodeException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
		@safe pure nothrow
	{
		super(msg, file, line, next);
	}
}


/// ditto
class InvalidPunycodeException : PunycodeException
{
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
		@safe pure nothrow
	{
		super(msg, file, line, next);
	}
}


private:


enum base = 36;
enum initialN = 0x80;
enum initialBias = 72;
enum tmin = 1;
enum tmax = 26;
enum damp = 700;
enum skew = 38;


uint adaptBias(uint delta, uint numpoints, bool firsttime) @safe pure nothrow /+@nogc+/
{
	delta = firsttime ? delta / damp : delta / 2;
	delta += delta / numpoints;

	uint k;
	while (delta > ((base - tmin) * tmax) / 2)
	{
		delta /= base - tmin;
		k += base;
	}

	return k + (base - tmin + 1) * delta / (delta + skew);
}

version (unittest) void assertCTFEable(alias f)()
{
	static assert({ f(); return true; }());
	f();
}
