const http = require("http");

const port = Number(process.env.PORT || 3000);

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }

  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("healthy");
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("not found");
});

server.listen(port, "0.0.0.0", () => {
  console.log(`listening on ${port}`);
});
