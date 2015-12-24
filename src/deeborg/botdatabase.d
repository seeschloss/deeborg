module deeborg.botdatabase;

interface BotDatabase {
	void learn_sentence(string[]);
	string rarest_word(string[] words);
	size_t[string] candidates_before(string[] words);
	size_t[string] candidates_after(string[] words);
}

