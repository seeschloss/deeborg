var WORD_POPULARITY_THRESHOLD = 2;
var LOOKAHEAD_DEPTH = 2;

var Bot = function() {
	this.sentences = [];
	this.candidates_after = {};
	this.candidates_before = {};
	this.frequencies = {};
};

Bot.prototype.learn = function(text) {
	var self = this;

	text = text.replace(/ \?/g, "?");
	text = text.replace(/ !/g, "!");
	text = text.replace(/\?/g, "?. ");
	text = text.replace(/!/g, "!. ");
	text = text.replace(/\(/g, ". ");
	text = text.replace(/\)/g, ". ");
	text = text.replace(/ : /g, ". ");

	var lines = text.split(/\. /);

	lines.forEach(function(line) {
		var sentence = new Sentence(line);
		if (sentence.meaningful()) {
			self.sentences.push(sentence);
		}
	});
};

Bot.prototype.organize = function() {
	var self = this;

	this.sentences.forEach(function(sentence) {
		if (sentence.words.length > LOOKAHEAD_DEPTH) {
			for (var i = 0; i <= sentence.words.length - LOOKAHEAD_DEPTH; i++) {
				var index = sentence.words.slice(i, i+LOOKAHEAD_DEPTH).join(' ');
				var word = i+LOOKAHEAD_DEPTH < sentence.words.length ? sentence.words[i+LOOKAHEAD_DEPTH] : new Word('<end>');

				if (!(index in self.frequencies)) {
					self.frequencies[index] = 1;
				} else {
					self.frequencies[index]++;
				}

				if (!(index in self.candidates_after)) {
					self.candidates_after[index] = {};
				}

				if (!(word in self.candidates_after[index])) {
					self.candidates_after[index][word] = new Candidate(word.text);
				} else {
					self.candidates_after[index][word].weight++;
				}
			}

			for (var i = 0; i <= sentence.words.length - LOOKAHEAD_DEPTH; i++) {
				var index = sentence.words.slice(i, i+LOOKAHEAD_DEPTH).join(' ');
				var word = i > 0 ? sentence.words[i-1] : new Word('<start>');

				if (!(index in self.candidates_before)) {
					self.candidates_before[index] = {};
				}

				if (!(word in self.candidates_before[index])) {
					self.candidates_before[index][word] = new Candidate(word.text);
				} else {
					self.candidates_before[index][word].weight++;
				}
			}
		}
	});

	this.sentences = [];
};

Bot.prototype.answer = function(text) {
	var sentence = new Sentence(text);

	if (!sentence.meaningful()) {
		return "";
	}

	var popularity = undefined;
	var seed = "";
	var after = "";
	var before = ""

	for (var i = 0; i < sentence.words.length - LOOKAHEAD_DEPTH; i++) {
		var index = sentence.words.slice(i, i+LOOKAHEAD_DEPTH).join(' ');

		var frequency = (index in this.frequencies) ? this.frequencies[index] : 0;

		if (frequency > WORD_POPULARITY_THRESHOLD && (popularity == undefined || frequency < popularity)) {
			popularity = frequency;
			seed = index;

			after = i+LOOKAHEAD_DEPTH < sentence.words.length ? sentence.words[i+LOOKAHEAD_DEPTH] : new Word('<end>');
			before = i > 0 ? sentence.words[i-1] : new Word('<start>');
		}
	}

	if (seed == "") {
		return "";
	}

	var words = LOOKAHEAD_DEPTH;

	var answer = seed;
	var next_word = this.next_word(seed, after);

	while (next_word && next_word != "<end>") {
		answer += " " + next_word;
		words++;

		var parts = answer.split(/ /);
		next_word = this.next_word(parts.slice(parts.length-LOOKAHEAD_DEPTH, parts.length).join(' '));
	}
	if (next_word == '<end>') {
		if (answer[answer.length-1] != '!' && answer[answer.length-1] != '?') {
			answer += '.';
		}
	}

	var previous_word = this.previous_word(seed, before);
	while (previous_word && previous_word != "<start>") {
		answer = previous_word + " " + answer;
		words++;

		var parts = answer.split(/ /);
		previous_word = this.previous_word(parts.slice(0, LOOKAHEAD_DEPTH).join(' '));
	}
	if (previous_word == "<start>") {
		answer = answer.charAt(0).toUpperCase() + answer.slice(1);
	}

	if (words == LOOKAHEAD_DEPTH) {
		// No new word was found to complete the sentence.
		return "";
	}

	answer = answer.replace(/\?/g, " ?");
	answer = answer.replace(/!/g, " !");

	return answer;
};

Bot.prototype.next_word = function(seed, exclude) {
	if (seed in this.candidates_after) {
		var choice = this.choose(this.candidates_after[seed], exclude);
		return choice ? choice.text : "";
	}

	return null;
};

Bot.prototype.previous_word = function(seed, exclude) {
	if (seed in this.candidates_before) {
		var choice = this.choose(this.candidates_before[seed], exclude);
		return choice ? choice.text : "";
	}

	return null;
};

Bot.prototype.load = function(data) {
	var self = this;

	data.split(/\n/).forEach(function(line) {
		var parts = line.split(/\t/);
		
		switch (parts[0]) {
			case "a":
				if (!(parts[1] in self.candidates_after)) {
					self.candidates_after[parts[1]] = {};
				}
				self.candidates_after[parts[1]][parts[2]] = new Candidate(parts[2], +parts[3]);
				break;
			case "b":
				if (!(parts[1] in self.candidates_before)) {
					self.candidates_before[parts[1]] = {};
				}
				self.candidates_before[parts[1]][parts[2]] = new Candidate(parts[2], +parts[3]);
				break;
			case "f":
				self.frequencies[parts[1]] = +parts[2];
				break;
			case "d":
				LOOKAHEAD_DEPTH = +parts[1];
				break;
			default:
				break;
		}
	});
};

Bot.prototype.save = function() {
	var data = "";

	data += "d\t" + LOOKAHEAD_DEPTH + "\n";

	for (var index in this.candidates_after) {
		var candidates = this.candidates_after[index];

		for (var index2 in candidates) {
			var candidate = candidates[index2];
			data += "a\t" + index + "\t" + candidate.text + "\t" + candidate.weight + "\n";
		}
	}

	for (var index in this.candidates_before) {
		var candidates = this.candidates_before[index];

		for (var index2 in candidates) {
			var candidate = candidates[index2];
			data += "b\t" + index + "\t" + candidate.text + "\t" + candidate.weight + "\n";
		}
	}

	for (var index in this.frequencies) {
		var frequency = this.frequencies[index];
		data += "f\t" + index + "\t" + frequency + "\n";
	}

	return data;
};

Bot.prototype.choose = function(candidates, exclude) {
	var total = 0;

	for (var index in candidates) {
		var candidate = candidates[index];
		total += candidate.weight;
	}

	var weights = [];
	var offset = 0;

	for (var index in candidates) {
		var candidate = candidates[index];

		if (candidate.weight > 0 && (!exclude || exclude.length <= 3 || candidate.text != exclude)) {
			weights.push({
				candidate: candidate,
				threshold: candidate.weight/total + offset
			});

			offset += candidate.weight/total;
		}
	}

	if (weights.length == 0) {
		return "";
	}

	weights.sort(function(a, b) {return a.threshold < b.threshold ? -1 : 1;});

	var random = Math.random();
	
	for (var i in weights) {
		var weight = weights[i];
		if (weight.threshold < random) {
			return weight.candidate;
		}
	}

	return weights[weights.length - 1].candidate;
};

var Candidate = function(text, weight) {
	this.text = text;
	this.weight = weight ? weight : 1;
};

Candidate.prototype.toString = function() {
	return this.text;
};

var Sentence = function(text) {
	this.text = text;
	this.words = [];

	this.clean();
	this.parse();
};

Sentence.prototype.clean = function() {
	this.text = this.text.replace(/^\s+|\s+$/g, '');
	this.text = this.text.replace(/"/, '');
};


Sentence.prototype.parse = function() {
	var self = this;

	this.text.split(/ /).forEach(function(part) {
		var word = new Word(part);

		if (word.meaningful()) {
			self.words.push(word);
		}
	});
};

Sentence.prototype.meaningful = function() {
	return this.words.length > LOOKAHEAD_DEPTH;
};

Sentence.prototype.toString = function() {
	var text = "";
	this.words.forEach(function(word) {
		text += word.text + " ";
	});
	return text;
};

var Word = function(text) {
	this.text = text;
}

Word.prototype.meaningful = function() {
	return !this.text.match(/^[0-9<>]/) && !this.text.match(/^href=/);
};

Word.prototype.toString = function() {
	return this.text;
};

if (typeof exports != 'undefined') {
	exports.Bot = Bot;
}

