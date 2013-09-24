deeborg
=======

Deeborg is a simple Markov chains bot, based on the old PyBorg (http://sebastien.dailly.free.fr/pyborg.html, in French).

```
  Usage: deeborg [--file=<word database>] [--learn=false] [--answer=false]
  
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

  
  Unless learning or answering are disabled, each line fed on stdin
  will be read and answered to use Markov chains and the existing
  word database. Each line will then be parsed into sentences
  and added to the database, and the next line will be processed.
```

Performance has not been tested extensively, but behaviour should be about the same as PyBorg.
