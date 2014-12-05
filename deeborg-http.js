// vim:et:sw=2
/**
 * Module dependencies.
 */

var http = require('http');
var fs = require('fs');
var deeborg = new (require('./deeborg.js').Bot)();

var db_file = process.env.DATABASE || "deeborg.db";
var port = process.env.PORT || 3000;
var bind = process.env.BIND || "0.0.0.0";

process.on('SIGINT', function() {process.exit();});
process.on("exit", exit);

function exit() {
	console.log("Saving database...");
	var db = deeborg.save();
	fs.writeFileSync(db_file, db);
	process.exit();
}

try {
	var db = fs.readFileSync(db_file);
	deeborg.load(db.toString());
} catch (e) {
	console.log("Database '" + db_file + "' does not exist,\nbot will not be able to answer much before it has learnt for a while.");
}

console.log("Listening on port " + port + "...");
http.createServer(function(request, response) {
	switch (request.method) {
		case "POST":
			var question = "";
			request.on("data", function(data) {
				question += data;

				if (question.length > 1024) {
					request.connection.destroy();
				}
			});
			request.on("end", function() {
				respondTo(question, request, response);
			});
			break;
		case "GET":
			var question = decodeURI(request.url.substr(2));
			respondTo(question, request, response);
			break;
	}
}).listen(port, bind);

function respondTo(question, request, response) {
	var answer = deeborg.answer(question);

    if (answer.length > 0) {
      response.writeHead(200, {"Content-Type": "text/plain; charset=utf8"});
      response.write(answer + "\n");
    } else {
      response.writeHead(418, {"Content-Type": "text/plain; charset=utf8"});
      response.write("<empty>\n");
    }
	response.end();

	console.log("Answered '" + answer + "' to '" + question + "'");

	deeborg.learn(question);
	deeborg.organize();
}

