/*
 * Diff Match and Patch
 *
 * Copyright 2006 Google Inc.
 * http://code.google.com/p/google-diff-match-patch/
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package dmp;

import haxe.PosInfos;

using StringTools;

/**
* Internal class for returning results from diff_linesToChars().
*/
typedef LinesToCharsResult = {
	var chars1: String;
	var chars2: String;
	var lineArray: Array<String>;
}

/**
 * The data structure representing a diff is a Linked list of Diff objects:
 * {Diff(Operation.DELETE, "Hello"), Diff(Operation.INSERT, "Goodbye"),
 *  Diff(Operation.EQUAL, " world.")}
 * which means: delete "Hello", add "Goodbye" and keep " world."
 */
@:enum
 abstract Operation(Int) {
	var DELETE = -1;
	var EQUAL = 0;
	var INSERT = 1;
}

class Character {
	inline public static function isLetterOrDigit(char: String)
		return ~/[a-z0-9]/i.match(char);
	inline public static function isWhitespace(char: String)
		return ~/\s/.match(char);
	inline public static function isLinebreak(char: String)
		return ~/[\r\n]/.match(char);
	inline public static function endsWithLinebreak(char: String)
		return ~/\n\r?\n$/.match(char);
	inline public static function startsWithLinebreak(char: String)
		return ~/^\r?\n\r?\n/.match(char);
}

class StringBuilder {
	var s: String;
	inline public function new()
		s = '';
	inline public function append(str: String) {
		s += str;
		return this;
	}
	inline public function toString(): String
		return s;
	public function addChar(char: Int) {
		#if java
		var b = new StringBuf();
		b.addChar(char);
		s += b;
		#else
		s += String.fromCharCode(char);
		#end
		return this;
	}
}

/*
 * Functions for diff, match and patch.
 * Computes the difference between two texts to create a patch.
 * Applies the patch onto another text, allowing for errors.
 *
 * @author fraser@google.com (Neil Fraser)
 */

/**
 * Class containing the diff, match and patch methods.
 * Also contains the behaviour settings.
 */
class DiffMatchPatch {

	// Defaults.
	// Set these on your diff_match_patch instance to override the defaults.

	/**
	 * Number of seconds to map a diff before giving up (0 for infinity).
	 */
	public var Diff_Timeout = 1.0;
	/**
	 * Cost of an empty edit operation in terms of edit characters.
	 */
	public var Diff_EditCost = 4;
	/**
	 * At what point is no match declared (0.0 = perfection, 1.0 = very loose).
	 */
	public var Match_Threshold = 0.5;
	/**
	 * How far to search for a match (0 = exact location, 1000+ = broad match).
	 * A match this many characters away from the expected location will add
	 * 1.0 to the score (0.0 is a perfect match).
	 */
	public var Match_Distance = 1000;
	/**
	 * When deleting a large block of text (over ~64 characters), how close do
	 * the contents have to be to match the expected contents. (0.0 = perfection,
	 * 1.0 = very loose).  Note that Match_Threshold controls how closely the
	 * end points of a delete need to match.
	 */
	public var Patch_DeleteThreshold = 0.5;
	/**
	 * Chunk size for context length.
	 */
	public var Patch_Margin = 4;

	/**
	 * The number of bits in an int.
	 */
	private var Match_MaxBits = 32;

	public function new() {}

	//  DIFF FUNCTIONS

	/**
	 * Find the differences between two texts.
	 * @param text1 Old string to be diffed.
	 * @param text2 New string to be diffed.
	 * @param checklines Speedup flag.  If false, then don't run a
	 *     line-level diff first to identify the changed areas.
	 *     If true, then run a faster slightly less optimal diff.
	 * @return Linked List of Diff objects.
	 */
	public function diff_main(text1: String, text2: String, checklines = true, ?deadline: Float): Array<Diff> {
		// Set a deadline by which time the diff must be complete.
		if (deadline == null) {
			if (Diff_Timeout <= 0) {
				deadline = Math.POSITIVE_INFINITY;
			} else {
				deadline = Date.now().getTime() + (Diff_Timeout * 1000);
			}
		}
		// Check for null inputs.
		if (text1 == null || text2 == null) {
			throw "Null inputs. (diff_main)";
		}

		// Check for equality (speedup).
		var diffs: Array<Diff>;
		if (text1 == text2) {
			diffs = [];
			if (text1.length != 0) {
				diffs.push(new Diff(Operation.EQUAL, text1));
			}
			return diffs;
		}

		// Trim off common prefix (speedup).
		var commonlength = diff_commonPrefix(text1, text2);
		var commonprefix = text1.substring(0, commonlength);
		text1 = text1.substring(commonlength);
		text2 = text2.substring(commonlength);

		// Trim off common suffix (speedup).
		commonlength = diff_commonSuffix(text1, text2);
		var commonsuffix = text1.substring(text1.length - commonlength);
		text1 = text1.substring(0, text1.length - commonlength);
		text2 = text2.substring(0, text2.length - commonlength);

		// Compute the diff on the middle block.
		diffs = diff_compute(text1, text2, checklines, deadline);

		// Restore the prefix and suffix.
		if (commonprefix.length != 0) {
			diffs.unshift(new Diff(Operation.EQUAL, commonprefix));
		}
		if (commonsuffix.length != 0) {
			diffs.push(new Diff(Operation.EQUAL, commonsuffix));
		}
		//trace(diffs);
		diff_cleanupMerge(diffs);
		return diffs;
	}

	/**
	 * Find the differences between two texts.  Assumes that the texts do not
	 * have any common prefix or suffix.
	 * @param text1 Old string to be diffed.
	 * @param text2 New string to be diffed.
	 * @param checklines Speedup flag.  If false, then don't run a
	 *     line-level diff first to identify the changed areas.
	 *     If true, then run a faster slightly less optimal diff.
	 * @param deadline Time when the diff should be complete by.
	 * @return Linked List of Diff objects.
	 */
	private function diff_compute(text1: String, text2: String, checklines: Bool, deadline: Float): Array<Diff> {
		var diffs = [];

		if (text1.length == 0) {
			// Just add some text (speedup).
			diffs.push(new Diff(Operation.INSERT, text2));
			return diffs;
		}

		if (text2.length == 0) {
			// Just delete some text (speedup).
			diffs.push(new Diff(Operation.DELETE, text1));
			return diffs;
		}
		
		var longtext = text1.length > text2.length ? text1 : text2;
		var shorttext = text1.length > text2.length ? text2 : text1;
		var i = longtext.indexOf(shorttext);
		if (i != -1) {
			// Shorter text is inside the longer text (speedup).
			var op = (text1.length > text2.length) ?
										 Operation.DELETE : Operation.INSERT;
			diffs.push(new Diff(op, longtext.substring(0, i)));
			diffs.push(new Diff(Operation.EQUAL, shorttext));
			diffs.push(new Diff(op, longtext.substring(i + shorttext.length)));
			return diffs;
		}

		if (shorttext.length == 1) {
			// Single character string.
			// After the previous speedup, the character can't be an equality.
			diffs.push(new Diff(Operation.DELETE, text1));
			diffs.push(new Diff(Operation.INSERT, text2));
			return diffs;
		}

		// Check to see if the problem can be split in two.
		var hm = diff_halfMatch(text1, text2);
		if (hm != null) {
			// A half-match was found, sort out the return data.
			var text1_a = hm[0];
			var text1_b = hm[1];
			var text2_a = hm[2];
			var text2_b = hm[3];
			var mid_common = hm[4];
			// Send both pairs off for separate processing.
			var diffs_a = diff_main(text1_a, text2_a, checklines, deadline);
			var diffs_b = diff_main(text1_b, text2_b, checklines, deadline);
			// Merge the results.
			diffs = diffs_a;
			diffs.push(new Diff(Operation.EQUAL, mid_common));
			return diffs.concat(diffs_b);
		}

		if (checklines && text1.length > 100 && text2.length > 100) {
			return diff_lineMode(text1, text2, deadline);
		}

		return diff_bisect(text1, text2, deadline);
	}

	/**
	 * Do a quick line-level diff on both strings, then rediff the parts for
	 * greater accuracy.
	 * This speedup can produce non-minimal diffs.
	 * @param text1 Old string to be diffed.
	 * @param text2 New string to be diffed.
	 * @param deadline Time when the diff should be complete by.
	 * @return Linked List of Diff objects.
	 */
	private function diff_lineMode(text1: String, text2: String, deadline: Float) {
		// Scan the text on a line-by-line basis first.
		var a = diff_linesToChars(text1, text2);
		text1 = a.chars1;
		text2 = a.chars2;
		var linearray = a.lineArray;

		var diffs = diff_main(text1, text2, false, deadline);

		// Convert the diff back to original text.
		diff_charsToLines(diffs, linearray);
		// Eliminate freak matches (e.g. blank lines)
		diff_cleanupSemantic(diffs);

		// Rediff any replacement blocks, this time character-by-character.
		// Add a dummy entry at the end.
		diffs.push(new Diff(EQUAL, ''));
		var pointer = 0;
		var count_delete = 0;
		var count_insert = 0;
		var text_delete = '';
		var text_insert = '';
		while (pointer < diffs.length) {
			switch (diffs[pointer].operation) {
				case INSERT:
					count_insert++;
					text_insert += diffs[pointer].text;
				case DELETE:
					count_delete++;
					text_delete += diffs[pointer].text;
				case EQUAL:
					// Upon reaching an equality, check for prior redundancies.
					if (count_delete >= 1 && count_insert >= 1) {
						// Delete the offending records and add the merged ones.
						diffs.splice(pointer - count_delete - count_insert,
												 count_delete + count_insert);
						pointer = pointer - count_delete - count_insert;
						var a = diff_main(text_delete, text_insert, false, deadline);
						var j = a.length - 1;
						while (j >= 0) {
							diffs.insert(pointer, a[j--]);
						}
						pointer = pointer + a.length;
					}
					count_insert = 0;
					count_delete = 0;
					text_delete = '';
					text_insert = '';
			}
			pointer++;
		}
		diffs.pop();  // Remove the dummy entry at the end.

		return diffs;
	}

	/**
	 * Find the 'middle snake' of a diff, split the problem in two
	 * and return the recursively constructed diff.
	 * See Myers 1986 paper: An O(ND) Difference Algorithm and Its Variations.
	 * @param text1 Old string to be diffed.
	 * @param text2 New string to be diffed.
	 * @param deadline Time at which to bail if not yet complete.
	 * @return LinkedList of Diff objects.
	 */
	private function diff_bisect(text1: String, text2: String, deadline: Float) {
		// Cache the text lengths to prevent multiple calls.
		var text1_length = text1.length;
		var text2_length = text2.length;
		var max_d = Std.int(((text1_length + text2_length + 1) / 2));
		var v_offset = max_d;
		var v_length = Std.int(2 * max_d);
		var v1 = [];
		var v2 = [];
		for (x in 0 ... v_length) {
			v1[x] = -1;
			v2[x] = -1;
		}
		v1[v_offset + 1] = 0;
		v2[v_offset + 1] = 0;
		var delta = text1_length - text2_length;
		// If the total number of characters is odd, then the front path will
		// collide with the reverse path.
		var front = (delta % 2 != 0);
		// Offsets for start and end of k loop.
		// Prevents mapping of space beyond the grid.
		var k1start = 0;
		var k1end = 0;
		var k2start = 0;
		var k2end = 0;
		for (d in 0 ... max_d) {
			// Bail out if deadline is reached.
			if (Date.now().getTime() > deadline) {
				break;
			}

			// Walk the front path one step.
			var k1 = -d + k1start;
			while (k1 <= d - k1end) {
				var k1_offset = v_offset + k1;
				var x1;
				if (k1 == -d || (k1 != d && v1[k1_offset - 1] < v1[k1_offset + 1])) {
					x1 = v1[k1_offset + 1];
				} else {
					x1 = v1[k1_offset - 1] + 1;
				}
				var y1 = x1 - k1;
				while (x1 < text1_length && y1 < text2_length
							 && text1.charAt(x1) == text2.charAt(y1)) {
					x1++;
					y1++;
				}
				v1[k1_offset] = x1;
				if (x1 > text1_length) {
					// Ran off the right of the graph.
					k1end += 2;
				} else if (y1 > text2_length) {
					// Ran off the bottom of the graph.
					k1start += 2;
				} else if (front) {
					var k2_offset = v_offset + delta - k1;
					if (k2_offset >= 0 && k2_offset < v_length && v2[k2_offset] != -1) {
						// Mirror x2 onto top-left coordinate system.
						var x2 = text1_length - v2[k2_offset];
						if (x1 >= x2) {
							// Overlap detected.
							return diff_bisectSplit(text1, text2, x1, y1, deadline);
						}
					}
				}
				k1 += 2;
			}

			// Walk the reverse path one step.
			var k2 = -d + k2start;
			while (k2 <= d - k2end) {
				var k2_offset = v_offset + k2;
				var x2;
				if (k2 == -d || (k2 != d && v2[k2_offset - 1] < v2[k2_offset + 1])) {
					x2 = v2[k2_offset + 1];
				} else {
					x2 = v2[k2_offset - 1] + 1;
				}
				var y2 = x2 - k2;
				while (x2 < text1_length && y2 < text2_length
							 && text1.charAt(text1_length - x2 - 1)
							 == text2.charAt(text2_length - y2 - 1)) {
					x2++;
					y2++;
				}
				v2[k2_offset] = x2;
				if (x2 > text1_length) {
					// Ran off the left of the graph.
					k2end += 2;
				} else if (y2 > text2_length) {
					// Ran off the top of the graph.
					k2start += 2;
				} else if (!front) {
					var k1_offset = v_offset + delta - k2;
					if (k1_offset >= 0 && k1_offset < v_length && v1[k1_offset] != -1) {
						var x1 = v1[k1_offset];
						var y1 = v_offset + x1 - k1_offset;
						// Mirror x2 onto top-left coordinate system.
						x2 = text1_length - x2;
						if (x1 >= x2) {
							// Overlap detected.
							return diff_bisectSplit(text1, text2, x1, y1, deadline);
						}
					}
				}
				k2 += 2;
			}
		}
		// Diff took too long and hit the deadline or
		// number of diffs equals number of characters, no commonality at all.
		var diffs = [];
		diffs.push(new Diff(Operation.DELETE, text1));
		diffs.push(new Diff(Operation.INSERT, text2));
		return diffs;
	}

	/**
	 * Given the location of the 'middle snake', split the diff in two parts
	 * and recurse.
	 * @param text1 Old string to be diffed.
	 * @param text2 New string to be diffed.
	 * @param x Index of split point in text1.
	 * @param y Index of split point in text2.
	 * @param deadline Time at which to bail if not yet complete.
	 * @return LinkedList of Diff objects.
	 */
	private function diff_bisectSplit(text1: String, text2: String, x: Int, y: Int, deadline: Float) {
		var text1a = text1.substring(0, x);
		var text2a = text2.substring(0, y);
		var text1b = text1.substring(x);
		var text2b = text2.substring(y);

		// Compute both diffs serially.
		var diffs = diff_main(text1a, text2a, false, deadline);
		var diffsb = diff_main(text1b, text2b, false, deadline);

		return diffs.concat(diffsb);
	}

	/**
	 * Split two texts into a list of strings.  Reduce the texts to a string of
	 * hashes where each Unicode character represents one line.
	 * @param text1 First string.
	 * @param text2 Second string.
	 * @return An object containing the encoded text1, the encoded text2 and
	 *     the List of unique strings.  The zeroth element of the List of
	 *     unique strings is intentionally blank.
	 */
	private function diff_linesToChars(text1: String, text2: String): LinesToCharsResult {
		var lineArray = [];
		var lineHash: Map<String, Int> = new Map();
		// e.g. linearray[4] == "Hello\n"
		// e.g. linehash.get("Hello\n") == 4

		// "\x00" is a valid character, but various debuggers don't like it.
		// So we'll insert a junk entry to avoid generating a null character.
		lineArray.push("");

		var chars1 = diff_linesToCharsMunge(text1, lineArray, lineHash);
		var chars2 = diff_linesToCharsMunge(text2, lineArray, lineHash);
		return {
		chars1: chars1, 
		chars2: chars2, 
		lineArray: lineArray
	};
	}

	/**
	 * Split a text into a list of strings.  Reduce the texts to a string of
	 * hashes where each Unicode character represents one line.
	 * @param text String to encode.
	 * @param lineArray List of unique strings.
	 * @param lineHash Map of strings to indices.
	 * @return Encoded string.
	 */
	private function diff_linesToCharsMunge(text: String, lineArray: Array<String>, lineHash: Map<String, Int>) {
		var lineStart = 0;
		var lineEnd = -1;
		var line;
		var chars = new StringBuilder();
		// Walk the text, pulling out a substring for each line.
		// text.split('\n') would would temporarily double our memory footprint.
		// Modifying text would create many large strings to garbage collect.
		while (lineEnd < text.length - 1) {
			lineEnd = text.indexOf('\n', lineStart);
			if (lineEnd == -1) {
				lineEnd = text.length - 1;
			}
			line = text.substring(lineStart, lineEnd + 1);
			lineStart = lineEnd + 1;

			if (lineHash.exists(line)) {
				chars.addChar(lineHash.get(line));
			} else {
				lineArray.push(line);
				lineHash.set(line, lineArray.length - 1);
				chars.addChar(lineArray.length - 1);
			}
		}
		return chars.toString();
	}

	/**
	 * Rehydrate the text in a diff from a string of line hashes to real lines of
	 * text.
	 * @param diffs LinkedList of Diff objects.
	 * @param lineArray List of unique strings.
	 */
	private function diff_charsToLines(diffs: Array<Diff>, lineArray: Array<String>) {
		var text;
		for (diff in diffs) {
			text = new StringBuilder();
			for (y in  0 ... diff.text.length) {
				text.append(lineArray[diff.text.charCodeAt(y)]);
			}
			diff.text = text.toString();
		}
		
	}

	/**
	 * Determine the common prefix of two strings
	 * @param text1 First string.
	 * @param text2 Second string.
	 * @return The number of characters common to the start of each string.
	 */
	public function diff_commonPrefix(text1: String, text2: String) {
		// Performance analysis: http://neil.fraser.name/news/2007/10/09/
		var n = Std.int(Math.min(text1.length, text2.length));
		for (i in  0 ... n) {
			if (text1.charAt(i) != text2.charAt(i)) {
				return i;
			}
		}
		return n;
	}

	/**
	 * Determine the common suffix of two strings
	 * @param text1 First string.
	 * @param text2 Second string.
	 * @return The number of characters common to the end of each string.
	 */
	public function diff_commonSuffix(text1: String, text2: String) {
		// Performance analysis: http://neil.fraser.name/news/2007/10/09/
		var text1_length = text1.length;
		var text2_length = text2.length;
		var n: Int = Std.int(Math.min(text1_length, text2_length));
		for (i in 0 ... n + 1) {
			if (text1.charAt(text1_length - i) != text2.charAt(text2_length - i)) {
				return i - 1;
			}
		}
		return n;
	}

	/**
	 * Determine if the suffix of one string is the prefix of another.
	 * @param text1 First string.
	 * @param text2 Second string.
	 * @return The number of characters common to the end of the first
	 *     string and the start of the second string.
	 */
	private function diff_commonOverlap(text1: String, text2: String): Int {
		// Cache the text lengths to prevent multiple calls.
		var text1_length = text1.length;
		var text2_length = text2.length;
		// Eliminate the null case.
		if (text1_length == 0 || text2_length == 0) {
			return 0;
		}
		// Truncate the longer string.
		if (text1_length > text2_length) {
			text1 = text1.substring(text1_length - text2_length);
		} else if (text1_length < text2_length) {
			text2 = text2.substring(0, text1_length);
		}
		var text_length = Std.int(Math.min(text1_length, text2_length));
		// Quick check for the worst case.
		if (text1 == text2) {
			return text_length;
		}

		// Start by looking for a single character match
		// and increase length until no match is found.
		// Performance analysis: http://neil.fraser.name/news/2010/11/04/
		var best = 0;
		var length = 1;
		while (true) {
			var pattern = text1.substring(text_length - length);
			var found = text2.indexOf(pattern);
			if (found == -1) {
				return best;
			}
			length += found;
			if (found == 0 || text1.substring(text_length - length) == text2.substring(0, length)) {
				best = length;
				length++;
			}
		}
	}

	/**
	 * Do the two texts share a substring which is at least half the length of
	 * the longer text?
	 * This speedup can produce non-minimal diffs.
	 * @param text1 First string.
	 * @param text2 Second string.
	 * @return Five element String array, containing the prefix of text1, the
	 *     suffix of text1, the prefix of text2, the suffix of text2 and the
	 *     common middle.  Or null if there was no match.
	 */
	private function diff_halfMatch(text1: String, text2: String): Array<String> {
		if (Diff_Timeout <= 0) {
			// Don't risk returning a non-optimal diff if we have unlimited time.
			return null;
		}
		var longtext = text1.length > text2.length ? text1 : text2;
		var shorttext = text1.length > text2.length ? text2 : text1;
		if (longtext.length < 4 || shorttext.length * 2 < longtext.length) {
			return null;  // Pointless.
		}

		// First check if the second quarter is the seed for a half-match.
		var hm1 = diff_halfMatchI(longtext, shorttext, Std.int((longtext.length + 3) / 4));
		// Check again based on the third quarter.
		var hm2 = diff_halfMatchI(longtext, shorttext, Std.int((longtext.length + 1) / 2));
		var hm;
		if (hm1 == null && hm2 == null) {
			return null;
		} else if (hm2 == null) {
			hm = hm1;
		} else if (hm1 == null) {
			hm = hm2;
		} else {
			// Both matched.  Select the longest.
			hm = hm1[4].length > hm2[4].length ? hm1 : hm2;
		}

		// A half-match was found, sort out the return data.
		if (text1.length > text2.length) {
			return hm;
			//return new String[]{hm[0], hm[1], hm[2], hm[3], hm[4]};
		} else {
			return [hm[2], hm[3], hm[0], hm[1], hm[4]];
		}
	}

	/**
	 * Does a substring of shorttext exist within longtext such that the
	 * substring is at least half the length of longtext?
	 * @param longtext Longer string.
	 * @param shorttext Shorter string.
	 * @param i Start index of quarter length substring within longtext.
	 * @return Five element String array, containing the prefix of longtext, the
	 *     suffix of longtext, the prefix of shorttext, the suffix of shorttext
	 *     and the common middle.  Or null if there was no match.
	 */
	private function diff_halfMatchI(longtext: String, shorttext: String, i: Int) {
		// Start with a 1/4 length substring at position i as a seed.
		var seed = longtext.substring(i, Std.int(i + longtext.length / 4));
		var j = -1;
		var best_common = "";
		var best_longtext_a = "", best_longtext_b = "";
		var best_shorttext_a = "", best_shorttext_b = "";
		while ((j = shorttext.indexOf(seed, j + 1)) != -1) {
			var prefixLength = diff_commonPrefix(longtext.substring(i), shorttext.substring(j));
			var suffixLength = diff_commonSuffix(longtext.substring(0, i), shorttext.substring(0, j));
			if (best_common.length < suffixLength + prefixLength) {
				best_common = shorttext.substring(j - suffixLength, j)
						+ shorttext.substring(j, j + prefixLength);
				best_longtext_a = longtext.substring(0, i - suffixLength);
				best_longtext_b = longtext.substring(i + prefixLength);
				best_shorttext_a = shorttext.substring(0, j - suffixLength);
				best_shorttext_b = shorttext.substring(j + prefixLength);
			}
		}
		if (best_common.length * 2 >= longtext.length) {
			return [best_longtext_a, best_longtext_b, best_shorttext_a, best_shorttext_b, best_common];
		} else {
			return null;
		}
	}

	/**
	 * Reduce the number of edits by eliminating semantically trivial equalities.
	 * @param diffs LinkedList of Diff objects.
	 */
	public function diff_cleanupSemantic(diffs: Array<Diff>) {
		var changes = false;
		var equalities: Map<Int, Int> = new Map();  // Stack of indices where equalities are found.
		var equalitiesLength = 0;  // Keeping our own length var is faster in JS.
		/** @type {?string} */
		var lastequality = null;
		// Always equal to diffs[equalities[equalitiesLength - 1]][1]
		var pointer = 0;  // Index of current position.
		// Number of characters that changed prior to the equality.
		var length_insertions1 = 0;
		var length_deletions1 = 0;
		// Number of characters that changed after the equality.
		var length_insertions2 = 0;
		var length_deletions2 = 0;
		while (pointer < diffs.length) {
			if (diffs[pointer].operation == EQUAL) {  // Equality found.
				equalities[equalitiesLength++] = pointer;
				length_insertions1 = length_insertions2;
				length_deletions1 = length_deletions2;
				length_insertions2 = 0;
				length_deletions2 = 0;
				lastequality = diffs[pointer].text;
			} else {  // An insertion or deletion.
				if (diffs[pointer].operation == INSERT) {
					length_insertions2 += diffs[pointer].text.length;
				} else {
					length_deletions2 += diffs[pointer].text.length;
				}
				// Eliminate an equality that is smaller or equal to the edits on both
				// sides of it.
				if (lastequality != null && (lastequality.length <=
					Math.max(length_insertions1, length_deletions1)) &&
					(lastequality.length <= Math.max(length_insertions2,
													 length_deletions2))) {
					// Duplicate record.
					diffs.insert(equalities[equalitiesLength - 1], new Diff(DELETE, lastequality));
					// Change second copy to insert.
					diffs[equalities[equalitiesLength - 1] + 1].operation = INSERT;
					// Throw away the equality we just deleted.
					equalitiesLength--;
					// Throw away the previous equality (it needs to be reevaluated).
					equalitiesLength--;
					pointer = equalitiesLength > 0 ? equalities[equalitiesLength - 1] : -1;
					length_insertions1 = 0;  // Reset the counters.
					length_deletions1 = 0;
					length_insertions2 = 0;
					length_deletions2 = 0;
					lastequality = null;
					changes = true;
				}
			}
			pointer++;
		}

		// Normalize the diff.
		if (changes) {
			diff_cleanupMerge(diffs);
		}
		diff_cleanupSemanticLossless(diffs);

		// Find any overlaps between deletions and insertions.
		// e.g: <del>abcxxx</del><ins>xxxdef</ins>
		//   -> <del>abc</del>xxx<ins>def</ins>
		// e.g: <del>xxxabc</del><ins>defxxx</ins>
		//   -> <ins>def</ins>xxx<del>abc</del>
		// Only extract an overlap if it is as big as the edit ahead or behind it.
		pointer = 1;
		while (pointer < diffs.length) {
			if (diffs[pointer - 1].operation == DELETE &&
				diffs[pointer].operation == INSERT) {
				var deletion = diffs[pointer - 1].text;
				var insertion = diffs[pointer].text;
				var overlap_length1 = diff_commonOverlap(deletion, insertion);
				var overlap_length2 = diff_commonOverlap(insertion, deletion);
				if (overlap_length1 >= overlap_length2) {
					if (overlap_length1 >= deletion.length / 2 ||
						overlap_length1 >= insertion.length / 2) {
						// Overlap found.  Insert an equality and trim the surrounding edits.
						diffs.insert(pointer, new Diff(EQUAL, insertion.substring(0, overlap_length1)));
						diffs[pointer - 1].text =
							deletion.substring(0, deletion.length - overlap_length1);
						diffs[pointer + 1].text = insertion.substring(overlap_length1);
						pointer++;
					}
				} else {
					if (overlap_length2 >= deletion.length / 2 ||
						overlap_length2 >= insertion.length / 2) {
						// Reverse overlap found.
						// Insert an equality and swap and trim the surrounding edits.
						diffs.insert(pointer, new Diff(EQUAL, deletion.substring(0, overlap_length2)));
						diffs[pointer - 1].operation = INSERT;
						diffs[pointer - 1].text =
							insertion.substring(0, insertion.length - overlap_length2);
						diffs[pointer + 1].operation = DELETE;
						diffs[pointer + 1].text =
							deletion.substring(overlap_length2);
						pointer++;
					}
				}
				pointer++;
			}
			pointer++;
		}
	}

	/**
	 * Look for single edits surrounded on both sides by equalities
	 * which can be shifted sideways to align the edit to a word boundary.
	 * e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
	 * @param diffs LinkedList of Diff objects.
	 */
	public function diff_cleanupSemanticLossless(diffs: Array<Diff>) {
		var pointer = 1;
		// Intentionally ignore the first and last element (don't need checking).
		while (pointer < diffs.length - 1) {
			if (diffs[pointer - 1].operation == EQUAL &&
					diffs[pointer + 1].operation == EQUAL) {
				// This is a single edit surrounded by equalities.
				var equality1 = diffs[pointer - 1].text;
				var edit = diffs[pointer].text;
				var equality2 = diffs[pointer + 1].text;

				// First, shift the edit as far left as possible.
				var commonOffset = diff_commonSuffix(equality1, edit);
				if (commonOffset > 0) {
					var commonString = edit.substring(edit.length - commonOffset);
					equality1 = equality1.substring(0, equality1.length - commonOffset);
					edit = commonString + edit.substring(0, edit.length - commonOffset);
					equality2 = commonString + equality2;
				}

				// Second, step character by character right, looking for the best fit.
				var bestEquality1 = equality1;
				var bestEdit = edit;
				var bestEquality2 = equality2;
				var bestScore = diff_cleanupSemanticScore(equality1, edit) +
						diff_cleanupSemanticScore(edit, equality2);
				while (edit.charAt(0) == equality2.charAt(0)) {
					equality1 += edit.charAt(0);
					edit = edit.substring(1) + equality2.charAt(0);
					equality2 = equality2.substring(1);
					var score = diff_cleanupSemanticScore(equality1, edit) +
							diff_cleanupSemanticScore(edit, equality2);
					// The >= encourages trailing rather than leading whitespace on edits.
					if (score >= bestScore) {
						bestScore = score;
						bestEquality1 = equality1;
						bestEdit = edit;
						bestEquality2 = equality2;
					}
				}

				if (diffs[pointer - 1].text != bestEquality1) {
					// We have an improvement, save it back to the diff.
					if (bestEquality1.length > 0) {
						diffs[pointer - 1].text = bestEquality1;
					} else {
						diffs.splice(pointer - 1, 1);
						pointer--;
					}
					diffs[pointer].text = bestEdit;
					if (bestEquality2.length > 0) {
						diffs[pointer + 1].text = bestEquality2;
					} else {
						diffs.splice(pointer + 1, 1);
						pointer--;
					}
				}
			}
			pointer++;
		}
	}

	/**
	 * Given two strings, compute a score representing whether the internal
	 * boundary falls on logical boundaries.
	 * Scores range from 6 (best) to 0 (worst).
	 * @param one First string.
	 * @param two Second string.
	 * @return The score.
	 */
	private function diff_cleanupSemanticScore(one: String, two: String) {
		if (one.length == 0 || two.length == 0) {
			// Edges are the best.
			return 6;
		}

		// Each port of this function behaves slightly differently due to
		// subtle differences in each language's definition of things like
		// 'whitespace'.  Since this function's purpose is largely cosmetic,
		// the choice has been made to use each language's native features
		// rather than force total conformity.
		var char1 = one.charAt(one.length - 1);
		var char2 = two.charAt(0);
		var nonAlphaNumeric1 = !Character.isLetterOrDigit(char1);
		var nonAlphaNumeric2 = !Character.isLetterOrDigit(char2);
		var whitespace1 = nonAlphaNumeric1 && Character.isWhitespace(char1);
		var whitespace2 = nonAlphaNumeric2 && Character.isWhitespace(char2);
		var lineBreak1 = whitespace1
			&& Character.isLinebreak(char1);
		var lineBreak2 = whitespace2
			&& Character.isLinebreak(char2);
		var blankLine1 = lineBreak1 && Character.endsWithLinebreak(one);
		var blankLine2 = lineBreak2 && Character.startsWithLinebreak(two);

		if (blankLine1 || blankLine2) {
			// Five points for blank lines.
			return 5;
		} else if (lineBreak1 || lineBreak2) {
			// Four points for line breaks.
			return 4;
		} else if (nonAlphaNumeric1 && !whitespace1 && whitespace2) {
			// Three points for end of sentences.
			return 3;
		} else if (whitespace1 || whitespace2) {
			// Two points for whitespace.
			return 2;
		} else if (nonAlphaNumeric1 || nonAlphaNumeric2) {
			// One point for non-alphanumeric.
			return 1;
		}
		return 0;
	}

	/**
	 * Reduce the number of edits by eliminating operationally trivial equalities.
	 * @param diffs LinkedList of Diff objects.
	 */
	public function diff_cleanupEfficiency(diffs: Array<Diff>) {
		if (diffs.length == 0) {
			return;
		}
		var changes = false;
		var equalities = [];  // Stack of indices where equalities are found.
		var equalitiesLength = 0;  // Keeping our own length var is faster in JS.
		/** @type {?string} */
		var lastequality = null;
		// Always equal to diffs[equalities[equalitiesLength - 1]][1]
		var pointer = 0;  // Index of current position.
		// Is there an insertion operation before the last equality.
		var pre_ins = false;
		// Is there a deletion operation before the last equality.
		var pre_del = false;
		// Is there an insertion operation after the last equality.
		var post_ins = false;
		// Is there a deletion operation after the last equality.
		var post_del = false;
		while (pointer < diffs.length) {
			if (diffs[pointer].operation == EQUAL) {  // Equality found.
				if (diffs[pointer].text.length < Diff_EditCost &&
						(post_ins || post_del)) {
					// Candidate found.
					equalities[equalitiesLength++] = pointer;
					pre_ins = post_ins;
					pre_del = post_del;
					lastequality = diffs[pointer].text;
				} else {
					// Not a candidate, and can never become one.
					equalitiesLength = 0;
					lastequality = null;
				}
				post_ins = post_del = false;
			} else {  // An insertion or deletion.
				if (diffs[pointer].operation == DELETE) {
					post_del = true;
				} else {
					post_ins = true;
				}
				/*
				 * Five types to be split:
				 * <ins>A</ins><del>B</del>XY<ins>C</ins><del>D</del>
				 * <ins>A</ins>X<ins>C</ins><del>D</del>
				 * <ins>A</ins><del>B</del>X<ins>C</ins>
				 * <ins>A</del>X<ins>C</ins><del>D</del>
				 * <ins>A</ins><del>B</del>X<del>C</del>
				 */
				if (lastequality != null && ((pre_ins && pre_del && post_ins && post_del) ||
						 ((lastequality.length < Diff_EditCost / 2) && ((pre_ins ? 1 : 0) + (pre_del ? 1 : 0)
												+ (post_ins ? 1 : 0) + (post_del ? 1 : 0)) == 3))) {
					// Duplicate record.
					diffs.insert(equalities[equalitiesLength - 1], new Diff(DELETE, lastequality));
					// Change second copy to insert.
					diffs[equalities[equalitiesLength - 1] + 1].operation = INSERT;
					equalitiesLength--;  // Throw away the equality we just deleted;
					lastequality = null;
					if (pre_ins && pre_del) {
						// No changes made which could affect previous entry, keep going.
						post_ins = post_del = true;
						equalitiesLength = 0;
					} else {
						equalitiesLength--;  // Throw away the previous equality.
						pointer = equalitiesLength > 0 ?
								equalities[equalitiesLength - 1] : -1;
						post_ins = post_del = false;
					}
					changes = true;
				}
			}
			pointer++;
		}

		if (changes) {
			diff_cleanupMerge(diffs);
		}
	}

	/**
	 * Reorder and merge like edit sections.  Merge equalities.
	 * Any edit section can move as long as it doesn't cross an equality.
	 * @param diffs LinkedList of Diff objects.
	 */
	public function diff_cleanupMerge(diffs: Array<Diff>) {
		diffs.push(new Diff(EQUAL, ''));  // Add a dummy entry at the end.
		var pointer = 0;
		var count_delete = 0;
		var count_insert = 0;
		var text_delete = '';
		var text_insert = '';
		var commonlength;
		while (pointer < diffs.length) {
			switch (diffs[pointer].operation) {
				case INSERT:
					count_insert++;
					text_insert += diffs[pointer].text;
					pointer++;
				case DELETE:
					count_delete++;
					text_delete += diffs[pointer].text;
					pointer++;
				case EQUAL:
					// Upon reaching an equality, check for prior redundancies.
					if (count_delete + count_insert > 1) {
						if (count_delete != 0 && count_insert != 0) {
							// Factor out any common prefixies.
							commonlength = diff_commonPrefix(text_insert, text_delete);
							if (commonlength != 0) {
								if ((pointer - count_delete - count_insert) > 0 &&
										diffs[pointer - count_delete - count_insert - 1].operation ==
										EQUAL) {
									diffs[pointer - count_delete - count_insert - 1].text +=
											text_insert.substring(0, commonlength);
								} else {
									diffs.unshift(new Diff(EQUAL, text_insert.substring(0, commonlength)));
									pointer++;
								}
								text_insert = text_insert.substring(commonlength);
								text_delete = text_delete.substring(commonlength);
							}
							// Factor out any common suffixies.
							commonlength = diff_commonSuffix(text_insert, text_delete);
							if (commonlength != 0) {
								diffs[pointer].text = text_insert.substring(text_insert.length - commonlength) + diffs[pointer].text;
								text_insert = text_insert.substring(0, text_insert.length - commonlength);
								text_delete = text_delete.substring(0, text_delete.length - commonlength);
							}
						}
						// Delete the offending records and add the merged ones.
						if (count_delete == 0) {
							diffs.splice(pointer - count_insert, count_delete + count_insert);
							diffs.insert(pointer - count_insert, new Diff(INSERT, text_insert));
						} else if (count_insert == 0) {
							diffs.splice(pointer - count_delete, count_delete + count_insert);
							diffs.insert(pointer - count_delete, new Diff(DELETE, text_delete));
						} else {
							var index = pointer - count_delete - count_insert;
							diffs.splice(index, count_delete + count_insert);
							diffs.insert(index, new Diff(DELETE, text_delete));
							diffs.insert(index + 1, new Diff(INSERT, text_insert));
						}
						pointer = pointer - count_delete - count_insert +
											(count_delete > 0 ? 1 : 0) + (count_insert > 0 ? 1 : 0) + 1;
					} else if (pointer != 0 && diffs[pointer - 1].operation == EQUAL) {
						// Merge this equality with the previous one.
						diffs[pointer - 1].text += diffs[pointer].text;
						diffs.splice(pointer, 1);
					} else {
						pointer++;
					}
					count_insert = 0;
					count_delete = 0;
					text_delete = '';
					text_insert = '';
			}
		}
		if (diffs[diffs.length - 1].text == '') {
			diffs.pop();  // Remove the dummy entry at the end.
		}

		// Second pass: look for single edits surrounded on both sides by equalities
		// which can be shifted sideways to eliminate an equality.
		// e.g: A<ins>BA</ins>C -> <ins>AB</ins>AC
		var changes = false;
		pointer = 1;
		// Intentionally ignore the first and last element (don't need checking).
		while (pointer < diffs.length - 1) {
			if (diffs[pointer - 1].operation == EQUAL &&
					diffs[pointer + 1].operation == EQUAL) {
				// This is a single edit surrounded by equalities.
				if (diffs[pointer].text.substring(diffs[pointer].text.length -
						diffs[pointer - 1].text.length) == diffs[pointer - 1].text) {
					// Shift the edit over the previous equality.
					diffs[pointer].text = diffs[pointer - 1].text +
							diffs[pointer].text.substring(0, diffs[pointer].text.length -
																					diffs[pointer - 1].text.length);
					diffs[pointer + 1].text = diffs[pointer - 1].text + diffs[pointer + 1].text;
					diffs.splice(pointer - 1, 1);
					changes = true;
				} else if (diffs[pointer].text.substring(0, diffs[pointer + 1].text.length) ==
						diffs[pointer + 1].text) {
					// Shift the edit over the next equality.
					diffs[pointer - 1].text += diffs[pointer + 1].text;
					diffs[pointer].text =
							diffs[pointer].text.substring(diffs[pointer + 1].text.length) +
							diffs[pointer + 1].text;
					diffs.splice(pointer + 1, 1);
					changes = true;
				}
			}
			pointer++;
		}
		// If shifts were made, the diff needs reordering and another shift sweep.
		if (changes) {
			diff_cleanupMerge(diffs);
		}
	}

	/**
	 * loc is a location in text1, compute and return the equivalent location in
	 * text2.
	 * e.g. "The cat" vs "The big cat", 1->1, 5->8
	 * @param diffs LinkedList of Diff objects.
	 * @param loc Location within text1.
	 * @return Location within text2.
	 */
	public function diff_xIndex(diffs: Array<Diff>, loc: Int) {
		var chars1 = 0;
		var chars2 = 0;
		var last_chars1 = 0;
		var last_chars2 = 0;
		var lastDiff = null;
		for (aDiff in diffs) {
			if (aDiff.operation != (Operation.INSERT)) {
				// Equality or deletion.
				chars1 += aDiff.text.length;
			}
			if (aDiff.operation != (Operation.DELETE)) {
				// Equality or insertion.
				chars2 += aDiff.text.length;
			}
			if (chars1 > loc) {
				// Overshot the location.
				lastDiff = aDiff;
				break;
			}
			last_chars1 = chars1;
			last_chars2 = chars2;
		}
		if (lastDiff != null && lastDiff.operation == (Operation.DELETE)) {
			// The location was deleted.
			return last_chars2;
		}
		// Add the remaining character length.
		return last_chars2 + (loc - last_chars1);
	}

	/**
	 * Convert a Diff list into a pretty HTML report.
	 * @param diffs LinkedList of Diff objects.
	 * @return HTML representation.
	 */
	public function diff_prettyHtml(diffs: Array<Diff>) {
		var html = new StringBuilder();
		for (aDiff in diffs) {
			var text = aDiff.text.replace("&", "&amp;").replace("<", "&lt;")
					.replace(">", "&gt;").replace("\n", "&para;<br>");
			switch (aDiff.operation) {
			case INSERT:
				html.append("<ins style=\"background:#e6ffe6;\">").append(text)
						.append("</ins>");
			case DELETE:
				html.append("<del style=\"background:#ffe6e6;\">").append(text)
						.append("</del>");
			case EQUAL:
				html.append("<span>").append(text).append("</span>");
			}
		}
		return html.toString();
	}

	/**
	 * Compute and return the source text (all equalities and deletions).
	 * @param diffs LinkedList of Diff objects.
	 * @return Source text.
	 */
	public function diff_text1(diffs: Array<Diff>) {
		var text = new StringBuilder();
		for (aDiff in diffs) {
			if (aDiff.operation != (Operation.INSERT)) {
				text.append(aDiff.text);
			}
		}
		return text.toString();
	}

	/**
	 * Compute and return the destination text (all equalities and insertions).
	 * @param diffs LinkedList of Diff objects.
	 * @return Destination text.
	 */
	public function diff_text2(diffs: Array<Diff>) {
		var text = new StringBuilder();
		for (aDiff in diffs) {
			if (aDiff.operation != (Operation.DELETE)) {
				text.append(aDiff.text);
			}
		}
		return text.toString();
	}

	/**
	 * Compute the Levenshtein distance; the number of inserted, deleted or
	 * substituted characters.
	 * @param diffs LinkedList of Diff objects.
	 * @return Number of changes.
	 */
	public function diff_levenshtein(diffs: Array<Diff>) {
		var levenshtein = 0;
		var insertions = 0;
		var deletions = 0;
		for (aDiff in diffs) {
			switch (aDiff.operation) {
			case INSERT:
				insertions += aDiff.text.length;
			case DELETE:
				deletions += aDiff.text.length;
			case EQUAL:
				// A deletion and an insertion is one substitution.
				levenshtein += Std.int(Math.max(insertions, deletions));
				insertions = 0;
				deletions = 0;
			}
		}
		levenshtein += Std.int(Math.max(insertions, deletions));
		return levenshtein;
	}

	/**
	 * Crush the diff into an encoded string which describes the operations
	 * required to transform text1 into text2.
	 * E.g. =3\t-2\t+ing  -> Keep 3 chars, delete 2 chars, insert 'ing'.
	 * Operations are tab-separated.  Inserted text is escaped using %xx notation.
	 * @param diffs Array of Diff objects.
	 * @return Delta text.
	 */
	public function diff_toDelta(diffs: Array<Diff>) {
		var text = new StringBuilder();
		for (aDiff in diffs) {
			switch (aDiff.operation) {
			case INSERT:
				text.append("+").append(aDiff.text.urlEncode().replace('+', ' ').replace('%20', ' ')).append("\t");
			case DELETE:
				text.append("-").append(Std.string(aDiff.text.length)).append("\t");
			case EQUAL:
				text.append("=").append(Std.string(aDiff.text.length)).append("\t");
			}
		}
		var delta = text.toString();
		if (delta.length != 0) {
			// Strip off trailing tab character.
			delta = delta.substring(0, delta.length - 1);
			delta = unescapeForEncodeUriCompatability(delta);
		}
		return delta;
	}

	/**
	 * Given the original text1, and an encoded string which describes the
	 * operations required to transform text1 into text2, compute the full diff.
	 * @param text1 Source string for the diff.
	 * @param delta Delta text.
	 * @return Array of Diff objects or null if invalid.
	 * @throws IllegalArgumentException If invalid input.
	 */
	public function diff_fromDelta(text1: String, delta: String) {
		var diffs = [];
		var pointer = 0;  // Cursor in text1
		var tokens = delta.split("\t");
		for (token in tokens) {
			if (token.length == 0) {
				// Blank tokens are ok (from a trailing \t).
				continue;
			}
			// Each token begins with a one character parameter which specifies the
			// operation of this token (delete, insert, equality).
			var param = token.substring(1);
			switch (token.charAt(0)) {
			case '+':
				// decode would change all "+" to " "
				param = param.replace("+", "%2B");
				param = param.urlDecode();
				diffs.push(new Diff(Operation.INSERT, param));
			case '-' | '=':
				var n = Std.parseInt(param);
				if (n == null)
					throw "Invalid number in diff_fromDelta: " + param;
				if (n < 0)
					throw "Negative number in diff_fromDelta: " + param;
				var text;
				if (pointer > text1.length)
					throw "Delta length (" + pointer
							+ ") larger than source text length (" + text1.length
							+ ").";
				text = text1.substring(pointer, pointer += n);
				if (token.charAt(0) == '=') {
					diffs.push(new Diff(Operation.EQUAL, text));
				} else {
					diffs.push(new Diff(Operation.DELETE, text));
				}
			default:
				// Anything else is an error.
				throw "Invalid diff operation in diff_fromDelta: " + token.charAt(0);
			}
		}
		if (pointer != text1.length) {
			throw "Delta length (" + pointer
					+ ") smaller than source text length (" + text1.length + ").";
		}
		return diffs;
	}


	//  MATCH FUNCTIONS


	/**
	 * Locate the best instance of 'pattern' in 'text' near 'loc'.
	 * Returns -1 if no match found.
	 * @param text The text to search.
	 * @param pattern The pattern to search for.
	 * @param loc The location to search around.
	 * @return Best match index or -1.
	 */
	public function match_main(text: String, pattern: String, loc: Int) {
		// Check for null inputs.
		if (text == null || pattern == null) {
			throw "Null inputs. (match_main)";
		}

		loc = Std.int(Math.max(0, Math.min(loc, text.length)));
		if (text == pattern) {
			// Shortcut (potentially not guaranteed by the algorithm)
			return 0;
		} else if (text.length == 0) {
			// Nothing to match.
			return -1;
		} else if (loc + pattern.length <= text.length
				&& text.substring(loc, loc + pattern.length) == pattern) {
			// Perfect match at the perfect spot!  (Includes case of null pattern)
			return loc;
		} else {
			// Do a fuzzy compare.
			return match_bitap(text, pattern, loc);
		}
	}

	/**
	 * Locate the best instance of 'pattern' in 'text' near 'loc' using the
	 * Bitap algorithm.  Returns -1 if no match found.
	 * @param text The text to search.
	 * @param pattern The pattern to search for.
	 * @param loc The location to search around.
	 * @return Best match index or -1.
	 */
	private function match_bitap(text: String, pattern: String, loc: Int) {
		if (Match_MaxBits != 0 && pattern.length > Match_MaxBits)
				throw "Pattern too long for this application.";

		// Initialise the alphabet.
		var s: Map<String, Int> = match_alphabet(pattern);

		// Highest score beyond which we give up.
		var score_threshold = Match_Threshold;
		// Is there a nearby exact match? (speedup)
		var best_loc = text.indexOf(pattern, loc);
		if (best_loc != -1) {
			score_threshold = Math.min(match_bitapScore(0, best_loc, loc, pattern),
					score_threshold);
			// What about in the other direction? (speedup)
			best_loc = text.lastIndexOf(pattern, loc + pattern.length);
			if (best_loc != -1) {
				score_threshold = Math.min(match_bitapScore(0, best_loc, loc, pattern),
						score_threshold);
			}
		}

		// Initialise the bit arrays.
		var matchmask = 1 << (pattern.length - 1);
		best_loc = -1;

		var bin_min, bin_mid;
		var bin_max = pattern.length + text.length;
		// Empty initialization added to appease Java compiler.
		var last_rd = [];
		for (d in 0 ... pattern.length) {
			// Scan for the best match; each iteration allows for one more error.
			// Run a binary search to determine how far from 'loc' we can stray at
			// this error level.
			bin_min = 0;
			bin_mid = bin_max;
			while (bin_min < bin_mid) {
				if (match_bitapScore(d, loc + bin_mid, loc, pattern)
						<= score_threshold) {
					bin_min = bin_mid;
				} else {
					bin_max = bin_mid;
				}
				bin_mid = Std.int((bin_max - bin_min) / 2 + bin_min);
			}
			// Use the result from this iteration as the maximum for the next.
			bin_max = bin_mid;
			var start = Std.int(Math.max(1, loc - bin_mid + 1));
			var finish = Std.int(Math.min(loc + bin_mid, text.length) + pattern.length);

			var rd = [];//new int[finish + 2];
			rd[finish + 1] = (1 << d) - 1;
			var j = finish;
			while (j >= start) {
				var charMatch;
				if (text.length <= j - 1 || !s.exists(text.charAt(j - 1))) {
					// Out of range.
					charMatch = 0;
				} else {
					charMatch = s.get(text.charAt(j - 1));
				}
				if (d == 0) {
					// First pass: exact match.
					rd[j] = ((rd[j + 1] << 1) | 1) & charMatch;
				} else {
					// Subsequent passes: fuzzy match.
					rd[j] = (((rd[j + 1] << 1) | 1) & charMatch)
							| (((last_rd[j + 1] | last_rd[j]) << 1) | 1) | last_rd[j + 1];
				}
				if ((rd[j] & matchmask) != 0) {
					var score = match_bitapScore(d, j - 1, loc, pattern);
					// This match will almost certainly be better than any existing
					// match.  But check anyway.
					if (score <= score_threshold) {
						// Told you so.
						score_threshold = score;
						best_loc = j - 1;
						if (best_loc > loc) {
							// When passing loc, don't exceed our current distance from loc.
							start = Std.int(Math.max(1, 2 * loc - best_loc));
						} else {
							// Already passed loc, downhill from here on in.
							break;
						}
					}
				}
		j--;
			}
			if (match_bitapScore(d + 1, loc, loc, pattern) > score_threshold) {
				// No hope for a (better) match at greater error levels.
				break;
			}
			last_rd = rd;
		}
		return best_loc;
	}

	/**
	 * Compute and return the score for a match with e errors and x location.
	 * @param e Number of errors in match.
	 * @param x Location of match.
	 * @param loc Expected location of match.
	 * @param pattern Pattern being sought.
	 * @return Overall score for match (0.0 = good, 1.0 = bad).
	 */
	private function match_bitapScore(e: Int, x: Int, loc: Int, pattern: String) {
		var accuracy = e / pattern.length;
		var proximity = Math.abs(loc - x);
		if (Match_Distance == 0) {
			// Dodge divide by zero error.
			return proximity == 0 ? accuracy : 1.0;
		}
		return accuracy + (proximity / Match_Distance);
	}

	/**
	 * Initialise the alphabet for the Bitap algorithm.
	 * @param pattern The text to encode.
	 * @return Hash of character locations.
	 */
	private function match_alphabet(pattern: String): Map<String, Int> {
		var s = new Map<String, Int>();
		var char_pattern = pattern.split('');
		for (c in char_pattern) {
			s.set(c, 0);
		}
		var i = 0;
		for (c in char_pattern) {
			s.set(c, s.get(c) | (1 << (pattern.length - i - 1)));
			i++;
		}
		return s;
	}


	//  PATCH FUNCTIONS


	/**
	 * Increase the context until it is unique,
	 * but don't let the pattern expand beyond Match_MaxBits.
	 * @param patch The patch to grow.
	 * @param text Source text.
	 */
	private function patch_addContext(patch: Patch, text: String) {
		if (text.length == 0) {
			return;
		}
		var pattern = text.substring(patch.start2, patch.start2 + patch.length1);
		var padding = 0;

		// Look for the first and last matches of pattern in text.  If two different
		// matches are found, increase the pattern length.
		while ((pattern.length == 0 || text.indexOf(pattern) != text.lastIndexOf(pattern))
				&& pattern.length < Match_MaxBits - Patch_Margin - Patch_Margin) {
			padding += Patch_Margin;
			pattern = text.substring(Std.int(Math.max(0, patch.start2 - padding)),
					Std.int(Math.min(text.length, patch.start2 + patch.length1 + padding)));
		}
		// Add one chunk for good luck.
		padding += Patch_Margin;

		// Add the prefix.
		var prefix = text.substring(Std.int(Math.max(0, patch.start2 - padding)),
				patch.start2);
		if (prefix.length != 0) {
			patch.diffs.unshift(new Diff(Operation.EQUAL, prefix));
		}
		// Add the suffix.
		var suffix = text.substring(patch.start2 + patch.length1,
				Std.int(Math.min(text.length, patch.start2 + patch.length1 + padding)));
		if (suffix.length != 0) {
			patch.diffs.push(new Diff(Operation.EQUAL, suffix));
		}

		// Roll back the start points.
		patch.start1 -= prefix.length;
		patch.start2 -= prefix.length;
		// Extend the lengths.
		patch.length1 += prefix.length + suffix.length;
		patch.length2 += prefix.length + suffix.length;
	}

	/**
	 * Compute a list of patches to turn text1 into text2.
	 * text2 is not provided, diffs are the delta between text1 and text2.
	 * @param text1 Old text.
	 * @param diffs Array of Diff objects for text1 to text2.
	 * @return LinkedList of Patch objects.
	 */
	public function patch_make(?text1: String, ?text2: String, ?diffs: Array<Diff>) {
		if (text1 == null && text2 == null && diffs != null) {
			text1 = diff_text1(diffs);
		} else if (text1 != null && text2 != null) {
			diffs = diff_main(text1, text2, true);
			if (diffs.length > 2) {
				diff_cleanupSemantic(diffs);
				diff_cleanupEfficiency(diffs);
			}
		} else if (!(text1 != null && diffs != null)) {
			throw "Null inputs. (patch_make)";
		}

		var patches = [];
		if (diffs.length == 0) {
			return patches;  // Get rid of the null case.
		}
		var patch = new Patch();
		var char_count1 = 0;  // Number of characters into the text1 string.
		var char_count2 = 0;  // Number of characters into the text2 string.
		// Start with text1 (prepatch_text) and apply the diffs until we arrive at
		// text2 (postpatch_text). We recreate the patches one by one to determine
		// context info.
		var prepatch_text = text1;
		var postpatch_text = text1;
		for (aDiff in diffs) {
			if (patch.diffs.length == 0 && aDiff.operation != (Operation.EQUAL)) {
				// A new patch starts here.
				patch.start1 = char_count1;
				patch.start2 = char_count2;
			}

			switch (aDiff.operation) {
			case INSERT:
				patch.diffs.push(aDiff);
				patch.length2 += aDiff.text.length;
				postpatch_text = postpatch_text.substring(0, char_count2)
						+ aDiff.text + postpatch_text.substring(char_count2);
			case DELETE:
				patch.length1 += aDiff.text.length;
				patch.diffs.push(aDiff);
				postpatch_text = postpatch_text.substring(0, char_count2)
						+ postpatch_text.substring(char_count2 + aDiff.text.length);
			case EQUAL:
				if (aDiff.text.length <= 2 * Patch_Margin
						&& patch.diffs.length != 0 && aDiff != diffs[diffs.length-1]) {
					// Small equality inside a patch.
					patch.diffs.push(aDiff);
					patch.length1 += aDiff.text.length;
					patch.length2 += aDiff.text.length;
				}

				if (aDiff.text.length >= 2 * Patch_Margin) {
					// Time for a new patch.
					if (patch.diffs.length > 0) {
						patch_addContext(patch, prepatch_text);
						patches.push(patch);
						patch = new Patch();
						// Unlike Unidiff, our patch lists have a rolling context.
						// http://code.google.com/p/google-diff-match-patch/wiki/Unidiff
						// Update prepatch text & pos to reflect the application of the
						// just completed patch.
						prepatch_text = postpatch_text;
						char_count1 = char_count2;
					}
				}
			}

			// Update the current character count.
			if (aDiff.operation != (Operation.INSERT)) {
				char_count1 += aDiff.text.length;
			}
			if (aDiff.operation != (Operation.DELETE)) {
				char_count2 += aDiff.text.length;
			}
		}
		// Pick up the leftover patch if not empty.
		if (patch.diffs.length > 0) {
			patch_addContext(patch, prepatch_text);
			patches.push(patch);
		}

		return patches;
	}

	/**
	 * Given an array of patches, return another array that is identical.
	 * @param patches Array of Patch objects.
	 * @return Array of Patch objects.
	 */
	public function patch_deepCopy(patches: Array<Patch>) {
		var patchesCopy = [];
		for (aPatch in patches) {
			var patchCopy = new Patch();
			for (aDiff in aPatch.diffs) {
				var diffCopy = new Diff(aDiff.operation, aDiff.text);
				patchCopy.diffs.push(diffCopy);
			}
			patchCopy.start1 = aPatch.start1;
			patchCopy.start2 = aPatch.start2;
			patchCopy.length1 = aPatch.length1;
			patchCopy.length2 = aPatch.length2;
			patchesCopy.push(patchCopy);
		}
		return patchesCopy;
	}

	/**
	 * Merge a set of patches onto the text.  Return a patched text, as well
	 * as an array of true/false values indicating which patches were applied.
	 * @param patches Array of Patch objects
	 * @param text Old text.
	 * @return Two element Object array, containing the new text and an array of
	 *      boolean values.
	 */
	public function patch_apply(patches: Array<Patch>, text: String): {text: String, applied: Array<Bool>} {
		if (patches.length == 0) {
			return {text: text, applied: []};
		}

		// Deep copy the patches so that no changes are made to originals.
		patches = [for (patch in patches) patch.copy()];

		var nullPadding = patch_addPadding(patches);
		text = nullPadding + text + nullPadding;
		patch_splitMax(patches);

		var x = 0;
		// delta keeps track of the offset between the expected and actual location
		// of the previous patch.  If there are patches expected at positions 10 and
		// 20, but the first patch was found at 12, delta is 2 and the second patch
		// has an effective expected position of 22.
		var delta = 0;
		var results = [];
		for (aPatch in patches) {
			var expected_loc = aPatch.start2 + delta;
			var text1 = diff_text1(aPatch.diffs);
			var start_loc;
			var end_loc = -1;
			if (text1.length > Match_MaxBits) {
				// patch_splitMax will only provide an oversized pattern in the case of
				// a monster delete.
				start_loc = match_main(text,
						text1.substring(0, Match_MaxBits), expected_loc);
				if (start_loc != -1) {
					end_loc = match_main(text,
							text1.substring(text1.length - Match_MaxBits),
							expected_loc + text1.length - Match_MaxBits);
					if (end_loc == -1 || start_loc >= end_loc) {
						// Can't find valid trailing context.  Drop this patch.
						start_loc = -1;
					}
				}
			} else {
				start_loc = match_main(text, text1, expected_loc);
			}
			if (start_loc == -1) {
				// No match found.  :(
				results[x] = false;
				// Subtract the delta for this failed patch from subsequent patches.
				delta -= aPatch.length2 - aPatch.length1;
			} else {
				// Found a match.  :)
				results[x] = true;
				delta = start_loc - expected_loc;
				var text2;
				if (end_loc == -1) {
					text2 = text.substring(start_loc,
							Std.int(Math.min(start_loc + text1.length, text.length)));
				} else {
					text2 = text.substring(start_loc,
							Std.int(Math.min(end_loc + Match_MaxBits, text.length)));
				}
				if (text1 == text2) {
					// Perfect match, just shove the replacement text in.
					text = text.substring(0, start_loc) + diff_text2(aPatch.diffs)
							+ text.substring(start_loc + text1.length);
				} else {
					// Imperfect match.  Run a diff to get a framework of equivalent
					// indices.
					var diffs = diff_main(text1, text2, false);
					if (text1.length > Match_MaxBits
							&& diff_levenshtein(diffs) / text1.length
							> Patch_DeleteThreshold) {
						// The end points match, but the content is unacceptably bad.
						results[x] = false;
					} else {
						diff_cleanupSemanticLossless(diffs);
						var index1 = 0;
						for (aDiff in aPatch.diffs) {
							if (aDiff.operation != (Operation.EQUAL)) {
								var index2 = diff_xIndex(diffs, index1);
								if (aDiff.operation == (Operation.INSERT)) {
									// Insertion
									text = text.substring(0, start_loc + index2) + aDiff.text
											+ text.substring(start_loc + index2);
								} else if (aDiff.operation == (Operation.DELETE)) {
									// Deletion
									text = text.substring(0, start_loc + index2)
											+ text.substring(start_loc + diff_xIndex(diffs,
											index1 + aDiff.text.length));
								}
							}
							if (aDiff.operation != (Operation.DELETE)) {
								index1 += aDiff.text.length;
							}
						}
					}
				}
			}
			x++;
		}
		// Strip the padding off.
		text = text.substring(nullPadding.length, text.length
				- nullPadding.length);
		return {text: text, applied: results};
	}

	/**
	 * Add some padding on text start and end so that edges can match something.
	 * Intended to be called only from within patch_apply.
	 * @param patches Array of Patch objects.
	 * @return The padding string added to each side.
	 */
	public function patch_addPadding(patches: Array<Patch>) {
		var paddingLength = Patch_Margin;
		var nullPadding = "";
		var x = 1;
		while (x <= paddingLength) {
			var b = new StringBuf();
			b.addChar(x);
			nullPadding += b;
			x++;
		}

		// Bump all the patches forward.
		for (aPatch in patches) {
			aPatch.start1 += paddingLength;
			aPatch.start2 += paddingLength;
		}

		// Add some padding on start of first diff.
		var patch = patches[0];
		var diffs = patch.diffs;
		if (diffs.length == 0 || diffs[0].operation != (Operation.EQUAL)) {
			// Add nullPadding equality.
			diffs.unshift(new Diff(Operation.EQUAL, nullPadding));
			patch.start1 -= paddingLength;  // Should be 0.
			patch.start2 -= paddingLength;  // Should be 0.
			patch.length1 += paddingLength;
			patch.length2 += paddingLength;
		} else if (paddingLength > diffs[0].text.length) {
			// Grow first equality.
			var firstDiff = diffs[0];
			var extraLength = paddingLength - firstDiff.text.length;
			firstDiff.text = nullPadding.substring(firstDiff.text.length)
					+ firstDiff.text;
			patch.start1 -= extraLength;
			patch.start2 -= extraLength;
			patch.length1 += extraLength;
			patch.length2 += extraLength;
		}

		// Add some padding on end of last diff.
		patch = patches[patches.length-1];
		diffs = patch.diffs;
		if (diffs.length == 0 || diffs[diffs.length-1].operation != (Operation.EQUAL)) {
			// Add nullPadding equality.
			diffs.push(new Diff(Operation.EQUAL, nullPadding));
			patch.length1 += paddingLength;
			patch.length2 += paddingLength;
		} else if (paddingLength > diffs[diffs.length-1].text.length) {
			// Grow last equality.
			var lastDiff = diffs[diffs.length-1];
			var extraLength = paddingLength - lastDiff.text.length;
			lastDiff.text += nullPadding.substring(0, extraLength);
			patch.length1 += extraLength;
			patch.length2 += extraLength;
		}

		return nullPadding;
	}

	/**
	 * Look through the patches and break up any which are longer than the
	 * maximum limit of the match algorithm.
	 * Intended to be called only from within patch_apply.
	 * @param patches LinkedList of Patch objects.
	 */
	public function patch_splitMax(patches: Array<Patch>) {
		var patch_size = Match_MaxBits;
		var x = 0;
		while (x < patches.length) {
			if (patches[x].length1 <= patch_size) {
				x++;
				continue;
			}
			var bigpatch = patches[x];
			// Remove the big old patch.
			patches.splice(x--, 1);
			var start1 = bigpatch.start1;
			var start2 = bigpatch.start2;
			var precontext = '';
			while (bigpatch.diffs.length != 0) {
				// Create one of several smaller patches.
				var patch = new Patch();
				var empty = true;
				patch.start1 = start1 - precontext.length;
				patch.start2 = start2 - precontext.length;
				if (precontext != '') {
					patch.length1 = patch.length2 = precontext.length;
					patch.diffs.push(new Diff(EQUAL, precontext));
				}
				while (bigpatch.diffs.length != 0 &&
							 patch.length1 < patch_size - Patch_Margin) {
					var diff_type = bigpatch.diffs[0].operation;
					var diff_text = bigpatch.diffs[0].text;
					if (diff_type == INSERT) {
						// Insertions are harmless.
						patch.length2 += diff_text.length;
						start2 += diff_text.length;
						patch.diffs.push(bigpatch.diffs.shift());
						empty = false;
					} else if (diff_type == DELETE && patch.diffs.length == 1 &&
										 patch.diffs[0].operation == EQUAL &&
										 diff_text.length > 2 * patch_size) {
						// This is a large deletion.  Let it pass in one chunk.
						patch.length1 += diff_text.length;
						start1 += diff_text.length;
						empty = false;
						patch.diffs.push(new Diff(diff_type, diff_text));
						bigpatch.diffs.shift();
					} else {
						// Deletion or equality.  Only take as much as we can stomach.
						diff_text = diff_text.substring(0,
								patch_size - patch.length1 - this.Patch_Margin);
						patch.length1 += diff_text.length;
						start1 += diff_text.length;
						if (diff_type == EQUAL) {
							patch.length2 += diff_text.length;
							start2 += diff_text.length;
						} else {
							empty = false;
						}
						patch.diffs.push(new Diff(diff_type, diff_text));
						if (diff_text == bigpatch.diffs[0].text) {
							bigpatch.diffs.shift();
						} else {
							bigpatch.diffs[0].text =
									bigpatch.diffs[0].text.substring(diff_text.length);
						}
					}
				}
				// Compute the head context for the next patch.
				precontext = diff_text2(patch.diffs);
				precontext =
						precontext.substring(precontext.length - Patch_Margin);
				// Append the end context for this patch.
				var postcontext = diff_text1(bigpatch.diffs)
										.substring(0, Patch_Margin);
				if (postcontext != '') {
					patch.length1 += postcontext.length;
					patch.length2 += postcontext.length;
					if (patch.diffs.length != 0 &&
							patch.diffs[patch.diffs.length - 1].operation == EQUAL) {
						patch.diffs[patch.diffs.length - 1].text += postcontext;
					} else {
						patch.diffs.push(new Diff(EQUAL, postcontext));
					}
				}
				if (!empty) {
					patches.insert(++x, patch);
				}
			}
			x++;
		}
	}

	/**
	 * Take a list of patches and return a textual representation.
	 * @param patches List of Patch objects.
	 * @return Text representation of patches.
	 */
	public function patch_toText(patches: Array<Patch>) {
		var text = new StringBuilder();
		for (aPatch in patches) {
			text.append(aPatch.toString());
		}
		return text.toString();
	}

	/**
	 * Parse a textual representation of patches and return a List of Patch
	 * objects.
	 * @param textline Text representation of patches.
	 * @return List of Patch objects.
	 * @throws IllegalArgumentException If invalid input.
	 */
	public function patch_fromText(textline: String) {
		var patches = [];
		if (textline.length == 0) {
			return patches;
		}
		var text = textline.split("\n");
		var patch;
		var m = ~/^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@$/;
		var sign;
		var line;
		while (text.length > 0) {
			if (!m.match(text[0])) {
				throw "Invalid patch string: " + text[0];
			}
			patch = new Patch();
			patches.push(patch);
			patch.start1 = Std.parseInt(m.matched(1));
			if (m.matched(2).length == 0) {
				patch.start1--;
				patch.length1 = 1;
			} else if (m.matched(2) == "0") {
				patch.length1 = 0;
			} else {
				patch.start1--;
				patch.length1 = Std.parseInt(m.matched(2));
			}

			patch.start2 = Std.parseInt(m.matched(3));
			if (m.matched(4).length == 0) {
				patch.start2--;
				patch.length2 = 1;
			} else if (m.matched(4) == "0") {
				patch.length2 = 0;
			} else {
				patch.start2--;
				patch.length2 = Std.parseInt(m.matched(4));
			}
			text.shift();

			while (text.length > 0) {
				sign = text[0].charAt(0);
				if (sign == '') {
					text.shift();
					continue;
				}
				line = text[0].substring(1);
				line = line.replace("+", "%2B");  // decode would change all "+" to " "
				line = line.urlDecode();

				if (sign == '-') {
					// Deletion.
					patch.diffs.push(new Diff(Operation.DELETE, line));
				} else if (sign == '+') {
					// Insertion.
					patch.diffs.push(new Diff(Operation.INSERT, line));
				} else if (sign == ' ') {
					// Minor equality.
					patch.diffs.push(new Diff(Operation.EQUAL, line));
				} else if (sign == '@') {
					// Start of next patch.
					break;
				} else {
					// WTF?
					throw "Invalid patch mode '" + sign + "' in: " + line;
				}
				text.shift();
			}
		}
		return patches;
	}
	
	/**
	 * Unescape selected chars for compatability with JavaScript's encodeURI.
	 * In speed critical applications this could be dropped since the
	 * receiving application will certainly decode these fine.
	 * Note that this function is case-sensitive.  Thus "%3f" would not be
	 * unescaped.  But this is ok because it is only called with the output of
	 * URLEncoder.encode which returns uppercase hex.
	 *
	 * Example: "%3F" -> "?", "%24" -> "$", etc.
	 *
	 * @param str The string to escape.
	 * @return The escaped string.
	 */
	public static function unescapeForEncodeUriCompatability(str: String) {
		return str.replace("%21", "!").replace("%7E", "~")
				.replace("%27", "'").replace("%28", "(").replace("%29", ")")
				.replace("%3B", ";").replace("%2F", "/").replace("%3F", "?")
				.replace("%3A", ":").replace("%40", "@").replace("%26", "&")
				.replace("%3D", "=").replace("%2B", "+").replace("%24", "$")
				.replace("%2C", ",").replace("%23", "#").replace("%2A", "*");
	}
}

/**
 * Class representing one diff operation.
 */
class Diff {
	/**
	 * One of: INSERT, DELETE or EQUAL.
	 */
	public var operation: Operation;
	/**
	 * The text associated with this diff operation.
	 */
	public var text: String;

	/**
	 * Constructor.  Initializes the diff with the provided values.
	 * @param operation One of INSERT, DELETE or EQUAL.
	 * @param text The text being applied.
	 */
	public function new(operation: Operation, text: String, ?pos: PosInfos) {
		// Construct a diff with the specified operation and text.
		this.operation = operation;
		this.text = text;
	}

	/**
	 * Display a human-readable version of this Diff.
	 * @return text version.
	 */
	public function toString() {
		var prettyText = this.text.replace('\n', '\u00b6');
		return "Diff(" + this.operation + ",\"" + prettyText + "\")";
	}
	
	public function copy() {
		return new Diff(operation, text);
	}

	/**
	 * Is this Diff equivalent to another Diff?
	 * @param obj Another Diff to compare against.
	 * @return true or false.
	 */
	public function equals(obj: Diff) {
		if (this == obj) {
			return true;
		}
		if (obj == null) {
			return false;
		}
		var other = obj;
		if (operation != other.operation) {
			return false;
		}
		if (text == null) {
			if (other.text != null) {
				return false;
			}
		} else if (text != other.text) {
			return false;
		}
		return true;
	}
}


/**
 * Class representing one patch operation.
 */
class Patch {
	public var diffs: Array<Diff>;
	public var start1: Int = 0;
	public var start2: Int = 0;
	public var length1: Int = 0;
	public var length2: Int = 0;

	/**
	 * Constructor.  Initializes with an empty list of diffs.
	 */
	public function new() {
		this.diffs = [];
	}
	
	public function copy() {
		var p = new Patch();
		p.start1 = start1;
		p.start2 = start2;
		p.length1 = length1;
		p.length2 = length2;
		p.diffs = [for (diff in diffs) 
			diff.copy()
		];
		return p;
	}

	/**
	 * Emmulate GNU diff's format.
	 * Header: @@ -382,8 +481,9 @@
	 * Indicies are printed as 1-based, not 0-based.
	 * @return The GNU diff string.
	 */
	public function toString() {
		var coords1, coords2;
		if (this.length1 == 0) {
			coords1 = this.start1 + ",0";
		} else if (this.length1 == 1) {
			coords1 = Std.string(this.start1 + 1);
		} else {
			coords1 = (this.start1 + 1) + "," + this.length1;
		}
		if (this.length2 == 0) {
			coords2 = this.start2 + ",0";
		} else if (this.length2 == 1) {
			coords2 = Std.string(this.start2 + 1);
		} else {
			coords2 = (this.start2 + 1) + "," + this.length2;
		}
		var text = new StringBuilder();
		text.append("@@ -").append(coords1).append(" +").append(coords2)
				.append(" @@\n");
		// Escape the body of the patch with %xx notation.
		for (aDiff in this.diffs) {
			switch (aDiff.operation) {
			case INSERT:
				text.append('+');
			case DELETE:
				text.append('-');
			case EQUAL:
				text.append(' ');
			}
				text.append(aDiff.text.urlEncode().replace('+', ' ').replace('%20', ' '))
						.append("\n");
		}
		return DiffMatchPatch.unescapeForEncodeUriCompatability(text.toString());
	}
}