# Web-access extension ablations

Map capabilities before choosing the control. Hosted search, URL fetching, document extraction, repository cloning, and video understanding are different surfaces; `curl` is a fetch fallback, not an equivalent search backend. If an extension reuses the active model provider's login to call hosted search, removing the extension still removes that search capability even though provider authentication remains.

Record the resolved runtime route, endpoint class, provider/model, fallback order, and whether credentials came from the agent registry or separate configuration—without exposing credential values. Probe the actual route rather than inferring it from package marketing. Keep provider-vs-provider tuning separate from the first keep/remove decision, and cover freshness, citation/source accuracy, extraction fidelity, failure/fallback behavior, SSRF/domain policy, startup/RSS/schema overhead, and natural selection.
