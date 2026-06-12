const express = require("express");
const app = express();

app.get("/", (req, res) => {
  res.json({
    message: "Hello CI/CD",
    version: process.env.APP_VERSION || "dev",
  });
});

app.get("/health", (req, res) => {
  res.status(200).send("OK");
});

function add(a, b) {
  return a + b;
}

module.exports = { app, add };

if (require.main === module) {
  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => console.log(`Listening on ${PORT}`));
}
