Deeborg is a simple Markov chains bot, based on the old PyBorg (http://sebastien.dailly.free.fr/pyborg.html, in French).

Performance has not been tested extensively, but behaviour should be about the same as PyBorg.

```
Usage: deeborg  [options ...]

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

```

Building
======

Deeborg can be built using [Dub](https://github.com/D-Programming-Language/dub/), just execute:

    dub -b release

and it should compile fine. If it doesn't, well, submit an issue or something.


Using
=======

To use it, you should first feed your bot a meaningful corpus.

Since it is primarily intended for animating *tribunes* (like [LinuxFR.org's](https://linuxfr.org/board)) a few patterns are handled in a special way: *HH:MM:SS* is completely ignored, and *word<* is treated as a nickname. Sentences are ended by ".", "?", "!" or newlines.

Just feed your input corpus on standard input like this, disabling answers so the bot doesn't waste its time when all it should do is learn:

    deeborg --answer=false < corpus.txt

Then check if it answers sensible things without polluting its database:

    echo "Hello there, how are you my dear?" | deeborg --learn=false

And you're set.
