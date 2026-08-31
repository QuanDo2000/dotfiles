export interface FastModeModel {
  provider: string;
  id: string;
}

const SUPPORTED_MODELS = new Set([
  "openai-codex/gpt-5.6-luna",
  "openai-codex/gpt-5.6-sol",
]);

export function isFastModeModel(model: FastModeModel | undefined): boolean {
  return model !== undefined && SUPPORTED_MODELS.has(`${model.provider}/${model.id}`);
}

export function rewriteFastModeProviderRequest(
  payload: unknown,
  enabled: boolean,
  model: FastModeModel | undefined,
): unknown {
  if (!enabled || !isFastModeModel(model) || !payload || typeof payload !== "object" || Array.isArray(payload)) {
    return payload;
  }
  return { ...payload, service_tier: "priority" };
}
