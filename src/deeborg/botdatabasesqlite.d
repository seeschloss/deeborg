module deeborg.botdatabasesqlite;

import deeborg.botdatabase;

private import sqlite.database, sqlite.exception, sqlite.statement, sqlite.table;

private import std.stdio;

private import std.file : exists;
private import std.random : dice;
private import std.array : join;
private import std.string : toLower;

class BotDatabaseSqlite : BotDatabase {
	private Database db;

	this(string dbfile) {
		if (!std.file.exists(dbfile)) {
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


			this.db.command("CREATE INDEX words_before_index ON words_before (word, word1, word2);");
			this.db.command("CREATE INDEX words_after_index  ON words_after  (word, word1, word2);");
		} else {
			this.db = new Database(dbfile);
			this.db.updateTablesList();
		}
	}

	void learn_sentence(string[] words) {
		debug(deeborg) stderr.writeln("Learning sentence: ", words);

		foreach (int position, string sentence_word ; words) {
			string word1_b = position > 0 ? words[position-1] : "";
			string word2_b = position > 1 ? words[position-2] : "";
			string word1_a = position < words.length - 1 ? words[position+1] : "";
			string word2_a = position < words.length - 2 ? words[position+2] : "";

			this.learn_chain(this.word_id(word2_b), this.word_id(word1_b), this.word_id(sentence_word), this.word_id(word1_a), this.word_id(word2_a));
		}
	}

	string rarest_word(string[] words) {
		size_t min_rarity = 0;
		int rarest_word_id = 0;
		foreach (string word; words) {
			auto rarity = this.word_rarity(this.word_id(word));

			if (rarity < 2) {
				if (rarity == 0) {
					debug(deeborg) stderr.writeln("Word with no frequency was ", word);
				}
				// An unknown word is not "rare", it is unknown.
				// And a word only seen once is still too rare to use.
				continue;
			}

			if (word.length < 4) {
				// Also, let's ignore small words.
				continue;
			}

			if (min_rarity == 0
			    || rarity < min_rarity
			    || (rarity == min_rarity && dice(1, 1))) {
				min_rarity = rarity;
				rarest_word_id = this.word_id(word);
			}
		}

		return this.word_string(rarest_word_id);
	}

	size_t[string] candidates_before(string[] words) {
		if (words.length < 1) {
			return null;
		}

		size_t[string] candidates;

		string[] conditions;
		Variant[] values;

		conditions ~= "word1=?";
		values ~= Variant(this.word_id(words[0]));

		if (words.length > 1) {
			conditions ~= "word2=?";
			values ~= Variant(this.word_id(words[1]));
		}

		debug(deeborg) stderr.writeln("Looking for candidates: ", conditions.join(" AND "), " / ", values, " - ", words);

		// This is a bit tricky:
		// Since we're looking for words that should come before [word, word1], we
		// have to look in the words_after table, for words that have [word, word1]
		// as their following words.
		// The words_after and words_before tables are redundant though, and I'll have
		// to get rid of one of them later.
		foreach (Row row; this.db["words_after"].select(["word", "frequency"], conditions.join(" AND "), values)) {
			string candidate = this.word_string(row["word"]().get!int);

			// Ignore words repeated three times.
			if (words.length > 1 && candidate == words[0] && candidate == words[1]) {
				continue;
			}

			if (candidate !in candidates) {
				candidates[candidate] = 0;
			}
			candidates[candidate] += row[1]().get!int;
		}

		return candidates;
	}

	size_t[string] candidates_after(string[] words) {
		if (words.length < 1) {
			return null;
		}

		size_t[string] candidates;

		string[] conditions;
		Variant[] values;
		string select;

		if (words.length > 1) {
			conditions ~= "word=?";
			values ~= Variant(this.word_id(words[$-2]));

			conditions ~= "word1=?";
			values ~= Variant(this.word_id(words[$-1]));

			select = "word2";
		} else {
			conditions ~= "word=?";
			values ~= Variant(this.word_id(words[$-1]));

			select = "word1";
		}

		debug(deeborg) stderr.writeln("Looking for candidates: ", conditions.join(" AND "), " / ", values, " - ", words[$-1]);

		foreach (Row row; this.db["words_after"].select([select, "frequency"], conditions.join(" AND "), values)) {
			string candidate = this.word_string(row[0]().get!int);

			// Ignore words repeated three times.
			if (words.length > 1 && candidate == words[$-2] && candidate == words[$-1]) {
				continue;
			}

			if (candidate !in candidates) {
				candidates[candidate] = 0;
			}
			candidates[candidate] += row[1]().get!int;
		}

		return candidates;
	}


	private int word_rarity(int word_id) {
		Variant resulta = this.db["words_after"].value(["SUM(frequency)"], "word=? GROUP BY word", Variant(word_id));
		Variant resultb = this.db["words_before"].value(["SUM(frequency)"], "word=? GROUP BY word", Variant(word_id));

		if (!resulta.peek!int || !resultb.peek!int) {
			// Well, this shouldn't happen.
			debug(deeborg) stderr.writeln("For some reason, word #", word_id, " has no frequency? ", resulta, "/", resultb);
			return 0;
		}

		return resulta.get!int + resultb.get!int;
	}

	private int word_id(string word) {
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

	private string word_string(int word_id) {
		Variant result = this.db["words"].value(["word"], "word_id=?", Variant(word_id));

		if (!result.peek!string) {
			return "";
		} else {
			return result.get!string;
		}
	}

	private void learn_chain(int word2b, int word1b, int word, int word1a, int word2a) {
		Variant result = this.db["words_before"].value(["frequency"], "word=? AND word1=? AND word2=?", Variant(word), Variant(word1b), Variant(word2b));

		int frequency = 0;
		if (!result.peek!int) {
			db["words_before"].insert([Variant(word2b), Variant(word1b), Variant(word), Variant(1)], ["word2", "word1", "word", "frequency"]);
		} else {
			frequency = result.get!int + 1;
			db["words_before"].update("frequency=?", "word=? AND word1=? AND word2=?", [Variant(frequency), Variant(word), Variant(word1b), Variant(word2b)]);
		}
		
		result = this.db["words_after"].value(["frequency"], "word=? AND word1=? AND word2=?", Variant(word), Variant(word1a), Variant(word2a));

		frequency = 0;
		if (!result.peek!int) {
			db["words_after"].insert([Variant(word2a), Variant(word1a), Variant(word), Variant(1)], ["word2", "word1", "word", "frequency"]);
		} else {
			frequency = result.get!int + 1;
			db["words_after"].update("frequency=?", "word=? AND word1=? AND word2=?", [Variant(frequency), Variant(word), Variant(word1a), Variant(word2a)]);
		}
	}
}

