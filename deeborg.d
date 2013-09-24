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

enum Direction {forward, backward};

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
	
	--handle=<author handle>    if learning is enabled, handle of the person talking
	                            the bot will not use sentences said by this person
	                            for its answers
	
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

	LOOKAHEAD_DEPTH = depth;

	Bot bot = new Bot();
	bot.user = std.array.replace(handle, "\t", " ");

	if (exists(statefile)) {
		string state;
		state = cast(string)read(statefile);
		bot.load_state(state);
	}

	string sentence;
	while ((sentence = stdin.readln()) !is null) {
		sentence = strip(sentence);

		if (answer) {
			string answer_sentence = bot.answer(sentence);

			// This is a crude way to ensure that sentences end mostly correctly.
			int tries = 0;
			while (answer_sentence.length > 1 && answer_sentence[$-1] != '.' && tries < 20) {
				tries++;
				answer_sentence = bot.answer(sentence);
			}

			stdout.writeln(answer_sentence);
		}

		if (learn) {
			bot.learn(sentence);
		}
	}

	string state = bot.save_state();
	std.file.write(statefile, state);

	return 0;
}

class Sentence {
	string[] words;
	string author;

	this() {}

	this(string[] data) {
		this.author = data[1];
		this.words = split(data[2]);
		this._id = data[0][1..$];
	}

	string _id = null;
	string id() {
		if (this._id is null) {
			this._id = crcHexString(digest!CRC32(this.words.join(" ")));
		}

		return this._id;
	}
}

class Word {
	string text;
	Sentence sentence;
	int position;

	this() {}

	this(string[] data) {
		this.text = data[0];
		this.position = parse!int(data[1]);
	}
}

class Bot {
	Sentence[string] sentences;
	Word[string][string] words;
	string user = "#";

	this() {
	}

	string save_state() {
		int[string] printed_sentences;

		string state_words;
		string state_sentences;

		foreach (string word_text, Word[string] words; this.words) {
			state_words ~= word_text;

			foreach (Word word; words) {
				state_words ~= format("\t%s:%s", word.sentence.id, word.position);
				
				if (word.sentence.id !in printed_sentences) {
					printed_sentences[word.sentence.id] = 1;
					state_sentences ~= format(" %s\t%s\t%s\n", word.sentence.id, word.sentence.author, word.sentence.words.join(" "));
				}
			}

			state_words ~= '\n';
		}

		return state_sentences ~ state_words;
	}

	void load_state(string state) {
		foreach (string line; state.splitLines()) {
			if (line.length == 0) {
				continue;
			}

			string[] data = line.split("\t");
			if (line[0] == ' ') {
				// That's a sentence
				this.sentences[data[0][1..$]] = new Sentence(data);
			} else {
				// That's a word
				string text = data[0];
				foreach (string reference; data[1..$]) {
					//string[] parts = reference.split(":");
					if (reference.length > 9) {
						string[] parts = [reference[0..8], reference[9..$]];

						Word word = new Word();
						word.text = text;
						word.sentence = this.sentences[parts[0]];
						word.position = parse!int(parts[1]);
						this.words[word.text][word.sentence.id] = word;
					} else {
						stderr.writeln("Buggy reference for word ", text, ": ", reference);
					}
				}
			}
		}
	}

	void learn(string human_sentence) {
		human_sentence = std.array.replace(human_sentence, "?", "?. ");
		human_sentence = std.array.replace(human_sentence, "!", "!. ");
		human_sentence = std.array.replace(human_sentence, " (", ". ");
		human_sentence = std.array.replace(human_sentence, ") ", ". ");

		foreach (string sub_sentence; human_sentence.split(". ")) {
			Sentence sentence = new Sentence();
			sentence.author = this.user ? this.user : "#";
			sentence.words = this.parse_sentence(sub_sentence);

			if (sentence.words.length < 3) {
				continue;
			}

			sentence.words[0] = sentence.words[0].toLower();

			if (sentence.id in this.sentences) {
				sentence = this.sentences[sentence.id];
			} else {
				this.sentences[sentence.id] = sentence;
			}

			foreach (int position, string sentence_word ; sentence.words) {
				Word word = new Word();
				word.text = sentence_word;
				word.sentence = sentence;
				word.position = position;

				if (sentence_word != "#") {
					this.words[sentence_word][sentence.id] = word;
				}
			}
		}

		int forgotten = 0;
		int min_popularity = 0;
		while (this.words.length > 50000) {
			// Some cleanup to do here.

			min_popularity++;
			foreach (string word_text, Word[string] sentences; this.words) {
				if (sentences.length <= min_popularity) {
					this.words.remove(word_text);
					forgotten++;
				}

				if (this.words.length <= 50000) {
					break;
				}
			}
		}
	}

	string[] parse_sentence(string sentence) {
		string[] words;

		sentence = std.array.replace(sentence, " ?", "?");
		sentence = std.array.replace(sentence, " !", "!");

		enum is_word = ctRegex!(`\pL`);
		enum is_junk = ctRegex!(`[=+(){}#/|\\*@~^<>&;]`);
		enum is_url = ctRegex!(`^href=`);

		sentence = sentence.removechars("\"");
		
		foreach (string word; sentence.split(" ")) {
			if (word.length > 1 && word[$-1] == '<') {
				// This is a tribune nickname.
				words ~= "#";
				continue;
			}

			if (!match(word, is_word)) {
				words ~= "#";
				continue;
			}

			if (match(word, is_junk)) {
				words ~= "#";
				continue;
			}

			if (match(word, is_url)) {
				words ~= "#";
				continue;
			}

			words ~= word;
		}

		while (words.length > 0 && words[0] == "#") {
			words = words[1 .. $];
		}

		return words;
	}

	auto word_rarity(string word) {
		if (word in this.words) {
			return this.words[word].length;
		} else {
			return 0;
		}
	}

	string rarest_word(string sentence) {
		string[] words = this.parse_sentence(sentence);

		size_t min_rarity = 0;
		string rarest_word = null;
		foreach (string word; words) {
			auto rarity = this.word_rarity(word);

			if (rarity < 2) {
				// An unknown word is not "rare", it is unknown.
				// And a word only seen once is still too rare to use.
				continue;
			}

			if (min_rarity == 0
			    || rarity < min_rarity
			    || (rarity == min_rarity && dice(1, 1))) {
				min_rarity = rarity;
				rarest_word = word;
			}
		}

		return rarest_word;
	}

	string sanitize_answer(string sentence) {
		sentence = std.array.replace(sentence, "''", "'");
		sentence = std.array.replace(sentence, "#", "");
		sentence = std.array.replace(sentence, "&lt;", "<");
		sentence = std.array.replace(sentence, "&gt;", ">");
		sentence = std.array.replace(sentence, "&amp;", "&");
		sentence = std.array.replace(sentence, "?", " ?");
		sentence = std.array.replace(sentence, "!", " !");

		return sentence;
	}

	string[] get_initial_sentence(string seed, int length) {
		string[][] sentences;

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

		if (sentences.length == 1) {
			return sentences[0];
		} else if (sentences.length > 1) {
			return sentences[uniform(0, sentences.length - 1)];
		} else {
			return [];
		}
	}

	string complete_before(string[] sentence, int depth) {
		size_t[string] candidates;

		string[] reference = sentence[0 .. min(depth, sentence.length)];

		if (sentence[0] in this.words && this.words[sentence[0]].length) {
			foreach (Word occurence; this.words[sentence[0]]) {
				if (occurence.sentence.author != this.user && occurence.sentence.words.length >= occurence.position + reference.length && occurence.position > 0) {
					if (occurence.sentence.words[occurence.position .. occurence.position + reference.length] == reference) {
						string word = occurence.sentence.words[occurence.position - 1];
						if (word in this.words && this.words[word].length > 1) {
							if (word !in candidates) {
								candidates[word] = 0;
							}

							candidates[word] = this.words[word].length;

							if (reference.length > 1) {
								string next_word = occurence.sentence.words[occurence.position + 1];
								if (next_word in this.words) {
									candidates[word] += this.words[next_word].length;
								}
							}

							// Boost score of first words.
							if (occurence.position == 0) {
								candidates[word] *= 2;
							}
						}
					}
				}
			}
		}

		if (candidates.length) {
			auto index = dice(candidates.values);
			return candidates.keys[index];
		}
		
		return null;
	}

	string complete_after(string[] sentence, int depth) {
		size_t[string] candidates;

		string[] reference = sentence[max(sentence.length - depth, 0) .. $];

		if (sentence[$-1] in this.words && this.words[sentence[$-1]].length) {
			foreach (Word occurence; this.words[sentence[$-1]]) {
				if (occurence.sentence.author != this.user && occurence.position >= reference.length - 1 && occurence.sentence.words.length > occurence.position + 1) {
					if (occurence.sentence.words[occurence.position - reference.length + 1 .. occurence.position + 1] == reference) {
						string word = occurence.sentence.words[occurence.position + 1];

						if (word in this.words && this.words[word].length > 1) {
							auto score = this.words[word].length;

							if (occurence.position == occurence.sentence.words.length - 2) {
								word ~= ".";
							}

							if (reference.length > 1) {
								string previous_word = occurence.sentence.words[occurence.position];
								if (previous_word in this.words) {
									score += this.words[previous_word].length;
								}
							}

							// Boost score of last words.
							if (occurence.position == occurence.sentence.words.length - 1) {
								score *= 2;
							}

							if (word !in candidates) {
								candidates[word] = 0;
							}
							candidates[word] = score;
						}
					}
				}
			}
		}

		if (!candidates.length && depth > 2) {
			string candidate = complete_after(sentence, depth - 1);
			if (candidate) {
				candidates[candidate] = 1;
			}
		}

		if (candidates.length) {
			auto index = dice(candidates.values);
			return candidates.keys[index];
		}
		
		return null;
	}

	string answer(string sentence) {
		string seed = this.rarest_word(sentence);

		if (seed is null) {
			// Seems like there is no answer to give.
			return "";
		}

		string[] answer = this.get_initial_sentence(seed, LOOKAHEAD_DEPTH);
		
		if (!answer.length) {
			return "";
		}

		string s;
		while ((s = this.complete_before(answer, LOOKAHEAD_DEPTH)) !is null) {
			answer = [s] ~ answer;
		}

		while ((s = this.complete_after(answer, LOOKAHEAD_DEPTH)) !is null) {
			answer ~= s;
		}

		return this.sanitize_answer(answer.join(" "));
	}
}

