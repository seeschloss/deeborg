module deeborg.main;

private import deeborg.bot;

private import std.string;
private import std.getopt;
private import std.stdio;

immutable WORD_POPULARITY_THRESHOLD = 1;

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

	bool show_help = false;

	try {
		getopt(
			args,
			"learn", &learn,
			"answer", &answer,
			"file", &statefile,
			"depth", &depth,
			"handle", &handle,
			"help", &show_help
		);
	} catch (Exception e) {
		help();
		return 1;
	}

	if (show_help) {
		help();
		return 0;
	}

	tmpstatefile = statefile ~ ".tmp";

	Bot bot = new Bot(statefile);
	bot.depth = depth;
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

			stdout.writeln(answer_sentence);
		}

		if (learn) {
			bot.learn(sentence);
		}
	}

	return 0;
}


