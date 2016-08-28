/*
 * Test harness for diff_match_patch.java
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

import dmp.DiffMatchPatch;
import haxe.PosInfos;
import haxe.unit.TestCase;

@:access(DiffMatchPatch)
class RunTests extends TestCase {
	
	static function main() {
		var r = new haxe.unit.TestRunner();
		r.add(new RunTests());
		r.run();
	}

	var dmp = new DiffMatchPatch();
	
	function assert<T>(description, expected: T, actual: T, ?c: PosInfos) {
		assertEquals(expected, actual, c);
	}
	
	function assertArrayEquals<T>(description, expected: Array<T>, actual: Array<T>, ?c: PosInfos) {
		for (i in 0 ... expected.length) 
			assert(description, expected[i], actual[i], c);
	}
	
	function assertMap<T, V>(description, expected: Map<T, V>, actual: Map<T, V>, ?c: PosInfos) {
		for (key in expected.keys()) 
			assert(description, expected.get(key), actual.get(key), c);
	}
	
	function assertDiffs(description, expected: Array<Diff>, actual: Array<Diff>, ?c: PosInfos) {
		currentTest.done = true;
		for (i in 0 ... expected.length) 
			if (expected[i].equals(actual[i]) != true){
				currentTest.success = false;
				currentTest.error   = description+"\nexpected: "+expected+"\nactual: "+actual;
				currentTest.posInfos = c;
				throw currentTest;
			}
	}
	
	function assertLinesToCharsResultEquals(description, a: LinesToCharsResult, b: LinesToCharsResult, ?c: PosInfos) {
		assertEquals(a.chars1, b.chars1);
		assertEquals(a.chars2, b.chars2);
		assertArrayEquals(description, a.lineArray, b.lineArray, c);
	}
	
	function fail(description, ?c: PosInfos) {
		currentTest.done = true;
		currentTest.success = false;
		currentTest.error = description;
		currentTest.posInfos = c;
	}

	//  DIFF TEST FUNCTIONS
	public function testDiffCommonPrefix() {
		// Detect any common prefix.
		assert("diff_commonPrefix: Null case.", 0, dmp.diff_commonPrefix("abc", "xyz"));

		assert("diff_commonPrefix: Non-null case.", 4, dmp.diff_commonPrefix("1234abcdef", "1234xyz"));

		assert("diff_commonPrefix: Whole case.", 4, dmp.diff_commonPrefix("1234", "1234xyz"));
	}
	

	public function testDiffCommonSuffix() {
		// Detect any common suffix.
		assert("diff_commonSuffix: Null case.", 0, dmp.diff_commonSuffix("abc", "xyz"));

		assert("diff_commonSuffix: Non-null case.", 4, dmp.diff_commonSuffix("abcdef1234", "xyz1234"));

		assert("diff_commonSuffix: Whole case.", 4, dmp.diff_commonSuffix("1234", "xyz1234"));
	}

	public function testDiffCommonOverlap() {
		// Detect any suffix/prefix overlap.
		assert("diff_commonOverlap: Null case.", 0, dmp.diff_commonOverlap("", "abcd"));

		assert("diff_commonOverlap: Whole case.", 3, dmp.diff_commonOverlap("abc", "abcd"));

		assert("diff_commonOverlap: No overlap.", 0, dmp.diff_commonOverlap("123456", "abcd"));

		assert("diff_commonOverlap: Overlap.", 3, dmp.diff_commonOverlap("123456xxx", "xxxabcd"));

		// Some overly clever languages (C#) may treat ligatures as equal to their
		// component letters.  E.g. U+FB01 == 'fi'
		assert("diff_commonOverlap: Unicode.", 0, dmp.diff_commonOverlap("fi", "\ufb01i"));
	}

	public function testDiffHalfmatch() {
		// Detect a halfmatch.
		dmp.Diff_Timeout = 1;
		assert("diff_halfMatch: No match #1.", null, dmp.diff_halfMatch("1234567890", "abcdef"));

		assert("diff_halfMatch: No match #2.", null, dmp.diff_halfMatch("12345", "23"));

		assertArrayEquals("diff_halfMatch: Single Match #1.", ["12", "90", "a", "z", "345678"], dmp.diff_halfMatch("1234567890", "a345678z"));

		assertArrayEquals("diff_halfMatch: Single Match #2.", ["a", "z", "12", "90", "345678"], dmp.diff_halfMatch("a345678z", "1234567890"));

		assertArrayEquals("diff_halfMatch: Single Match #3.", ["abc", "z", "1234", "0", "56789"], dmp.diff_halfMatch("abc56789z", "1234567890"));

		assertArrayEquals("diff_halfMatch: Single Match #4.", ["a", "xyz", "1", "7890", "23456"], dmp.diff_halfMatch("a23456xyz", "1234567890"));

		assertArrayEquals("diff_halfMatch: Multiple Matches #1.", ["12123", "123121", "a", "z", "1234123451234"], dmp.diff_halfMatch("121231234123451234123121", "a1234123451234z"));

		assertArrayEquals("diff_halfMatch: Multiple Matches #2.", ["", "-=-=-=-=-=", "x", "", "x-=-=-=-=-=-=-="], dmp.diff_halfMatch("x-=-=-=-=-=-=-=-=-=-=-=-=", "xx-=-=-=-=-=-=-="));

		assertArrayEquals("diff_halfMatch: Multiple Matches #3.", ["-=-=-=-=-=", "", "", "y", "-=-=-=-=-=-=-=y"], dmp.diff_halfMatch("-=-=-=-=-=-=-=-=-=-=-=-=y", "-=-=-=-=-=-=-=yy"));

		// Optimal diff would be -q+x=H-i+e=lloHe+Hu=llo-Hew+y not -qHillo+x=HelloHe-w+Hulloy
		assertArrayEquals("diff_halfMatch: Non-optimal halfmatch.", ["qHillo", "w", "x", "Hulloy", "HelloHe"], dmp.diff_halfMatch("qHilloHelloHew", "xHelloHeHulloy"));

		dmp.Diff_Timeout = 0;
		assert("diff_halfMatch: Optimal no halfmatch.", null, dmp.diff_halfMatch("qHilloHelloHew", "xHelloHeHulloy"));
	}

	public function testDiffLinesToChars() {
		// Convert lines down to characters.
		assertLinesToCharsResultEquals(
			"diff_linesToChars: Shared lines.", 
			{chars1: "\u0001\u0002\u0001", chars2: "\u0002\u0001\u0002", lineArray: ['', 'alpha\n', 'beta\n']}, 
			dmp.diff_linesToChars("alpha\nbeta\nalpha\n", "beta\nalpha\nbeta\n")
		);
		
		assertLinesToCharsResultEquals(
			"diff_linesToChars: Empty string and blank lines.", 
			{chars1: "", chars2: "\u0001\u0002\u0003\u0003", lineArray: ['', 'alpha\r\n', 'beta\r\n', '\r\n']}, 
			dmp.diff_linesToChars("", "alpha\r\nbeta\r\n\r\n\r\n")
		);

		assertLinesToCharsResultEquals(
			"diff_linesToChars: No linebreaks.", 
			{chars1: "\u0001", chars2: "\u0002", lineArray: ['', 'a', 'b']}, 
			dmp.diff_linesToChars("a", "b")
		);

		// More than 256 to reveal any 8-bit limitations.
		var n = 300;
		var lineList = new StringBuilder();
		var charList = new StringBuilder();
		var tmpVector = [];
		
		for (i in 0 ... n) {
			var x = i + 1;
			tmpVector.push(x + "\n");
			lineList.append(x + "\n");
			charList.addChar(x);
		}
		assertEquals(n, tmpVector.length);
		var lines = lineList.toString();
		var chars = charList.toString();
		assertEquals(n, chars.length);
		tmpVector.unshift("");
		assertLinesToCharsResultEquals(
			"diff_linesToChars: More than 256.", 
			{chars1: chars, chars2: "", lineArray: tmpVector}, 
			dmp.diff_linesToChars(lines, "")
		);
	}

	public function testDiffCharsToLines() {
		// First check that Diff equality works.
		assertTrue(new Diff(EQUAL, "a").equals(new Diff(EQUAL, "a")));

		assertDiffs("diff_charsToLines: Equality #2.", [new Diff(EQUAL, "a")], [new Diff(EQUAL, "a")]);

		// Convert chars up to lines.
		var diffs = [new Diff(EQUAL, "\u0001\u0002\u0001"), new Diff(INSERT, "\u0002\u0001\u0002")];
		var tmpVector = [];
		tmpVector.push("");
		tmpVector.push("alpha\n");
		tmpVector.push("beta\n");
		dmp.diff_charsToLines(diffs, tmpVector);
		assertDiffs("diff_charsToLines: Shared lines.", [new Diff(EQUAL, "alpha\nbeta\nalpha\n"), new Diff(INSERT, "beta\nalpha\nbeta\n")], diffs);

		// More than 256 to reveal any 8-bit limitations.
		var n = 300;
		tmpVector = [];
		var lineList = new StringBuilder();
		var charList = new StringBuilder();
		for (i in 0 ... n) {
			var x = ['a', 'b', 'c'][i%3];
			tmpVector.push(x + "\n");
			lineList.append(x + "\n");
			charList.append(x);
		}
		assertEquals(n, tmpVector.length);
		var lines = lineList.toString();
		var chars = charList.toString();
		assertEquals(n, chars.length);
		tmpVector.unshift("");
		diffs = [new Diff(DELETE, chars)];
		dmp.diff_charsToLines(diffs, tmpVector);
		assertDiffs("diff_charsToLines: More than 256.", [new Diff(DELETE, lines)], diffs);
	}

	public function testDiffCleanupMerge() {
		// Cleanup a messy diff.
		var diffs = [];
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Null case.", [], diffs);

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(DELETE, "b"), new Diff(INSERT, "c"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: No change case.", diffList(new Diff(EQUAL, "a"), new Diff(DELETE, "b"), new Diff(INSERT, "c")), diffs);

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(EQUAL, "b"), new Diff(EQUAL, "c"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Merge equalities.", diffList(new Diff(EQUAL, "abc")), diffs);

		diffs = diffList(new Diff(DELETE, "a"), new Diff(DELETE, "b"), new Diff(DELETE, "c"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Merge deletions.", diffList(new Diff(DELETE, "abc")), diffs);

		diffs = diffList(new Diff(INSERT, "a"), new Diff(INSERT, "b"), new Diff(INSERT, "c"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Merge insertions.", diffList(new Diff(INSERT, "abc")), diffs);

		diffs = diffList(new Diff(DELETE, "a"), new Diff(INSERT, "b"), new Diff(DELETE, "c"), new Diff(INSERT, "d"), new Diff(EQUAL, "e"), new Diff(EQUAL, "f"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Merge interweave.", diffList(new Diff(DELETE, "ac"), new Diff(INSERT, "bd"), new Diff(EQUAL, "ef")), diffs);

		diffs = diffList(new Diff(DELETE, "a"), new Diff(INSERT, "abc"), new Diff(DELETE, "dc"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Prefix and suffix detection.", diffList(new Diff(EQUAL, "a"), new Diff(DELETE, "d"), new Diff(INSERT, "b"), new Diff(EQUAL, "c")), diffs);

		diffs = diffList(new Diff(EQUAL, "x"), new Diff(DELETE, "a"), new Diff(INSERT, "abc"), new Diff(DELETE, "dc"), new Diff(EQUAL, "y"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Prefix and suffix detection with equalities.", diffList(new Diff(EQUAL, "xa"), new Diff(DELETE, "d"), new Diff(INSERT, "b"), new Diff(EQUAL, "cy")), diffs);

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(INSERT, "ba"), new Diff(EQUAL, "c"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Slide edit left.", diffList(new Diff(INSERT, "ab"), new Diff(EQUAL, "ac")), diffs);

		diffs = diffList(new Diff(EQUAL, "c"), new Diff(INSERT, "ab"), new Diff(EQUAL, "a"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Slide edit right.", diffList(new Diff(EQUAL, "ca"), new Diff(INSERT, "ba")), diffs);

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(DELETE, "b"), new Diff(EQUAL, "c"), new Diff(DELETE, "ac"), new Diff(EQUAL, "x"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Slide edit left recursive.", diffList(new Diff(DELETE, "abc"), new Diff(EQUAL, "acx")), diffs);

		diffs = diffList(new Diff(EQUAL, "x"), new Diff(DELETE, "ca"), new Diff(EQUAL, "c"), new Diff(DELETE, "b"), new Diff(EQUAL, "a"));
		dmp.diff_cleanupMerge(diffs);
		assertDiffs("diff_cleanupMerge: Slide edit right recursive.", diffList(new Diff(EQUAL, "xca"), new Diff(DELETE, "cba")), diffs);
	}

	public function testDiffCleanupSemanticLossless() {
		// Slide diffs to match logical boundaries.
		var diffs = diffList();
		dmp.diff_cleanupSemanticLossless(diffs);
		assertDiffs("diff_cleanupSemanticLossless: Null case.", diffList(), diffs);

		diffs = diffList(new Diff(EQUAL, "AAA\r\n\r\nBBB"), new Diff(INSERT, "\r\nDDD\r\n\r\nBBB"), new Diff(EQUAL, "\r\nEEE"));
		dmp.diff_cleanupSemanticLossless(diffs);
		assertDiffs("diff_cleanupSemanticLossless: Blank lines.", diffList(new Diff(EQUAL, "AAA\r\n\r\n"), new Diff(INSERT, "BBB\r\nDDD\r\n\r\n"), new Diff(EQUAL, "BBB\r\nEEE")), diffs);

		diffs = diffList(new Diff(EQUAL, "AAA\r\nBBB"), new Diff(INSERT, " DDD\r\nBBB"), new Diff(EQUAL, " EEE"));
		dmp.diff_cleanupSemanticLossless(diffs);
		assertDiffs("diff_cleanupSemanticLossless: Line boundaries.", diffList(new Diff(EQUAL, "AAA\r\n"), new Diff(INSERT, "BBB DDD\r\n"), new Diff(EQUAL, "BBB EEE")), diffs);

		diffs = diffList(new Diff(EQUAL, "The c"), new Diff(INSERT, "ow and the c"), new Diff(EQUAL, "at."));
		dmp.diff_cleanupSemanticLossless(diffs);
		assertDiffs("diff_cleanupSemanticLossless: Word boundaries.", diffList(new Diff(EQUAL, "The "), new Diff(INSERT, "cow and the "), new Diff(EQUAL, "cat.")), diffs);

		diffs = diffList(new Diff(EQUAL, "The-c"), new Diff(INSERT, "ow-and-the-c"), new Diff(EQUAL, "at."));
		dmp.diff_cleanupSemanticLossless(diffs);
		assertDiffs("diff_cleanupSemanticLossless: Alphanumeric boundaries.", diffList(new Diff(EQUAL, "The-"), new Diff(INSERT, "cow-and-the-"), new Diff(EQUAL, "cat.")), diffs);

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(DELETE, "a"), new Diff(EQUAL, "ax"));
		dmp.diff_cleanupSemanticLossless(diffs);
		assertDiffs("diff_cleanupSemanticLossless: Hitting the start.", diffList(new Diff(DELETE, "a"), new Diff(EQUAL, "aax")), diffs);

		diffs = diffList(new Diff(EQUAL, "xa"), new Diff(DELETE, "a"), new Diff(EQUAL, "a"));
		dmp.diff_cleanupSemanticLossless(diffs);
		assertDiffs("diff_cleanupSemanticLossless: Hitting the end.", diffList(new Diff(EQUAL, "xaa"), new Diff(DELETE, "a")), diffs);

		diffs = diffList(new Diff(EQUAL, "The xxx. The "), new Diff(INSERT, "zzz. The "), new Diff(EQUAL, "yyy."));
		dmp.diff_cleanupSemanticLossless(diffs);
		assertDiffs("diff_cleanupSemanticLossless: Sentence boundaries.", diffList(new Diff(EQUAL, "The xxx."), new Diff(INSERT, " The zzz."), new Diff(EQUAL, " The yyy.")), diffs);
	}

	public function testDiffCleanupSemantic() {
		// Cleanup semantically trivial equalities.
		var diffs = diffList();
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: Null case.", diffList(), diffs);

		diffs = diffList(new Diff(DELETE, "ab"), new Diff(INSERT, "cd"), new Diff(EQUAL, "12"), new Diff(DELETE, "e"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: No elimination #1.", diffList(new Diff(DELETE, "ab"), new Diff(INSERT, "cd"), new Diff(EQUAL, "12"), new Diff(DELETE, "e")), diffs);

		diffs = diffList(new Diff(DELETE, "abc"), new Diff(INSERT, "ABC"), new Diff(EQUAL, "1234"), new Diff(DELETE, "wxyz"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: No elimination #2.", diffList(new Diff(DELETE, "abc"), new Diff(INSERT, "ABC"), new Diff(EQUAL, "1234"), new Diff(DELETE, "wxyz")), diffs);

		diffs = diffList(new Diff(DELETE, "a"), new Diff(EQUAL, "b"), new Diff(DELETE, "c"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: Simple elimination.", diffList(new Diff(DELETE, "abc"), new Diff(INSERT, "b")), diffs);

		diffs = diffList(new Diff(DELETE, "ab"), new Diff(EQUAL, "cd"), new Diff(DELETE, "e"), new Diff(EQUAL, "f"), new Diff(INSERT, "g"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: Backpass elimination.", diffList(new Diff(DELETE, "abcdef"), new Diff(INSERT, "cdfg")), diffs);

		diffs = diffList(new Diff(INSERT, "1"), new Diff(EQUAL, "A"), new Diff(DELETE, "B"), new Diff(INSERT, "2"), new Diff(EQUAL, "_"), new Diff(INSERT, "1"), new Diff(EQUAL, "A"), new Diff(DELETE, "B"), new Diff(INSERT, "2"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: Multiple elimination.", diffList(new Diff(DELETE, "AB_AB"), new Diff(INSERT, "1A2_1A2")), diffs);

		diffs = diffList(new Diff(EQUAL, "The c"), new Diff(DELETE, "ow and the c"), new Diff(EQUAL, "at."));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: Word boundaries.", diffList(new Diff(EQUAL, "The "), new Diff(DELETE, "cow and the "), new Diff(EQUAL, "cat.")), diffs);

		diffs = diffList(new Diff(DELETE, "abcxx"), new Diff(INSERT, "xxdef"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: No overlap elimination.", diffList(new Diff(DELETE, "abcxx"), new Diff(INSERT, "xxdef")), diffs);

		diffs = diffList(new Diff(DELETE, "abcxxx"), new Diff(INSERT, "xxxdef"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: Overlap elimination.", diffList(new Diff(DELETE, "abc"), new Diff(EQUAL, "xxx"), new Diff(INSERT, "def")), diffs);

		diffs = diffList(new Diff(DELETE, "xxxabc"), new Diff(INSERT, "defxxx"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: Reverse overlap elimination.", diffList(new Diff(INSERT, "def"), new Diff(EQUAL, "xxx"), new Diff(DELETE, "abc")), diffs);

		diffs = diffList(new Diff(DELETE, "abcd1212"), new Diff(INSERT, "1212efghi"), new Diff(EQUAL, "----"), new Diff(DELETE, "A3"), new Diff(INSERT, "3BC"));
		dmp.diff_cleanupSemantic(diffs);
		assertDiffs("diff_cleanupSemantic: Two overlap eliminations.", diffList(new Diff(DELETE, "abcd"), new Diff(EQUAL, "1212"), new Diff(INSERT, "efghi"), new Diff(EQUAL, "----"), new Diff(DELETE, "A"), new Diff(EQUAL, "3"), new Diff(INSERT, "BC")), diffs);
	}

	public function testDiffCleanupEfficiency() {
		// Cleanup operationally trivial equalities.
		dmp.Diff_EditCost = 4;
		var diffs = diffList();
		dmp.diff_cleanupEfficiency(diffs);
		assertDiffs("diff_cleanupEfficiency: Null case.", diffList(), diffs);

		diffs = diffList(new Diff(DELETE, "ab"), new Diff(INSERT, "12"), new Diff(EQUAL, "wxyz"), new Diff(DELETE, "cd"), new Diff(INSERT, "34"));
		dmp.diff_cleanupEfficiency(diffs);
		assertDiffs("diff_cleanupEfficiency: No elimination.", diffList(new Diff(DELETE, "ab"), new Diff(INSERT, "12"), new Diff(EQUAL, "wxyz"), new Diff(DELETE, "cd"), new Diff(INSERT, "34")), diffs);

		diffs = diffList(new Diff(DELETE, "ab"), new Diff(INSERT, "12"), new Diff(EQUAL, "xyz"), new Diff(DELETE, "cd"), new Diff(INSERT, "34"));
		dmp.diff_cleanupEfficiency(diffs);
		assertDiffs("diff_cleanupEfficiency: Four-edit elimination.", diffList(new Diff(DELETE, "abxyzcd"), new Diff(INSERT, "12xyz34")), diffs);

		diffs = diffList(new Diff(INSERT, "12"), new Diff(EQUAL, "x"), new Diff(DELETE, "cd"), new Diff(INSERT, "34"));
		dmp.diff_cleanupEfficiency(diffs);
		assertDiffs("diff_cleanupEfficiency: Three-edit elimination.", diffList(new Diff(DELETE, "xcd"), new Diff(INSERT, "12x34")), diffs);

		diffs = diffList(new Diff(DELETE, "ab"), new Diff(INSERT, "12"), new Diff(EQUAL, "xy"), new Diff(INSERT, "34"), new Diff(EQUAL, "z"), new Diff(DELETE, "cd"), new Diff(INSERT, "56"));
		dmp.diff_cleanupEfficiency(diffs);
		assertDiffs("diff_cleanupEfficiency: Backpass elimination.", diffList(new Diff(DELETE, "abxyzcd"), new Diff(INSERT, "12xy34z56")), diffs);

		dmp.Diff_EditCost = 5;
		diffs = diffList(new Diff(DELETE, "ab"), new Diff(INSERT, "12"), new Diff(EQUAL, "wxyz"), new Diff(DELETE, "cd"), new Diff(INSERT, "34"));
		dmp.diff_cleanupEfficiency(diffs);
		assertDiffs("diff_cleanupEfficiency: High cost elimination.", diffList(new Diff(DELETE, "abwxyzcd"), new Diff(INSERT, "12wxyz34")), diffs);
		dmp.Diff_EditCost = 4;
	}

	public function testDiffPrettyHtml() {
		// Pretty print.
		var diffs = diffList(new Diff(EQUAL, "a\n"), new Diff(DELETE, "<B>b</B>"), new Diff(INSERT, "c&d"));
		assert("diff_prettyHtml:", "<span>a&para;<br></span><del style=\"background:#ffe6e6;\">&lt;B&gt;b&lt;/B&gt;</del><ins style=\"background:#e6ffe6;\">c&amp;d</ins>", dmp.diff_prettyHtml(diffs));
	}

	public function testDiffText() {
		// Compute the source and destination texts.
		var diffs = diffList(new Diff(EQUAL, "jump"), new Diff(DELETE, "s"), new Diff(INSERT, "ed"), new Diff(EQUAL, " over "), new Diff(DELETE, "the"), new Diff(INSERT, "a"), new Diff(EQUAL, " lazy"));
		assert("diff_text1:", "jumps over the lazy", dmp.diff_text1(diffs));
		assert("diff_text2:", "jumped over a lazy", dmp.diff_text2(diffs));
	}

	public function testDiffDelta() {
		// Convert a diff into delta string.
		var diffs = diffList(new Diff(EQUAL, "jump"), new Diff(DELETE, "s"), new Diff(INSERT, "ed"), new Diff(EQUAL, " over "), new Diff(DELETE, "the"), new Diff(INSERT, "a"), new Diff(EQUAL, " lazy"), new Diff(INSERT, "old dog"));
		var text1 = dmp.diff_text1(diffs);
		assert("diff_text1: Base text.", "jumps over the lazy", text1);

		var delta = dmp.diff_toDelta(diffs);
		assert("diff_toDelta:", "=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", delta);

		// Convert delta string into a diff.
		assertDiffs("diff_fromDelta: Normal.", diffs, dmp.diff_fromDelta(text1, delta));

		// Generates error (19 < 20).
		try {
			dmp.diff_fromDelta(text1 + "x", delta);
			fail("diff_fromDelta: Too long.");
		} catch (e: Dynamic) {
			// Exception expected.
		}

		// Generates error (19 > 18).
		try {
			dmp.diff_fromDelta(text1.substring(1), delta);
			fail("diff_fromDelta: Too short.");
		} catch (e: Dynamic) {
			// Exception expected.
		}

		// Generates error (%c3%xy invalid Unicode).
		try {
			dmp.diff_fromDelta("", "+%c3%xy");
			fail("diff_fromDelta: Invalid character.");
		} catch (e: Dynamic) {
			// Exception expected.
		}

		// Test deltas with special characters.
		diffs = diffList(new Diff(EQUAL, "\u0680 \000 \t %"), new Diff(DELETE, "\u0681 \001 \n ^"), new Diff(INSERT, "\u0682 \002 \\ |"));
		text1 = dmp.diff_text1(diffs);
		assert("diff_text1: Unicode text.", "\u0680 \000 \t %\u0681 \001 \n ^", text1);

		delta = dmp.diff_toDelta(diffs);
		#if (java || node)
		assert("diff_toDelta: Unicode.", "=7\t-7\t+%DA%82 %02 %5C %7C", delta);
		#end

		assertDiffs("diff_fromDelta: Unicode.", diffs, dmp.diff_fromDelta(text1, delta));

		// Verify pool of unchanged characters.
		diffs = diffList(new Diff(INSERT, "A-Z a-z 0-9 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # "));
		var text2 = dmp.diff_text2(diffs);
		assert("diff_text2: Unchanged characters.", "A-Z a-z 0-9 - _ . ! ~ * \' ( ) ; / ? : @ & = + $ , # ", text2);

		delta = dmp.diff_toDelta(diffs);
		assert("diff_toDelta: Unchanged characters.", "+A-Z a-z 0-9 - _ . ! ~ * \' ( ) ; / ? : @ & = + $ , # ", delta);

		// Convert delta string into a diff.
		assertDiffs("diff_fromDelta: Unchanged characters.", diffs, dmp.diff_fromDelta("", delta));
	}

	public function testDiffXIndex() {
		// Translate a location in text1 to text2.
		var diffs = diffList(new Diff(DELETE, "a"), new Diff(INSERT, "1234"), new Diff(EQUAL, "xyz"));
		assert("diff_xIndex: Translation on equality.", 5, dmp.diff_xIndex(diffs, 2));

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(DELETE, "1234"), new Diff(EQUAL, "xyz"));
		assert("diff_xIndex: Translation on deletion.", 1, dmp.diff_xIndex(diffs, 3));
	}

	public function testDiffLevenshtein() {
		var diffs = diffList(new Diff(DELETE, "abc"), new Diff(INSERT, "1234"), new Diff(EQUAL, "xyz"));
		assert("Levenshtein with trailing equality.", 4, dmp.diff_levenshtein(diffs));

		diffs = diffList(new Diff(EQUAL, "xyz"), new Diff(DELETE, "abc"), new Diff(INSERT, "1234"));
		assert("Levenshtein with leading equality.", 4, dmp.diff_levenshtein(diffs));

		diffs = diffList(new Diff(DELETE, "abc"), new Diff(EQUAL, "xyz"), new Diff(INSERT, "1234"));
		assert("Levenshtein with middle equality.", 7, dmp.diff_levenshtein(diffs));
	}

	public function testDiffBisect() {
		// Normal.
		var a = "cat";
		var b = "map";
		// Since the resulting diff hasn't been normalized, it would be ok if
		// the insertion and deletion pairs are swapped.
		// If the order changes, tweak this test as required.
		var diffs = diffList(new Diff(DELETE, "c"), new Diff(INSERT, "m"), new Diff(EQUAL, "a"), new Diff(DELETE, "t"), new Diff(INSERT, "p"));
		assertDiffs("diff_bisect: Normal.", diffs, dmp.diff_bisect(a, b, Math.POSITIVE_INFINITY));

		// Timeout.
		diffs = diffList(new Diff(DELETE, "cat"), new Diff(INSERT, "map"));
		assertDiffs("diff_bisect: Timeout.", diffs, dmp.diff_bisect(a, b, 0));
	}

	public function testDiffMain() {
		// Perform a trivial diff.
		var diffs = diffList();
		assertDiffs("diff_main: Null case.", diffs, dmp.diff_main("", "", false));

		diffs = diffList(new Diff(EQUAL, "abc"));
		assertDiffs("diff_main: Equality.", diffs, dmp.diff_main("abc", "abc", false));

		diffs = diffList(new Diff(EQUAL, "ab"), new Diff(INSERT, "123"), new Diff(EQUAL, "c"));
		assertDiffs("diff_main: Simple insertion.", diffs, dmp.diff_main("abc", "ab123c", false));

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(DELETE, "123"), new Diff(EQUAL, "bc"));
		assertDiffs("diff_main: Simple deletion.", diffs, dmp.diff_main("a123bc", "abc", false));

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(INSERT, "123"), new Diff(EQUAL, "b"), new Diff(INSERT, "456"), new Diff(EQUAL, "c"));
		assertDiffs("diff_main: Two insertions.", diffs, dmp.diff_main("abc", "a123b456c", false));

		diffs = diffList(new Diff(EQUAL, "a"), new Diff(DELETE, "123"), new Diff(EQUAL, "b"), new Diff(DELETE, "456"), new Diff(EQUAL, "c"));
		assertDiffs("diff_main: Two deletions.", diffs, dmp.diff_main("a123b456c", "abc", false));

		// Perform a real diff.
		// Switch off the timeout.
		dmp.Diff_Timeout = 0;
		diffs = diffList(new Diff(DELETE, "a"), new Diff(INSERT, "b"));
		assertDiffs("diff_main: Simple case #1.", diffs, dmp.diff_main("a", "b", false));

		diffs = diffList(new Diff(DELETE, "Apple"), new Diff(INSERT, "Banana"), new Diff(EQUAL, "s are a"), new Diff(INSERT, "lso"), new Diff(EQUAL, " fruit."));
		assertDiffs("diff_main: Simple case #2.", diffs, dmp.diff_main("Apples are a fruit.", "Bananas are also fruit.", false));

		diffs = diffList(new Diff(DELETE, "a"), new Diff(INSERT, "\u0680"), new Diff(EQUAL, "x"), new Diff(DELETE, "\t"), new Diff(INSERT, "\000"));
		assertDiffs("diff_main: Simple case #3.", diffs, dmp.diff_main("ax\t", "\u0680x\000", false));

		diffs = diffList(new Diff(DELETE, "1"), new Diff(EQUAL, "a"), new Diff(DELETE, "y"), new Diff(EQUAL, "b"), new Diff(DELETE, "2"), new Diff(INSERT, "xab"));
		assertDiffs("diff_main: Overlap #1.", diffs, dmp.diff_main("1ayb2", "abxab", false));

		diffs = diffList(new Diff(INSERT, "xaxcx"), new Diff(EQUAL, "abc"), new Diff(DELETE, "y"));
		assertDiffs("diff_main: Overlap #2.", diffs, dmp.diff_main("abcy", "xaxcxabc", false));

		diffs = diffList(new Diff(DELETE, "ABCD"), new Diff(EQUAL, "a"), new Diff(DELETE, "="), new Diff(INSERT, "-"), new Diff(EQUAL, "bcd"), new Diff(DELETE, "="), new Diff(INSERT, "-"), new Diff(EQUAL, "efghijklmnopqrs"), new Diff(DELETE, "EFGHIJKLMNOefg"));
		assertDiffs("diff_main: Overlap #3.", diffs, dmp.diff_main("ABCDa=bcd=efghijklmnopqrsEFGHIJKLMNOefg", "a-bcd-efghijklmnopqrs", false));

		diffs = diffList(new Diff(INSERT, " "), new Diff(EQUAL, "a"), new Diff(INSERT, "nd"), new Diff(EQUAL, " [[Pennsylvania]]"), new Diff(DELETE, " and [[New"));
		assertDiffs("diff_main: Large equality.", diffs, dmp.diff_main("a [[Pennsylvania]] and [[New", " and [[Pennsylvania]]", false));
		
		dmp.Diff_Timeout = 0.1;  // 100ms
		var a = "`Twas brillig, and the slithy toves\nDid gyre and gimble in the wabe:\nAll mimsy were the borogoves,\nAnd the mome raths outgrabe.\n";
		var b = "I am the very model of a modern major general,\nI've information vegetable, animal, and mineral,\nI know the kings of England, and I quote the fights historical,\nFrom Marathon to Waterloo, in order categorical.\n";
		// Increase the text lengths by 1024 times to ensure a timeout.
		for (x in 0 ... 10) {
			a = a + a;
			b = b + b;
		}
		
		#if node // has milliseconds precision
		var startTime = Date.now().getTime();
		dmp.diff_main(a, b);
		var endTime = Date.now().getTime();
		// Test that we took at least the timeout period.
		assertTrue(dmp.Diff_Timeout * 1000 <= endTime - startTime);
		// Test that we didn't take forever (be forgiving).
		// Theoretically this test could fail very occasionally if the
		// OS task swaps or locks up for a second at the wrong moment.
		assertTrue(dmp.Diff_Timeout * 1000 * 2 > endTime - startTime);
		#end
		dmp.Diff_Timeout = 0;

		// Test the linemode speedup.
		// Must be long to pass the 100 char cutoff.
		a = "1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n";
		b = "abcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\n";
		assertDiffs("diff_main: Simple line-mode.", dmp.diff_main(a, b, true), dmp.diff_main(a, b, false));

		a = "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890";
		b = "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij";
		assertDiffs("diff_main: Single line-mode.", dmp.diff_main(a, b, true), dmp.diff_main(a, b, false));

		a = "1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n";
		b = "abcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n";
		var texts_linemode = diff_rebuildtexts(dmp.diff_main(a, b, true));
		var texts_textmode = diff_rebuildtexts(dmp.diff_main(a, b, false));
		assertArrayEquals("diff_main: Overlap line-mode.", texts_textmode, texts_linemode);

		// Test null inputs.
		try {
			dmp.diff_main(null, null);
			fail("diff_main: Null inputs.");
		} catch (e: Dynamic) {
			// Error expected.
		}
	}


	//  MATCH TEST FUNCTIONS


	public function testMatchAlphabet() {
		// Initialise the bitmasks for Bitap.
		var bitmask: Map<String, Int>;
		bitmask = new Map();
		bitmask.set('a', 4); bitmask.set('b', 2); bitmask.set('c', 1);
		assertMap("match_alphabet: Unique.", bitmask, dmp.match_alphabet("abc"));

		bitmask = new Map();
		bitmask.set('a', 37); bitmask.set('b', 18); bitmask.set('c', 8);
		assertMap("match_alphabet: Duplicates.", bitmask, dmp.match_alphabet("abcaba"));
	}

	public function testMatchBitap() {
		// Bitap algorithm.
		dmp.Match_Distance = 100;
		dmp.Match_Threshold = 0.5;
		assert("match_bitap: Exact match #1.", 5, dmp.match_bitap("abcdefghijk", "fgh", 5));

		assert("match_bitap: Exact match #2.", 5, dmp.match_bitap("abcdefghijk", "fgh", 0));

		assert("match_bitap: Fuzzy match #1.", 4, dmp.match_bitap("abcdefghijk", "efxhi", 0));

		assert("match_bitap: Fuzzy match #2.", 2, dmp.match_bitap("abcdefghijk", "cdefxyhijk", 5));

		assert("match_bitap: Fuzzy match #3.", -1, dmp.match_bitap("abcdefghijk", "bxy", 1));

		assert("match_bitap: Overflow.", 2, dmp.match_bitap("123456789xx0", "3456789x0", 2));

		assert("match_bitap: Before start match.", 0, dmp.match_bitap("abcdef", "xxabc", 4));

		assert("match_bitap: Beyond end match.", 3, dmp.match_bitap("abcdef", "defyy", 4));

		assert("match_bitap: Oversized pattern.", 0, dmp.match_bitap("abcdef", "xabcdefy", 0));

		dmp.Match_Threshold = 0.4;
		assert("match_bitap: Threshold #1.", 4, dmp.match_bitap("abcdefghijk", "efxyhi", 1));

		dmp.Match_Threshold = 0.3;
		assert("match_bitap: Threshold #2.", -1, dmp.match_bitap("abcdefghijk", "efxyhi", 1));

		dmp.Match_Threshold = 0.0;
		assert("match_bitap: Threshold #3.", 1, dmp.match_bitap("abcdefghijk", "bcdef", 1));

		dmp.Match_Threshold = 0.5;
		assert("match_bitap: Multiple select #1.", 0, dmp.match_bitap("abcdexyzabcde", "abccde", 3));

		assert("match_bitap: Multiple select #2.", 8, dmp.match_bitap("abcdexyzabcde", "abccde", 5));

		dmp.Match_Distance = 10;  // Strict location.
		assert("match_bitap: Distance test #1.", -1, dmp.match_bitap("abcdefghijklmnopqrstuvwxyz", "abcdefg", 24));

		assert("match_bitap: Distance test #2.", 0, dmp.match_bitap("abcdefghijklmnopqrstuvwxyz", "abcdxxefg", 1));

		dmp.Match_Distance = 1000;  // Loose location.
		assert("match_bitap: Distance test #3.", 0, dmp.match_bitap("abcdefghijklmnopqrstuvwxyz", "abcdefg", 24));
	}

	public function testMatchMain() {
		// Full match.
		assert("match_main: Equality.", 0, dmp.match_main("abcdef", "abcdef", 1000));

		assert("match_main: Null text.", -1, dmp.match_main("", "abcdef", 1));

		assert("match_main: Null pattern.", 3, dmp.match_main("abcdef", "", 3));

		assert("match_main: Exact match.", 3, dmp.match_main("abcdef", "de", 3));

		assert("match_main: Beyond end match.", 3, dmp.match_main("abcdef", "defy", 4));

		assert("match_main: Oversized pattern.", 0, dmp.match_main("abcdef", "abcdefy", 0));

		dmp.Match_Threshold = 0.7;
		assert("match_main: Complex match.", 4, dmp.match_main("I am the very model of a modern major general.", " that berry ", 5));
		dmp.Match_Threshold = 0.5;

		// Test null inputs.
		try {
			dmp.match_main(null, null, 0);
			fail("match_main: Null inputs.");
		} catch (e: Dynamic) {
			// Error expected.
		}
	}


	//  PATCH TEST FUNCTIONS


	public function testPatchObj() {
		// Patch Object.
		var p = new Patch();
		p.start1 = 20;
		p.start2 = 21;
		p.length1 = 18;
		p.length2 = 17;
		p.diffs = diffList(new Diff(EQUAL, "jump"), new Diff(DELETE, "s"), new Diff(INSERT, "ed"), new Diff(EQUAL, " over "), new Diff(DELETE, "the"), new Diff(INSERT, "a"), new Diff(EQUAL, "\nlaz"));
		var strp = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n";
		assert("Patch: toString.", strp, p.toString());
	}

	public function testPatchFromText() {
		assert("patch_fromText: #0.", true, dmp.patch_fromText("").length == 0);

		var strp = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n";
		assert("patch_fromText: #1.", strp, dmp.patch_fromText(strp)[0].toString());

		assert("patch_fromText: #2.", "@@ -1 +1 @@\n-a\n+b\n", dmp.patch_fromText("@@ -1 +1 @@\n-a\n+b\n")[0].toString());

		assert("patch_fromText: #3.", "@@ -1,3 +0,0 @@\n-abc\n", dmp.patch_fromText("@@ -1,3 +0,0 @@\n-abc\n")[0].toString());

		assert("patch_fromText: #4.", "@@ -0,0 +1,3 @@\n+abc\n", dmp.patch_fromText("@@ -0,0 +1,3 @@\n+abc\n")[0].toString());

		// Generates error.
		try {
			dmp.patch_fromText("Bad\nPatch\n");
			fail("patch_fromText: #5.");
		} catch (e: Dynamic) {
			// Exception expected.
		}
	}

	public function testPatchToText() {
		var strp = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n";
		var patches;
		patches = dmp.patch_fromText(strp);
		assert("patch_toText: Single.", strp, dmp.patch_toText(patches));

		strp = "@@ -1,9 +1,9 @@\n-f\n+F\n oo+fooba\n@@ -7,9 +7,9 @@\n obar\n-,\n+.\n  tes\n";
		patches = dmp.patch_fromText(strp);
		assert("patch_toText: Dual.", strp, dmp.patch_toText(patches));
	}

	public function testPatchAddContext() {
		dmp.Patch_Margin = 4;
		var p;
		p = dmp.patch_fromText("@@ -21,4 +21,10 @@\n-jump\n+somersault\n")[0];
		dmp.patch_addContext(p, "The quick brown fox jumps over the lazy dog.");
		assert("patch_addContext: Simple case.", "@@ -17,12 +17,18 @@\n fox \n-jump\n+somersault\n s ov\n", p.toString());

		p = dmp.patch_fromText("@@ -21,4 +21,10 @@\n-jump\n+somersault\n")[0];
		dmp.patch_addContext(p, "The quick brown fox jumps.");
		assert("patch_addContext: Not enough trailing context.", "@@ -17,10 +17,16 @@\n fox \n-jump\n+somersault\n s.\n", p.toString());

		p = dmp.patch_fromText("@@ -3 +3,2 @@\n-e\n+at\n")[0];
		dmp.patch_addContext(p, "The quick brown fox jumps.");
		assert("patch_addContext: Not enough leading context.", "@@ -1,7 +1,8 @@\n Th\n-e\n+at\n  qui\n", p.toString());

		p = dmp.patch_fromText("@@ -3 +3,2 @@\n-e\n+at\n")[0];
		dmp.patch_addContext(p, "The quick brown fox jumps.  The quick brown fox crashes.");
		assert("patch_addContext: Ambiguity.", "@@ -1,27 +1,28 @@\n Th\n-e\n+at\n  quick brown fox jumps. \n", p.toString());
	}

	
	public function testPatchMake() {
		var patches;
		patches = dmp.patch_make("", "");
		assert("patch_make: Null case.", "", dmp.patch_toText(patches));

		var text1 = "The quick brown fox jumps over the lazy dog.";
		var text2 = "That quick brown fox jumped over a lazy dog.";
		var expectedPatch = "@@ -1,8 +1,7 @@\n Th\n-at\n+e\n  qui\n@@ -21,17 +21,18 @@\n jump\n-ed\n+s\n  over \n-a\n+the\n  laz\n";
		// The second patch must be "-21,17 +21,18", not "-22,17 +21,18" due to rolling context.
		patches = dmp.patch_make(text2, text1);
		assert("patch_make: Text2+Text1 inputs.", expectedPatch, dmp.patch_toText(patches));

		expectedPatch = "@@ -1,11 +1,12 @@\n Th\n-e\n+at\n  quick b\n@@ -22,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n";
		patches = dmp.patch_make(text1, text2);
		assert("patch_make: Text1+Text2 inputs.", expectedPatch, dmp.patch_toText(patches));

		var diffs = dmp.diff_main(text1, text2, false);
		patches = dmp.patch_make(diffs);
		assert("patch_make: Diff input.", expectedPatch, dmp.patch_toText(patches));

		patches = dmp.patch_make(text1, diffs);
		assert("patch_make: Text1+Diff inputs.", expectedPatch, dmp.patch_toText(patches));

		patches = dmp.patch_make(text1, text2, diffs);
		assert("patch_make: Text1+Text2+Diff inputs (deprecated).", expectedPatch, dmp.patch_toText(patches));

		patches = dmp.patch_make("`1234567890-=[]\\;',./", "~!@#$%^&*()_+{}|:\"<>?");
		assert("patch_toText: Character encoding.", "@@ -1,21 +1,21 @@\n-%601234567890-=%5B%5D%5C;',./\n+~!@#$%25%5E&*()_+%7B%7D%7C:%22%3C%3E?\n", dmp.patch_toText(patches));

		diffs = diffList(new Diff(DELETE, "`1234567890-=[]\\;',./"), new Diff(INSERT, "~!@#$%^&*()_+{}|:\"<>?"));
		assertDiffs("patch_fromText: Character decoding.", diffs, dmp.patch_fromText("@@ -1,21 +1,21 @@\n-%601234567890-=%5B%5D%5C;',./\n+~!@#$%25%5E&*()_+%7B%7D%7C:%22%3C%3E?\n")[0].diffs);

		text1 = "";
		for (x in 0 ... 100) {
			text1 += "abcdef";
		}
		text2 = text1 + "123";
		expectedPatch = "@@ -573,28 +573,31 @@\n cdefabcdefabcdefabcdefabcdef\n+123\n";
		patches = dmp.patch_make(text1, text2);
		assert("patch_make: Long string with repeats.", expectedPatch, dmp.patch_toText(patches));

		// Test null inputs.
		try {
			dmp.patch_make(null);
			fail("patch_make: Null inputs.");
		} catch (e: Dynamic) {
			// Error expected.
		}
	}
	

	public function testPatchSplitMax() {
		// Assumes that Match_MaxBits is 32.
		var patches;
		patches = dmp.patch_make("abcdefghijklmnopqrstuvwxyz01234567890", "XabXcdXefXghXijXklXmnXopXqrXstXuvXwxXyzX01X23X45X67X89X0");
		dmp.patch_splitMax(patches);
		assert("patch_splitMax: #1.", "@@ -1,32 +1,46 @@\n+X\n ab\n+X\n cd\n+X\n ef\n+X\n gh\n+X\n ij\n+X\n kl\n+X\n mn\n+X\n op\n+X\n qr\n+X\n st\n+X\n uv\n+X\n wx\n+X\n yz\n+X\n 012345\n@@ -25,13 +39,18 @@\n zX01\n+X\n 23\n+X\n 45\n+X\n 67\n+X\n 89\n+X\n 0\n", dmp.patch_toText(patches));

		patches = dmp.patch_make("abcdef1234567890123456789012345678901234567890123456789012345678901234567890uvwxyz", "abcdefuvwxyz");
		var oldToText = dmp.patch_toText(patches);
		dmp.patch_splitMax(patches);
		assert("patch_splitMax: #2.", oldToText, dmp.patch_toText(patches));

		patches = dmp.patch_make("1234567890123456789012345678901234567890123456789012345678901234567890", "abc");
		dmp.patch_splitMax(patches);
		assert("patch_splitMax: #3.", "@@ -1,32 +1,4 @@\n-1234567890123456789012345678\n 9012\n@@ -29,32 +1,4 @@\n-9012345678901234567890123456\n 7890\n@@ -57,14 +1,3 @@\n-78901234567890\n+abc\n", dmp.patch_toText(patches));

		patches = dmp.patch_make("abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1", "abcdefghij , h : 1 , t : 1 abcdefghij , h : 1 , t : 1 abcdefghij , h : 0 , t : 1");
		dmp.patch_splitMax(patches);
		assert("patch_splitMax: #4.", "@@ -2,32 +2,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n@@ -29,32 +29,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n", dmp.patch_toText(patches));
	}

	public function testPatchAddPadding() {
		var patches;
		patches = dmp.patch_make("", "test");
		assert("patch_addPadding: Both edges full.", "@@ -0,0 +1,4 @@\n+test\n", dmp.patch_toText(patches));
		dmp.patch_addPadding(patches);
		assert("patch_addPadding: Both edges full.", "@@ -1,8 +1,12 @@\n %01%02%03%04\n+test\n %01%02%03%04\n", dmp.patch_toText(patches));

		patches = dmp.patch_make("XY", "XtestY");
		assert("patch_addPadding: Both edges partial.", "@@ -1,2 +1,6 @@\n X\n+test\n Y\n", dmp.patch_toText(patches));
		dmp.patch_addPadding(patches);
		assert("patch_addPadding: Both edges partial.", "@@ -2,8 +2,12 @@\n %02%03%04X\n+test\n Y%01%02%03\n", dmp.patch_toText(patches));

		patches = dmp.patch_make("XXXXYYYY", "XXXXtestYYYY");
		assert("patch_addPadding: Both edges none.", "@@ -1,8 +1,12 @@\n XXXX\n+test\n YYYY\n", dmp.patch_toText(patches));
		dmp.patch_addPadding(patches);
		assert("patch_addPadding: Both edges none.", "@@ -5,8 +5,12 @@\n XXXX\n+test\n YYYY\n", dmp.patch_toText(patches));
	}

	public function testPatchApply() {
		dmp.Match_Distance = 1000;
		dmp.Match_Threshold = 0.5;
		dmp.Patch_DeleteThreshold = 0.5;
		var patches;
		patches = dmp.patch_make("", "");
		var results = dmp.patch_apply(patches, "Hello world.");
		var boolArray = results.applied;
		var resultStr = results.text + "\t" + boolArray.length;
		assert("patch_apply: Null case.", "Hello world.\t0", resultStr);

		patches = dmp.patch_make("The quick brown fox jumps over the lazy dog.", "That quick brown fox jumped over a lazy dog.");
		results = dmp.patch_apply(patches, "The quick brown fox jumps over the lazy dog.");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0] + "\t" + boolArray[1];
		assert("patch_apply: Exact match.", "That quick brown fox jumped over a lazy dog.\ttrue\ttrue", resultStr);

		results = dmp.patch_apply(patches, "The quick red rabbit jumps over the tired tiger.");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0] + "\t" + boolArray[1];
		assert("patch_apply: Partial match.", "That quick red rabbit jumped over a tired tiger.\ttrue\ttrue", resultStr);

		results = dmp.patch_apply(patches, "I am the very model of a modern major general.");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0] + "\t" + boolArray[1];
		assert("patch_apply: Failed match.", "I am the very model of a modern major general.\tfalse\tfalse", resultStr);

		patches = dmp.patch_make("x1234567890123456789012345678901234567890123456789012345678901234567890y", "xabcy");
		results = dmp.patch_apply(patches, "x123456789012345678901234567890-----++++++++++-----123456789012345678901234567890y");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0] + "\t" + boolArray[1];
		assert("patch_apply: Big delete, small change.", "xabcy\ttrue\ttrue", resultStr);

		patches = dmp.patch_make("x1234567890123456789012345678901234567890123456789012345678901234567890y", "xabcy");
		results = dmp.patch_apply(patches, "x12345678901234567890---------------++++++++++---------------12345678901234567890y");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0] + "\t" + boolArray[1];
		assert("patch_apply: Big delete, big change 1.", "xabc12345678901234567890---------------++++++++++---------------12345678901234567890y\tfalse\ttrue", resultStr);

		dmp.Patch_DeleteThreshold = 0.6;
		patches = dmp.patch_make("x1234567890123456789012345678901234567890123456789012345678901234567890y", "xabcy");
		results = dmp.patch_apply(patches, "x12345678901234567890---------------++++++++++---------------12345678901234567890y");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0] + "\t" + boolArray[1];
		assert("patch_apply: Big delete, big change 2.", "xabcy\ttrue\ttrue", resultStr);
		dmp.Patch_DeleteThreshold = 0.5;

		// Compensate for failed patch.
		dmp.Match_Threshold = 0.0;
		dmp.Match_Distance = 0;
		patches = dmp.patch_make("abcdefghijklmnopqrstuvwxyz--------------------1234567890", "abcXXXXXXXXXXdefghijklmnopqrstuvwxyz--------------------1234567YYYYYYYYYY890");
		results = dmp.patch_apply(patches, "ABCDEFGHIJKLMNOPQRSTUVWXYZ--------------------1234567890");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0] + "\t" + boolArray[1];
		assert("patch_apply: Compensate for failed patch.", "ABCDEFGHIJKLMNOPQRSTUVWXYZ--------------------1234567YYYYYYYYYY890\tfalse\ttrue", resultStr);
		dmp.Match_Threshold = 0.5;
		dmp.Match_Distance = 1000;

		patches = dmp.patch_make("", "test");
		var patchStr = dmp.patch_toText(patches);
		dmp.patch_apply(patches, "");
		assert("patch_apply: No side effects.", patchStr, dmp.patch_toText(patches));

		patches = dmp.patch_make("The quick brown fox jumps over the lazy dog.", "Woof");
		patchStr = dmp.patch_toText(patches);
		dmp.patch_apply(patches, "The quick brown fox jumps over the lazy dog.");
		assert("patch_apply: No side effects with major delete.", patchStr, dmp.patch_toText(patches));

		patches = dmp.patch_make("", "test");
		results = dmp.patch_apply(patches, "");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0];
		assert("patch_apply: Edge exact match.", "test\ttrue", resultStr);

		patches = dmp.patch_make("XY", "XtestY");
		results = dmp.patch_apply(patches, "XY");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0];
		assert("patch_apply: Near edge exact match.", "XtestY\ttrue", resultStr);

		patches = dmp.patch_make("y", "y123");
		results = dmp.patch_apply(patches, "x");
		boolArray = results.applied;
		resultStr = results.text + "\t" + boolArray[0];
		assert("patch_apply: Edge partial match.", "x123\ttrue", resultStr);
	}

	// Construct the two texts which made up the diff originally.
	private function diff_rebuildtexts(diffs: Array<Diff>) {
		var text = ["", ""];
		for (myDiff in diffs) {
			if (myDiff.operation != Operation.INSERT) {
				text[0] += myDiff.text;
			}
			if (myDiff.operation != Operation.DELETE) {
				text[1] += myDiff.text;
			}
		}
		return text;
	}

	

	function diffList(?a, ?b, ?c, ?d, ?e, ?f, ?g, ?h, ?i, ?j, ?k, ?l) {
		var result = [];
		for (item in [a,b,c,d,e,f,g,h,i,j,k,l])
			if (item != null) result.push(item);
		return result;
	}
}
