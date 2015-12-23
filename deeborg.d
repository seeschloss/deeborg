import std.stdio;
import std.string;
import std.random;
import std.digest.crc;
import std.conv;
import std.file;
import std.regex;
import std.getopt;
import std.zlib;
import std.algorithm;
import std.math;

import sqlite.database, sqlite.exception, sqlite.statement, sqlite.table;

immutable WORD_POPULARITY_THRESHOLD = 1;
int LOOKAHEAD_DEPTH = 3;

void help() {
	stdout.writeln(q"#Usage: deeborg  [options ...]

	--file=<word database>      read <word database> to create answers and update
	                            it with new sentences
	                            ("deeborg.state" in current directory by default)

	--learn=<true|false>        do not learn new sentences
	                            (true by default, ie learn new sentences)

	--answer=<true|false>       do not answer fed sentences
	                            (true by default, ie answer each sentence fed)

	--depth=<lookahead depth>   depth to which to look for matches for words in
	                            answer (3 means every three-word subsentence must
	                            already exist in known sentences)
	                            (2 by default)
	
	--handle=<author handle>    this will be used for answering posts, where a name
	                            is needed
	
	--help                      this help message


Unless learning or answering are disabled, each line fed on stdin
will be read and answered to use Markov chains and the existing
word database. Each line will then be parsed into sentences
and added to the database, and the next line will be processed.

License GPLv2: <http://gnu.org/licenses/gpl.html>.
Written by Matthieu Valleton, please report bugs or comments to <see@seos.fr>.
Project homepage: <https://github.com/seeschloss/deeborg>.
#");
}

int main(string[] args) {
	bool learn = true, answer = true;
	int depth = 2;
	string handle = null;
	string statefile = "deeborg.state";
	string tmpstatefile = "";

	try {
		getopt(
			args,
			"learn", &learn,
			"answer", &answer,
			"file", &statefile,
			"depth", &depth,
			"handle", &handle
		);
	} catch (Exception e) {
		help();
		return 1;
	}

	tmpstatefile = statefile ~ ".tmp";

	LOOKAHEAD_DEPTH = depth;

	Bot bot = new Bot(statefile);
	bot.user = std.array.replace(handle, "\t", " ");

	string sentence;
	while ((sentence = stdin.readln()) !is null) {
		sentence = strip(sentence);

		debug(deeborg) stderr.writeln("Sentence to answer is ", sentence);

		if (answer) {
			string answer_sentence = bot.answer(sentence);

			// This is a crude way to ensure that sentences end mostly correctly.
			int tries = 0;
			while (answer_sentence.length > 1 && answer_sentence[$-1] != '.' && answer_sentence[$-1] != '!' && answer_sentence[$-1] != '?' && tries < 20) {
				tries++;
				debug(tries) stderr.writeln("Another try because sentence is not good: ", answer_sentence);
				answer_sentence = bot.answer(sentence);
			}

			/*
			if (answer_sentence.length > 1 && answer_sentence[$-1] == '.') {
				// Remove extra period.
				answer_sentence = answer_sentence[0 .. $-1];
			}
			*/

			stdout.writeln(answer_sentence);
		}

		if (learn) {
			bot.learn(sentence);
		}
	}

	//string state = bot.save_state();

	return 0;
}

class Bot {
	Database db;
	string user = "";

	this(string dbfile) {
		if (!exists(dbfile)) {
			this.db = new Database(dbfile);
			db.createTable("words",
				"word_id INTEGER PRIMARY KEY ASC",
				"word TEXT UNIQUE");

			db.createTable("words_before",
				"word INTEGER",
				"word1 INTEGER",
				"word2 INTEGER",
				"frequency INTEGER");
			
			db.createTable("words_after",
				"word INTEGER",
				"word1 INTEGER",
				"word2 INTEGER",
				"frequency INTEGER");


			/*
			sqlite3_exec(this.db, "CREATE UNIQUE INDEX words_before_index ON words_before (word, word1, word2)", null, null, null);
			sqlite3_exec(this.db, "CREATE UNIQUE INDEX words_after_index  ON words_after  (word, word1, word2)", null, null, null);
			*/
		} else {
			this.db = new Database(dbfile);
			this.db.updateTablesList();
		}
	}

	int word_id(string word) {
		if (word.length == 0) {
			return 0;
		}

		word = word.toLower();

		Row[] results = this.db["words"].select(["word_id"], "word=?", Variant(word));
		if (results.length == 1) {
			return results[0]["word_id"]().get!(int);
		}

		db["words"].insert([Variant(word)], ["word"]);
		results = this.db["words"].select(["word_id"], "word=?", Variant(word));
		if (results.length == 1) {
			return results[0]["word_id"]().get!(int);
		}

		return 0;
	}

	string word(int word_id) {
		Variant result = this.db["words"].value(["word"], "word_id=?", Variant(word_id));

		if (!result.peek!string) {
			return "";
		} else {
			return result.get!string;
		}
	}

	void learn_chain(int word2b, int word1b, int word, int word1a, int word2a) {
		/+
		Variant result = this.db["words_before"].value(["frequency"], "word=? AND word1=? AND word2=?", Variant(word), Variant(word1b), Variant(word2b));

		int frequency = 0;
		if (!result.peek!int) {
		+/
			db["words_before"].insert([Variant(word2b), Variant(word1b), Variant(word), Variant(1)], ["word2", "word1", "word", "frequency"]);
		/+
		} else {
			frequency = result.get!int + 1;
			db["words_before"].update("frequency=?", "word=? AND word1=? AND word2=?", [Variant(frequency), Variant(word), Variant(word1b), Variant(word2b)]);
		}
		+/
		
		//Variant result = this.db["words_after"].value(["frequency"], "word=? AND word1=? AND word2=?", Variant(word), Variant(word1a), Variant(word2a));

		//int frequency = 0;
		//if (!result.peek!int) {
			db["words_after"].insert([Variant(word2a), Variant(word1a), Variant(word), Variant(1)], ["word2", "word1", "word", "frequency"]);
		//} else {
		//	frequency = result.get!int + 1;
		//	db["words_after"].update("frequency=?", "word=? AND word1=? AND word2=?", [Variant(frequency), Variant(word), Variant(word1a), Variant(word2a)]);
		//}
	}

	void learn(string human_sentence) {
		human_sentence = std.array.replace(human_sentence, " (", ". ");
		human_sentence = std.array.replace(human_sentence, ") ", ". ");

		if (human_sentence.length > 1 && human_sentence[$-1] != '.' && human_sentence[$-1] != '!' && human_sentence[$-1] != '?') {
			human_sentence ~= ".";
		}

		foreach (string sub_sentence; human_sentence.split(". ")) {
			string[] words = this.parse_sentence(sub_sentence);

			if (words.length < 3) {
				continue;
			}

			words[0] = words[0].toLower();

			foreach (int position, string sentence_word ; words) {
				string word1_b = position > 0 ? words[position-1] : "";
				string word2_b = position > 1 ? words[position-2] : "";
				string word1_a = position < words.length - 1 ? words[position+1] : "";
				string word2_a = position < words.length - 2 ? words[position+2] : "";

				this.learn_chain(this.word_id(word2_b), this.word_id(word1_b), this.word_id(sentence_word), this.word_id(word1_a), this.word_id(word2_a));
			}
		}
	}

	string[] parse_sentence(string sentence) {
		string[] words;

		// We don't want <a href="http://plop">[url]</a> to be split up
		sentence = std.array.replace(sentence, "<a href", "<a_href");

		enum is_clock = ctRegex!(`..:..:..`);
		enum is_junk = ctRegex!(`[=+(){}/|\\*@~^<>&;]`);
		enum is_url = ctRegex!(`href=`);

		sentence = sentence.removechars("\"");
		
		foreach (string word; sentence.split(" ")) {
			if (word == " ") {
				continue;
			}

			if (word.length > 1 && word[$-1] == '<') {
				// This is a tribune nickname.
				words ~= "<nickname>";
				continue;
			}

			if (match(word, is_clock)) {
				continue;
			}

			if (match(word, is_junk)) {
				continue;
			}

			if (match(word, is_url)) {
				words ~= "<url>";
				continue;
			}

			words ~= word;
		}

		while (words.length > 0 && words[0] == "#") {
			words = words[1 .. $];
		}

		return words;
	}

	int word_rarity(int word_id) {
		Variant resulta = this.db["words_after"].value(["SUM(frequency)"], "word=? GROUP BY word", Variant(word_id));
		Variant resultb = this.db["words_before"].value(["SUM(frequency)"], "word=? GROUP BY word", Variant(word_id));

		return resulta.get!int + resultb.get!int;
	}

	int rarest_word(string sentence) {
		string[] words = this.parse_sentence(sentence);

		size_t min_rarity = 0;
		int rarest_word = 0;
		foreach (string word; words) {
			auto rarity = this.word_rarity(this.word_id(word));

			if (rarity < 2) {
				// An unknown word is not "rare", it is unknown.
				// And a word only seen once is still too rare to use.
				continue;
			}

			if (min_rarity == 0
			    || rarity < min_rarity
			    || (rarity == min_rarity && dice(1, 1))) {
				min_rarity = rarity;
				rarest_word =this.word_id(word);
			}
		}

		return rarest_word;
	}

	string sanitize_answer(string sentence) {
		sentence = std.array.replace(sentence, "''", "'");
		sentence = std.array.replace(sentence, "# ", " ");
		sentence = std.array.replace(sentence, "&lt;", "<");
		sentence = std.array.replace(sentence, "&gt;", ">");
		sentence = std.array.replace(sentence, "&amp;", "&");
		sentence = std.array.replace(sentence, "?", " ?");
		sentence = std.array.replace(sentence, "!", " !");
		sentence = std.array.replace(sentence, "  ", " ");

		if (this.user) {
			sentence = std.array.replace(sentence, "<nickname>", this.user ~ "<");
		}

		sentence = std.array.replace(sentence, "<url>", "<b><u>[url]</u></b>");

		return sentence;
	}

	int[] get_initial_sentence(int seed, int length) {
		return [seed];


		int[][] sentences;

		/*
		if (seed in this.words && this.words[seed].length) {
			foreach (Word occurence; this.words[seed]) {
				if (occurence.sentence.author != this.user && occurence.sentence.words.length >= length) {
					if (occurence.position <= length) {
						// seed is within the length first words
						sentences ~= occurence.sentence.words[0 .. length];
					} else if (occurence.sentence.words.length - occurence.position < length) {
						// seed is within the length last words
						sentences ~= occurence.sentence.words[$-length .. $];
					} else {
						// then seed will have at least length words before it and length words after it
						int offset = length/2 + 1;
						sentences ~= occurence.sentence.words[occurence.position-length+offset .. occurence.position+offset];
					}
				}
			}
		}
		*/

		foreach (Row row; this.db["words_before"].select(["word", "word1", "word2"], "word=?", Variant(seed))) {
		}

		if (sentences.length == 1) {
			return sentences[0];
		} else if (sentences.length > 1) {
			return sentences[uniform(0, sentences.length - 1)];
		} else {
			return [];
		}
	}

	size_t[int] candidates_before(int word, int word1 = 0) {
		size_t[int] candidates;

		string[] conditions;
		Variant[] values;

		conditions ~= "word1=?";
		values ~= Variant(word);

		if (word1) {
			conditions ~= "word2=?";
			values ~= Variant(word1);
		}

		// This is a bit tricky:
		// Since we're looking for words that should come before [word, word1], we
		// have to look in the words_after table, for words that have [word, word1]
		// as their following words.
		// The words_after and words_before tables are redundant though, and I'll have
		// to get rid of one of them later.
		foreach (Row row; this.db["words_after"].select(["word"], conditions.join(" AND "), values)) {
			int candidate = row["word"]().get!int;
			if (candidate !in candidates) {
				candidates[candidate] = 0;
			}
			candidates[candidate]++;
		}

		return candidates;
	}

	size_t[int] candidates_after(int word, int word1 = 0) {
		size_t[int] candidates;

		Row[] result;

		if (word1) {
			result = this.db["words_after"].select(["word2"], "word1=? AND word=?", Variant(word), Variant(word1));
		} else {
			result = this.db["words_after"].select(["word1"], "word=?", Variant(word));
		}

		foreach (Row row; result) {
			int candidate = row[0]().get!int;
			if (candidate !in candidates) {
				candidates[candidate] = 0;
			}
			candidates[candidate]++;
		}

		return candidates;
	}

	int complete_before(int[] sentence) {
		size_t[int] candidates;

		switch (sentence.length) {
			case 0:
				return 0;
			case 1:
				candidates = this.candidates_before(sentence[0]);
				break;
			case 2:
			default:
				candidates = this.candidates_before(sentence[0], sentence[1]);
				break;
		}

		debug(deeborg) stderr.writeln("Backward candidates for ", sentence, ": ", candidates);

		if (candidates.length) {
			auto index = dice(candidates.values);
			return candidates.keys[index];
		}
		
		return 0;
	}

	int complete_after(int[] sentence) {
		size_t[int] candidates;

		switch (sentence.length) {
			case 0:
				return 0;
			case 1:
				candidates = this.candidates_after(sentence[$-1]);
				break;
			case 2:
			default:
				candidates = this.candidates_after(sentence[$-1], sentence[$-2]);
				break;
		}

		if (candidates.length) {
			auto index = dice(candidates.values);
			return candidates.keys[index];
		}
		
		return 0;
	}

	string sentence(int[] words) {
		string[] sentence;

		foreach (int word_id; words) {
			sentence ~= this.word(word_id);
		}

		return sentence.join(" ");
	}

	string answer(string sentence) {
		int seed = this.rarest_word(sentence);

		debug(deeborg) stderr.writeln("Rarest word is ", seed);

		if (!seed) {
			// Seems like there is no answer to give.
			return "";
		}

		int[] answer = this.get_initial_sentence(seed, LOOKAHEAD_DEPTH);

		debug(deeborg) stderr.writeln("Initial sentence is ", this.sentence(answer));
		
		if (!answer.length) {
			return "";
		}

		auto init_length = answer.length;

		int s;
		while ((s = this.complete_before(answer)) > 0) {
			answer = [s] ~ answer;
		}

		debug(deeborg) stderr.writeln("Backward-completed sentence is ", this.sentence(answer));

		while ((s = this.complete_after(answer)) > 0) {
			answer ~= s;
		}

		debug(deeborg) stderr.writeln("Forward-completed sentence is ", this.sentence(answer));

		if (answer.length > init_length) {
			return this.sanitize_answer(this.sentence(answer));
		} else {
			return "";
		}
	}
}

