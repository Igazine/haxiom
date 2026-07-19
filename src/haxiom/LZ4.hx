package haxiom;

import haxe.io.Bytes;

/**
 * Pure Haxe LZ4 Block Compressor and Decompressor.
 * 100% target-agnostic (works on C++, HashLink, JS, Java, C#, Eval, Python, etc.)
 */
class LZ4 {
	/**
	 * Decompresses an LZ4 compressed payload.
	 * The input bytes start with a 4-byte little-endian uncompressed length header.
	 */
	public static function decompress(src:Bytes):Bytes {
		if (src == null || src.length < 4) {
			throw "LZ4 Decompress Error: Invalid payload (too short)";
		}

		var uncompressedLen = src.get(0) | (src.get(1) << 8) | (src.get(2) << 16) | (src.get(3) << 24);
		if (uncompressedLen == 0) {
			return Bytes.alloc(0);
		}

		var dst = Bytes.alloc(uncompressedLen);
		var ip = 4;
		var srcLen = src.length;
		var op = 0;

		while (ip < srcLen) {
			var token = src.get(ip++);
			var literalLen = token >> 4;

			if (literalLen == 15) {
				var s = 0;
				do {
					s = src.get(ip++);
					literalLen += s;
				} while (s == 255 && ip < srcLen);
			}

			// Copy literals
			if (literalLen > 0) {
				dst.blit(op, src, ip, literalLen);
				op += literalLen;
				ip += literalLen;
			}

			if (ip >= srcLen || op >= uncompressedLen) {
				break;
			}

			// Read offset (16-bit LE)
			var offset = src.get(ip) | (src.get(ip + 1) << 8);
			ip += 2;

			var matchLen = token & 0x0F;
			if (matchLen == 15) {
				var s = 0;
				do {
					s = src.get(ip++);
					matchLen += s;
				} while (s == 255 && ip < srcLen);
			}
			matchLen += 4;

			// Copy match (handle overlapping bytes)
			var matchPos = op - offset;
			if (matchPos < 0) {
				throw "LZ4 Decompress Error: Invalid match offset";
			}

			for (i in 0...matchLen) {
				dst.set(op + i, dst.get(matchPos + i));
			}
			op += matchLen;
		}

		return dst;
	}

	/**
	 * Compresses a Bytes instance using LZ4 block format.
	 * Prepends 4-byte little-endian uncompressed length.
	 */
	public static function compress(src:Bytes):Bytes {
		if (src == null || src.length == 0) {
			var empty = Bytes.alloc(4);
			empty.set(0, 0);
			empty.set(1, 0);
			empty.set(2, 0);
			empty.set(3, 0);
			return empty;
		}

		var srcLen = src.length;
		// Worst case buffer size calculation
		var maxDstLen = 4 + srcLen + (Std.int(srcLen / 255) + 16);
		var dst = Bytes.alloc(maxDstLen);

		// Write uncompressed length (4 bytes LE)
		dst.set(0, srcLen & 0xFF);
		dst.set(1, (srcLen >> 8) & 0xFF);
		dst.set(2, (srcLen >> 16) & 0xFF);
		dst.set(3, (srcLen >> 24) & 0xFF);

		var ip = 0;
		var anchor = 0;
		var op = 4;

		// Hash table for 4-byte match lookup (4096 entries)
		var hashTable = new Array<Int>();
		for (i in 0...4096)
			hashTable.push(-1);

		inline function hash4(pos:Int):Int {
			var v = src.get(pos) | (src.get(pos + 1) << 8) | (src.get(pos + 2) << 16) | (src.get(pos + 3) << 24);
			return ((v * -1640531527) >>> 20) & 4095;
		}

		var limit = srcLen - 12;

		while (ip < limit) {
			var h = hash4(ip);
			var ref = hashTable[h];
			hashTable[h] = ip;

			if (ref >= 0 && (ip - ref) <= 65535 && (ip - ref) > 0
				&& src.get(ref) == src.get(ip)
				&& src.get(ref + 1) == src.get(ip + 1)
				&& src.get(ref + 2) == src.get(ip + 2)
				&& src.get(ref + 3) == src.get(ip + 3)) {
				// Match found! Calculate match length
				var matchCode = 4;
				while ((ip + matchCode < srcLen) && (src.get(ref + matchCode) == src.get(ip + matchCode))) {
					matchCode++;
				}

				var litLen = ip - anchor;
				var tokenLit = litLen < 15 ? litLen : 15;
				var tokenMatch = (matchCode - 4) < 15 ? (matchCode - 4) : 15;

				// Write token
				dst.set(op++, (tokenLit << 4) | tokenMatch);

				// Extra literal length bytes
				if (litLen >= 15) {
					var len = litLen - 15;
					while (len >= 255) {
						dst.set(op++, 255);
						len -= 255;
					}
					dst.set(op++, len);
				}

				// Copy literals
				if (litLen > 0) {
					dst.blit(op, src, anchor, litLen);
					op += litLen;
				}

				// Write offset (16-bit LE)
				var offset = ip - ref;
				dst.set(op++, offset & 0xFF);
				dst.set(op++, (offset >> 8) & 0xFF);

				// Extra match length bytes
				if ((matchCode - 4) >= 15) {
					var len = (matchCode - 4) - 15;
					while (len >= 255) {
						dst.set(op++, 255);
						len -= 255;
					}
					dst.set(op++, len);
				}

				ip += matchCode;
				anchor = ip;
			} else {
				ip++;
			}
		}

		// Write remaining literals
		var lastLit = srcLen - anchor;
		var tokenLit = lastLit < 15 ? lastLit : 15;
		dst.set(op++, tokenLit << 4);

		if (lastLit >= 15) {
			var len = lastLit - 15;
			while (len >= 255) {
				dst.set(op++, 255);
				len -= 255;
			}
			dst.set(op++, len);
		}

		if (lastLit > 0) {
			dst.blit(op, src, anchor, lastLit);
			op += lastLit;
		}

		// Return trimmed output
		var result = Bytes.alloc(op);
		result.blit(0, dst, 0, op);
		return result;
	}
}
