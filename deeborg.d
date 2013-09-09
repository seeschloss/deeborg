import std.stdio;
import std.string;
import std.random;
import std.digest.crc;
import std.conv;
import std.file;
import std.regex;
import std.getopt;
import std.zlib;

void help() {
	stdout.writeln(q"#Usage: deeborg [--file=<word database>] [--learn=false] [--answer=false]

	--file=<word database>  read <word database> to create answers and update
	                        it with new sentences
	--learn=false           do not learn new sentences
	                        (true by default, ie learn new sentences)
	--answer=false          do not answer fed sentences
	                        (true by default, ie answer each sentence fed)

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
	string statefile = "deeborg.state";

	try {
		getopt(
			args,
			"learn", &learn,
			"answer", &answer,
			"file", &statefile
		);
	} catch (Exception e) {
		help();
		return 1;
	}

	Bot bot = new Bot();

	if (exists(statefile)) {
		string state;
		state = cast(string)read(statefile);
		bot.load_state(state);
	}

	string sentence;
	while ((sentence = stdin.readln()) !is null) {
		sentence = strip(sentence);

		if (answer) {
			stdout.writeln(bot.answer(sentence));
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
	int times;

	this() {}

	this(string[] data) {
		this.times = parse!int(data[1]);
		this.words = split(data[2]);
		this._hash = data[0][1..$];
	}

	string _hash = null;
	string hash() {
		if (this._hash is null) {
			this._hash = crcHexString(digest!CRC32(this.words.join(" ")));
		}

		return this._hash;
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

	this() {
	}

	string save_state() {
		int[string] printed_sentences;

		string state_words;
		string state_sentences;

		foreach (string word_text, Word[string] words; this.words) {
			state_words ~= word_text;

			foreach (Word word; words) {
				state_words ~= format("\t%s:%s", word.sentence.hash, word.position);
				
				if (word.sentence.hash !in printed_sentences) {
					printed_sentences[word.sentence.hash] = 1;
					state_sentences ~= format(" %s\t%s\t%s\n", word.sentence.hash, word.sentence.times, word.sentence.words.join(" "));
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
						this.words[word.text][word.sentence.hash] = word;
					} else {
						stderr.writeln("Buggy reference for word ", text, ": ", reference);
					}
				}
			}
		}
	}

	void learn(string human_sentence) {
		foreach (string sub_sentence; human_sentence.split(".")) {
			Sentence sentence = new Sentence();
			sentence.words = this.parse_sentence(sub_sentence);

			if (sentence.hash in this.sentences) {
				sentence = this.sentences[sentence.hash];
				sentence.times++;
			} else {
				sentence.times = 1;
				this.sentences[sentence.hash] = sentence;
			}

			foreach (int position, string sentence_word ; sentence.words) {
				Word word = new Word();
				word.text = sentence_word;
				word.sentence = sentence;
				word.position = position;

				this.words[sentence_word][sentence.hash] = word;
			}
		}
	}

	string[] parse_sentence(string sentence) {
		string[] words;

		enum is_word = ctRegex!(`\pL`);
		enum is_junk = ctRegex!(`[=+\[\](){}#/|\\*@~^<>]`);
		enum is_url = ctRegex!(`^(<a|href=)`);
		enum is_unbalanced = ctRegex!(`^(<[^>]*)|([^<]*>)$`);

		sentence = sentence.removechars("\"");
		
		foreach (string word; split(sentence)) {
			if (!match(word, is_word)) {
				continue;
			}

			if (match(word, is_junk)) {
				continue;
			}

			if (match(word, is_url)) {
				continue;
			}

			if (match(word, is_unbalanced)) {
				continue;
			}

			words ~= word;
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

		typeof([].length) min_rarity = 0;
		string rarest_word = null;
		foreach (string word; words) {
			auto rarity = this.word_rarity(word);

			if (rarity == 0) {
				// An unknown word is not "rare", it is unknown.
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

	string previous_word(string word, string[] sentence) {
		int[string] previous_words;
		if (word !in this.words) {
			stderr.writeln("Word not found: ", word);
			return null;
		}

		foreach (Word candidate; this.words[word]) {
			if (candidate.position > 0 && candidate.sentence.words.length > 0) {
				// We are unlikely to find a previous word if this
				// word is the first, right?

				if (sentence.length > 1
				    && candidate.sentence.words.length > candidate.position+1) {
					// We already have a small length of sentence
					// and this candidate word is not at the end of
					// its own original sentence, so let's look for
					// a sentence in which this word is followed by
					// the same word it is followed by in our answer.
				    if (sentence[1] != candidate.sentence.words[candidate.position+1]) {
						// Not this time
						continue;
					}
				}

				// When we arrive here, we are either looking for the
				// very first word in our answer, or we have found a
				// word that is followed by the same word it will be
				// followed by in our answer. Is that clear?

				string previous_word = candidate.sentence.words[candidate.position-1];
				if (previous_word !in previous_words) {
					previous_words[previous_word] = 0;
				}

				previous_words[previous_word] += candidate.sentence.times;
			}
		}

		if (previous_words.values.length == 0) {
			// No previous word to say.
			return null;
		}

		int[string] words_in_sentence;
		foreach (string sentence_word; sentence) {
			words_in_sentence[sentence_word] = 1;
		}

		string previous_word = null;
		auto max_tries = previous_words.values.length;
		typeof(max_tries) tries = 0;

		do {
			tries++;

			// Choose a random word from the list of candidates.
			// Pyborg just takes the one with the highest score, but
			// we will choose one randomly, here, although we will
			// still favour the ones with the highest score.
			auto index = dice(previous_words.values);
			previous_word = previous_words.keys[index];
		} while (previous_word in words_in_sentence && tries <= max_tries);

		return tries <= max_tries ? previous_word : null;
	}

	string next_word(string word, string[] sentence) {
		int[string] next_words;
		if (word !in this.words) {
			stderr.writeln("Word not found: ", word);
			return null;
		}

		foreach (Word candidate; this.words[word]) {
			if (candidate.position < candidate.sentence.words.length - 1) {
				// We are unlikely to find a next word if this
				// word is the last, right?

				if (sentence.length > 1
				    && candidate.position > 1) {
					// We already have a small length of sentence
					// and this candidate word is not at the beginning of
					// its own original sentence, so let's look for
					// a sentence in which this word is preceeded by
					// the same word it is preceeded by in our answer.
				    if (sentence[$-2] != candidate.sentence.words[candidate.position-1]) {
						// Not this time
						continue;
					}
				}

				// When we arrive here, we are either looking for the
				// very first word in our answer, or we have found a
				// word that is preceeded by the same word it will be
				// preceeded by in our answer. Is that clear?

				string next_word = candidate.sentence.words[candidate.position+1];
				if (next_word !in next_words) {
					next_words[next_word] = 0;
				}

				next_words[next_word] += candidate.sentence.times;
			}
		}

		if (next_words.values.length == 0) {
			// No next word to say.
			return null;
		}

		int[string] words_in_sentence;
		foreach (string sentence_word; sentence) {
			words_in_sentence[sentence_word] = 1;
		}

		string next_word = null;
		auto max_tries = next_words.values.length;
		typeof(max_tries) tries = 0;

		do {
			tries++;

			// Choose a random word from the list of candidates.
			// Pyborg just takes the one with the highest score, but
			// we will choose one randomly, here, although we will
			// still favour the ones with the highest score.
			auto index = dice(next_words.values);
			next_word = next_words.keys[index];
		} while (next_word in words_in_sentence && tries <= max_tries);

		return tries <= max_tries ? next_word : null;
	}

	string sanitize_answer(string sentence) {
		sentence = std.array.replace(sentence, "''", "'");
		sentence = std.array.replace(sentence, "&lt;", "<");
		sentence = std.array.replace(sentence, "&gt;", ">");
		sentence = std.array.replace(sentence, "&amp;", "&");

		return sentence;
	}

	string answer(string sentence) {
		string seed = this.rarest_word(sentence);

		if (seed is null) {
			// Seems like there is no answer to give.
			return "";
		}

		string[] answer = [seed];

		string previous = null;
		while ((previous = this.previous_word(answer[0], answer)) !is null) {
			answer = [previous] ~ answer;
		}

		string next = null;
		while ((next = this.next_word(answer[$-1], answer)) !is null) {
			answer ~= next;
		}

		string final_answer = answer.join(" ");

		return this.sanitize_answer(final_answer);
	}
}

