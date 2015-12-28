module deeborg.bot;

private import deeborg.botdatabase;
private import deeborg.botdatabasesqlite;

import std.stdio;
import std.string;
import std.random;
import std.digest.crc;
import std.conv;
import std.file;
import std.regex;
import std.algorithm;
import std.math;

import sqlite.database, sqlite.exception, sqlite.statement, sqlite.table;

class Bot {
	BotDatabase db;
	string user = "";
	int depth = 3;

	this(string dbfile) {
		this.db = new BotDatabaseSqlite(dbfile);
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

			this.db.learn_sentence(words);
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

			if (word.length > 1 && word[$-1] == '<' && word != "moules<") {
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

	string sanitize_answer(string sentence) {
		sentence = std.array.replace(sentence, "''", "'");
		sentence = std.array.replace(sentence, "# ", " ");
		sentence = std.array.replace(sentence, "&lt;", "<");
		sentence = std.array.replace(sentence, "&gt;", ">");
		sentence = std.array.replace(sentence, "&amp;", "&");
		sentence = std.array.replace(sentence, "?", " ?");
		sentence = std.array.replace(sentence, "!", " !");
		sentence = std.array.replace(sentence, "  ", " ");

		if (this.user && dice(75, 25)) {
			sentence = std.array.replace(sentence, "<nickname>", this.user ~ "<");
		} else {
			sentence = std.array.replace(sentence, "<nickname>", "toi");
		}

		sentence = std.array.replace(sentence, "<url>", "<b><u>[url]</u></b>");

		return sentence;
	}

	string[] get_initial_sentence(string seed, int length) {
		return [seed];

		/+

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
		+/
	}

	string complete_before(string[] sentence) {
		size_t[string] candidates = this.db.candidates_before(sentence);

		debug(deeborg) stderr.writeln("Backward candidates for ", sentence, ": ", candidates);

		if (candidates && candidates.length) {
			auto index = dice(candidates.values);
			return candidates.keys[index];
		}
		
		return "";
	}

	string complete_after(string[] sentence) {
		size_t[string] candidates = this.db.candidates_after(sentence);

		debug(deeborg) stderr.writeln("Forward candidates for ", sentence, ": ", candidates);

		if (candidates && candidates.length) {
			auto index = dice(candidates.values);
			return candidates.keys[index];
		}
		
		return "";
	}

	string answer(string sentence) {
		string seed = this.db.rarest_word(this.parse_sentence(sentence));

		debug(deeborg) stderr.writeln("Rarest word is ", seed);

		if (!seed) {
			// Seems like there is no answer to give.
			return "";
		}

		string[] answer = this.get_initial_sentence(seed, this.depth);

		if (!answer.length) {
			return "";
		}

		auto init_length = answer.length;

		string s;
		while ((s = this.complete_before(answer)) != "") {
			answer = [s] ~ answer;
		}

		while ((s = this.complete_after(answer)) != "") {
			answer ~= s;
		}

		if (answer.length > init_length) {
			return this.sanitize_answer(answer.join(" "));
		} else {
			return "";
		}
	}
}
