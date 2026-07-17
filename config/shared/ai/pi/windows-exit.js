module.exports = (pi) => {
  pi.registerCommand("exit", {
    description: "Quit pi",
    handler: (_args, ctx) => ctx.shutdown(),
  });
};
