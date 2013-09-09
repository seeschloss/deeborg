deeborg
=======

Deeborg is a simple Markov chains bot, based on the old PyBorg (http://sebastien.dailly.free.fr/pyborg.html, in French).

```
  Usage: deeborg [--file=<word database>] [--learn=false] [--answer=false]
  
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
```

Performance has not been tested extensively, but behaviour should be about the same as PyBorg.
