/**
	Punycode converter.
*/
module punycode;


import core.checkedint;
import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.exception;
import std.traits;


/**
	Converts an UTF string to a Punycode string.
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

		// delta += (m - n) * (handledLength + 1);
		bool overflow; // moving this to outer scope causes wrong code generation with -O -inline?
		delta = delta.addu((m - n) * (handledLength + 1), overflow);
		enforce(!overflow, "Overflow occured");

		n = m;

		foreach (immutable(dchar) c; dstr)
		{
			if (c < n)
			{
				enforce(delta != uint.max, "Overflow occured");
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
*/
S punyDecode(S)(in S str)
	if (isSomeString!S)
{
	static uint decodeDigit(dchar c)
	{
		if (c.isUpper) return c - 'A';
		if (c.isLower) return c - 'a';
		if (c.isDigit) return c - '0' + 26;
		throw new Exception("Invalid Punycode");
	}

	auto dstr = str.to!dstring;
	assert(dstr.length <= uint.max);

	dstring ret;

	dchar n = initialN;
	uint i = 0;
	uint bias = initialBias;

	import std.string : lastIndexOf;
	immutable delimIdx = dstr.lastIndexOf('-');
	if (delimIdx != -1)
	{
		enforce(dstr[0 .. delimIdx].all!isASCII, "Invalid Punycode");
		ret = dstr[0 .. delimIdx];
	}

	auto idx = (delimIdx == -1 || delimIdx == 0) ? 0 : delimIdx + 1;

	bool overflow;
	while (idx < dstr.length)
	{
		immutable oldi = i;
		uint w = 1;

		for (auto k = base;;k += base)
		{
			enforce(idx < dstr.length, "Invalid Punycode");

			immutable digit = decodeDigit(dstr[idx]);
			idx++;

			i = i.addu(digit * w, overflow);
			enforce(!overflow, "Overflow occured");

			immutable t = k <= bias ? tmin :
				k >= bias + tmax ? tmax : k - bias;
			if (digit < t) break;

			w = w.mulu(base - t, overflow);
			enforce(!overflow, "Overflow occured");
		}

		enforce(ret.length < uint.max-1, "Overflow occured");

		bias = adaptBias(i - oldi, cast(uint) ret.length + 1, oldi == 0);

		// n += i / (ret.length + 1);
		n = n.addu(i / (ret.length + 1), overflow);
		enforce(!overflow, "Overflow occured");

		i %= ret.length + 1;

		ret.insertInPlace(i, n);

		i++;
	}

	return ret.to!S;
}

///
/+pure+/ @safe
unittest
{
	assert(punyDecode("maana-pta") == "mañana");
}


/+pure+/ @safe
unittest
{
	static void assertConvertible(S)(S plain, S punycode)
	{
		assert(punyEncode(plain) == punycode, "punyEncode");
		assert(punyDecode(punycode) == plain, "punyDecode");
	}

	assertCTFEable!({
		assertConvertible("", "");
		assertConvertible("ASCII0123", "ASCII0123-");
		assertConvertible("Punycodeぴゅにこーど", "Punycode-p73grhua1i6jv5d");
		assertConvertible("ぴゅにこーど"w, "28j1be9azfq9a"w);
		assertConvertible("他们为什么不说中文"d, "ihqwcrb4cv8a8dqg056pqjye"d);
		assertConvertible("☃-⌘", "--dqo34k");
		assertConvertible("-> $1.00 <-", "-> $1.00 <--");
		assertThrown(punyDecode("aaa-*"));
		assertThrown(punyDecode("aaa-p73grhua1i6jv5dd"));
	});
}


private:


enum base = 36;
enum initialN = 0x80;
enum initialBias = 72;
enum tmin = 1;
enum tmax = 26;
enum damp = 700;
enum skew = 38;

uint adaptBias(uint delta, uint numpoints, bool firsttime) pure @safe nothrow /+@nogc+/
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
