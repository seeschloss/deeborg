import std.stdio;
import std.string;
import std.random;
import std.conv;
import std.file;
import std.regex;
import std.getopt;
import std.algorithm;
import std.math;
import std.datetime;

import core.memory;

immutable WORD_POPULARITY_THRESHOLD = 2;
int LOOKAHEAD_DEPTH = 2;

void help() {
	stdout.writeln(q"#Usage: deeborg  [options ...]

	--file=<word database>      read <word database> to create answers and update
	                            it with new sentences
	                            ("deeborg.state" in current directory by default)

	--learn=<true|false>        do not learn new sentences
	                            (true by default, ie learn new sentences)

	--answer=<true|false>       do not answer fed sentences
	                            (true by default, ie answer each sentence fed)

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
			"file", &statefile
		);
	} catch (Exception e) {
		help();
		return 1;
	}

	LOOKAHEAD_DEPTH = depth;

	Bot bot = new Bot();
	
	if (exists(statefile)) {
		auto time = Clock.currTime();
		debug(running) {stderr.writeln("Reading statefile ", statefile, "...");}
		string state = cast(string)read(statefile);
		debug(running) {stderr.writeln("State read (", Clock.currTime() - time, ").");}
		debug(running) {stderr.writeln("Loading state...");}
		time = Clock.currTime();
		bot.load(state);
		debug(running) {stderr.writeln("State loaded (", Clock.currTime() - time, ").");}
	}

	string text;
	auto time = Clock.currTime();
	debug(running) {stderr.writeln("Reading input...");}
	while ((text = stdin.readln().strip) !is null) {
		if (text.length > 0) {
			debug(running) {stderr.writeln("Answering and learning ", text, "...");}

			if (answer) {
				string answer_text = bot.answer(text);
				if (answer_text.length > 0) {
					stdout.writeln(answer_text);
				}
			}

			if (learn) {
				bot.learn(text);
			}
		}
	}
	debug(running) {stderr.writeln("Input read (", Clock.currTime() - time, ").");}
	time = Clock.currTime();
	debug(running) {stderr.writeln("Organizing sentences...");}
	bot.organize();
	debug(running) {stderr.writeln("Sentences organized (", Clock.currTime() - time, ").");}

	time = Clock.currTime();
	debug(running) {stderr.writeln("Writing state to ", statefile, "...");}
	std.file.write(statefile, bot.save());
	debug(running) {stderr.writeln("State written (", Clock.currTime() - time, ").");}

	return 0;
}

class Bot {
	private Sentence[] sentences;
	private int length = 2;

	private Candidate[string][string] candidates_after;
	private Candidate[string][string] candidates_before;
	private int[string] frequencies;

	this() {}

	void learn(string text) {
		text = std.array.replace(text, " ?", "?");
		text = std.array.replace(text, " !", "!");

		text = std.array.replace(text, "?", "?. ");
		text = std.array.replace(text, "!", "!. ");
		text = std.array.replace(text, "(", ". ");
		text = std.array.replace(text, ")", ". ");

		string[] lines = text.split(". ");

		foreach (string line; lines) {
			Sentence sentence = new Sentence(line);
			
			if (sentence.meaningful) {
				this.sentences ~= sentence;

				debug(learning) {stderr.writeln("Learnt sentence: ", sentence);}
			} else {
				debug(learning) {stderr.writeln("Discarded sentence: ", line);}
			}
		}
	}

	void organize() {
		GC.disable();

		foreach (Sentence sentence; this.sentences) {
			if (sentence.length > this.length) {
				debug(learning) {stderr.writeln("Organizing sentence ", sentence);}
				for (int i = 0; i <= sentence.length - this.length; i++) {
					string index = sentence[i..i+2].join(" ");
					string word = i+2 < sentence.length ? sentence[i+2] : "<end>";

					if (index !in this.frequencies) {
						this.frequencies[index] = 1;
					} else {
						this.frequencies[index]++;
						debug(learning) debug(verbose) {stderr.writeln("Frequency of ", index, " is ", frequencies[index], " (in ", sentence, ")");}
					}

					if (index !in this.candidates_after || word !in this.candidates_after[index]) {
						this.candidates_after[index][word] = new Candidate(word);
						debug(learning) debug(verbose) {stderr.writeln("Added new candidate: ", index, "... ", word);}
					} else {
						this.candidates_after[index][word].weight++;
					}
				}

				for (int i = 0; i <= sentence.length - this.length; i++) {
					string index = sentence[i..i+2].join(" ");
					string word = i > 0 ? sentence[i-1] : "<start>";

					if (index !in this.candidates_before || word !in this.candidates_before[index]) {
						this.candidates_before[index][word] = new Candidate(word);
						debug(learning) debug(verbose) {stderr.writeln("Added new candidate: ", index, "... ", word);}
					} else {
						this.candidates_before[index][word].weight++;
					}
				}
			}
		}
		GC.enable();

		debug(learning) {stderr.writeln("Found ", this.candidates_after.length, " chains");}
	}

	string answer(string text) {
		Sentence sentence = new Sentence(text);

		if (!sentence.meaningful()) {
			debug(answering) {stderr.writeln("Sentence is meaningless (", text, ")");}
			return "";
		}

		int popularity = int.max;
		string seed = "";

		for (int i = 0; i < sentence.length - this.length; i++) {
			string index = sentence[i..i+2].join(" ");

			int frequency = index in this.frequencies ? this.frequencies[index] : 0;
			debug(answering) {stderr.writeln("Frequency of ", index, " is ", frequency);}

			if (frequency > WORD_POPULARITY_THRESHOLD && frequency < popularity) {
				popularity = frequency;
				seed = index;
			}
		}

		debug(answering) {stderr.writeln("Seed is ", seed, " seen ", popularity, " times");}

		if (seed == "") {
			return "";
		}

		string answer = seed;
		string next_word = this.next_word(seed);

		while (next_word && next_word != "<end>") {
			debug(answering) {stderr.writeln("Answer is ", answer, "... ", next_word);}
			answer ~= " " ~ next_word;

			string[] parts = split(answer, " ");
			next_word = this.next_word(parts[$-2 .. $].join(" "));
		}
		if (next_word == "<end>") {
			if (answer[$-1] != '!' && answer[$-1] != '?') {
				answer ~= ".";
			}
		}

		string previous_word = this.previous_word(seed);
		while (previous_word && previous_word != "<start>") {
			debug(answering) {stderr.writeln("Answer is ", previous_word, "... ", answer);}
			answer = previous_word ~ " " ~ answer;

			string[] parts = split(answer, " ");
			previous_word = this.previous_word(parts[0 .. 2].join(" "));
		}
		if (previous_word == "<start>") {
			answer = answer.capitalize();
		}

		answer = std.array.replace(answer, "?", " ?");
		answer = std.array.replace(answer, "!", " !");

		return answer;
	}

	string next_word(string seed) {
		if (seed in this.candidates_after) {
			debug(answering) {stderr.writeln(this.candidates_after[seed].length, " candidates after ", seed, "...");}
			return this.choose(this.candidates_after[seed]).toString();
		}

		return null;
	}

	string previous_word(string seed) {
		if (seed in this.candidates_before) {
			debug(answering) {stderr.writeln(this.candidates_before[seed].length, " candidates before ", seed, "...");}
			return this.choose(this.candidates_before[seed]).toString();
		}

		return null;
	}

	void load(string data) {
		string[] lines = data.split("\n");

		GC.disable();

		foreach (string line; lines) {
			if (line.length < 3) {
				continue;
			}

			string[] parts = line.split("\t");
			
			switch (parts[0]) {
				case "a":
					this.candidates_after[parts[1]][parts[2]] = new Candidate(parts[2], to!int(parts[3]));
					break;
				case "b":
					this.candidates_before[parts[1]][parts[2]] = new Candidate(parts[2], to!int(parts[3]));
					break;
				case "f":
					this.frequencies[parts[1]] = to!int(parts[2]);
					break;
				default:
					break;
			}
		}

		GC.enable();
	}

	string save() {
		string data = "";

		foreach (string index, Candidate[string] candidates; this.candidates_after) {
			foreach (Candidate candidate; candidates) {
				data ~= std.string.format("a\t%s\t%s\t%s\n", index, candidate, candidate.weight);
			}
		}

		foreach (string index, Candidate[string] candidates; this.candidates_before) {
			foreach (Candidate candidate; candidates) {
				data ~= std.string.format("b\t%s\t%s\t%s\n", index, candidate, candidate.weight);
			}
		}

		foreach (string index, int frequency; this.frequencies) {
			data ~= std.string.format("f\t%s\t%s\n", index, frequency);
		}

		return data;
	}

	Candidate choose(Candidate[string] candidates) {
		int[Candidate] weights;
		foreach (Candidate candidate; candidates) {
			weights[candidate] = candidate.weight;
		}
		size_t index = dice(weights.values);

		return weights.keys[index];
	}
}

class Candidate {
	private string text;
	public int weight = 1;

	this(string text, int weight = 1) {
		this.text = text;
		this.weight = weight;
	}

	override string toString() {
		return this.text;
	}
}

class Sentence {
	private string text;
	private Word[] words;

	this(string text) {
		this.text = text.strip();
		this.clean();
		this.parse();
	}

	void clean() {
		this.text = std.array.replace(this.text, `"`, ``);
	}

	void parse() {
		foreach (string part; splitter(this.text)) {
			Word word = new Word(part);

			if (word.meaningful) {
				this.words ~= new Word(part);
			}
		}
	}

	bool meaningful() {
		return this.words.length > 2;
	}

	string opIndex(size_t i) {
		return words[i].toString();
	}

	string[] opSlice(size_t i, size_t j) {
		string[] words_text;
		foreach (Word word; words[i..j]) {
			words_text ~= word.toString();
		}
		return words_text;
	}

	size_t length() {
		return this.words.length;
	}

	int opApply(int delegate(ref Word) dg) {
		int result = 0;

		for (int i = 0; i < this.words.length; i++) {
			result = dg(this.words[i]);
			if (result) {
				break;
			}
		}
		return result;
	}

	override string toString() {
		string text;
		foreach (Word word; this.words) {
			text ~= word.toString() ~ " ";
		}
		return text;
	}
}

class Word {
	private string text;

	this(string text) {
		this.text = text;
	}

	bool meaningful() {
		return !matchFirst(this.text, `^\p{L}`).empty() && (this.text.length < 5 || this.text[0..5] != "href=");
	}

	override string toString() {
		return this.text;
	}
}

