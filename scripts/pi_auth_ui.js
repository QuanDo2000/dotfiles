// Loaded only by pi_auth.py; keep login guidance visible in Pi's full-screen UI.
module.exports = function providerLoginGuide(pi) {
  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;
    const missing = new Set((process.env.DOTFILE_PI_AUTH_MISSING || "").split(","));
    const lines = ["Pi provider setup - complete the missing logins below:"];
    if (missing.has("openai-codex")) {
      lines.push("/login openai-codex - follow the browser link to connect your subscription.");
    }
    if (missing.has("openrouter")) {
      lines.push("/login openrouter - enter your API key only in Pi's login UI.");
    }
    lines.push("Then /quit to return to setup and verify your logins.");
    ctx.ui.setWidget("dotfile-provider-login", lines);
  });
};
