<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Account Balance</title>
</head>
<body>
  <h1>Check Account Balance</h1>
  <input id="accountId" placeholder="Account ID (e.g. 1001)">
  <button id="check">Get Balance</button>
  <p id="result"></p>
  <script>
    const API_URL = "${api_url}";
    document.getElementById("check").onclick = async () => {
      const out = document.getElementById("result");
      try {
        const r = await fetch(API_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ accountId: document.getElementById("accountId").value })
        });
        const data = await r.json();
        out.textContent = r.ok ? "Balance: $" + data.balance : "Error: " + data.error;
      } catch (e) {
        out.textContent = "Request failed: " + e.message;
      }
    };
  </script>
</body>
</html>
