package;

import DiffMatchPatch;


class Main {
	
	
	static function main() {
		var text1 = [
			"Hamlet: Do you see yonder cloud that's almost in shape of a camel?",
			"Polonius: By the mass, and 'tis like a camel, indeed.",
			"Hamlet: Methinks it is like a weasel.",
			"Polonius: It is backed like a weasel.",
			"Hamlet: Or like a whale?",
			"Polonius: Very like a whale.",
			"-- Shakespeare"
		].join('\n');
		var text2 = [
			"Hamlet: Do you see the cloud over there that's almost the shape of a camel?",	
			"Polonius: By golly, it is like a camel, indeed.",
			"Hamlet: I think it looks like a weasel.",
			"Polonius: It is shaped like a weasel.",
			"Hamlet: Or like a whale?",
			"Polonius: It's totally like a whale.",
			"-- Shakespeare"
		].join('\n');

		/*text1 = [
			"abc",
			"de egf"
		].join('\n');
		text2 = [
			"abc",
			"dae fr egf"
		].join('\n');*/
		
		//text1 = 'Hello world';
		//text2 = 'Goodbye world';
		
		/*var diffs = DiffMatchPatch.diff_main(text1, text2);
		//trace(diffs);
		DiffMatchPatch.diff_cleanupSemantic(diffs);
		DiffMatchPatch.diff_cleanupEfficiency(diffs);
		
		var patches = DiffMatchPatch.patch_make(text1, diffs);*/

		//trace(DiffMatchPatch.patch_apply(patches, text1).text);
		var patches = DiffMatchPatch.patch_make_texts(text1, text2);
		trace(text2 == DiffMatchPatch.patch_apply(patches, text1).text);
	}
	
}