// Wall-clock tok/s meter: first-token to final-output elapsed time.

export function createTpsMeter() {
  let genStartedAt = 0;
  let lastTps = 0;
  let estTokens = 0;
  let realTokens = 0;
  let liveTps = 0;
  return {
    // Real per-delta usage counts (anthropic/mistral) override the estimate.
    noteDelta(usageOutput: unknown) {
      if (genStartedAt === 0) {
        genStartedAt = Date.now();
        estTokens = 0;
        realTokens = 0;
      }
      estTokens += 1;
      if (typeof usageOutput === "number" && usageOutput > 0) realTokens = usageOutput;
      const elapsed = genStartedAt ? (Date.now() - genStartedAt) / 1000 : 0;
      if (elapsed >= 0.1) liveTps = (realTokens > 0 ? realTokens : estTokens) / elapsed;
    },
    noteGeneration(outputTokens: unknown) {
      const elapsed = genStartedAt ? (Date.now() - genStartedAt) / 1000 : 0;
      genStartedAt = 0;
      estTokens = 0;
      realTokens = 0;
      liveTps = 0;
      // Under 100 ms the whole message arrived in one delta, where the division
      // says more about scheduling than about the model.
      if (typeof outputTokens === "number" && outputTokens > 0 && elapsed >= 0.1) {
        lastTps = outputTokens / elapsed;
      }
    },
    get tps() {
      return liveTps > 0 ? liveTps : lastTps;
    },
  };
}
