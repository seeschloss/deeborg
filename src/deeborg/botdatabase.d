module deeborg.botdatabase;

interface BotDatabase {
	/*
	 * Learn an ordered array of words
	 */
	void learn_sentence(string[]);

	/*
	 * Return which word is the least commonly used one among an array
	 */
	string rarest_word(string[] words);

	/*
	 * Suggest words that could be placed before or after a list of words
	 * as an array of weights indexed by words
	 */
	size_t[string] candidates_before(string[] words);
	size_t[string] candidates_after(string[] words);
}

