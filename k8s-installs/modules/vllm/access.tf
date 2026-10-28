# Who can call this model (README "Who can call this model"). Network identity
# by default: the internal gateway refuses this hostname to any address outside
# the owner's and approved consumers' CIDRs, and stamps the caller's name on
# the request. OIDC tokens as an option.
locals {
  access_defaults = {
    owner_cidrs = [] # Backstage writes the owner environment's VPC CIDR(s)
    consumers   = {} # name => { cidrs = [...], weight = 1 }; Backstage writes approved ones
    oidc        = { issuer = null, jwks_uri = null, audiences = [], consumer_claim = "azp" }
  }
  access    = merge(local.access_defaults, try(module.context.spec.access, {}))
  oidc      = merge(local.access_defaults.oidc, try(module.context.spec.access.oidc, {}))
  oidc_on   = local.oidc.issuer != null
  tier      = module.context.tier
  shared    = length(local.access.consumers) > 0
  access_on = length(local.access.owner_cidrs) > 0 || local.oidc_on

  owner = try(module.context.config.tags["owner.team"], "owner")
  # Owner first: an address in both is the owner's.
  identities = concat(
    [for c in local.access.owner_cidrs : { name = local.owner, cidr = c }],
    flatten([for name in sort(keys(local.access.consumers)) : [for c in local.access.consumers[name].cidrs : { name = name, cidr = c }]]),
  )
  allowed_cidrs = [for i in local.identities : i.cidr]

  # The gateway runs one of these per model; each acts on its own hostname only.
  # replace, never add: a client can't name itself.
  consumer_lua = local.access_on && !local.oidc_on ? join("\n", [
    "local host = \"${local.hostname}\"",
    "local nets = {",
    join(",\n", [for i in local.identities : "  { \"${i.name}\", \"${i.cidr}\" }"]),
    "}",
    <<-LUA
    local function num(ip)
      local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
      if not a then return nil end
      return ((tonumber(a) * 256 + tonumber(b)) * 256 + tonumber(c)) * 256 + tonumber(d)
    end
    local function within(ip, cidr)
      local base, len = cidr:match("^(.+)/(%d+)$")
      local size = 2 ^ (32 - tonumber(len))
      return math.floor(ip / size) == math.floor(num(base) / size)
    end
    function envoy_on_request(handle)
      local headers = handle:headers()
      local authority = (headers:get(":authority") or ""):gsub(":%d+$", "")
      if authority ~= host then return end
      local ip = num((handle:streamInfo():downstreamRemoteAddress() or ""):match("^([%d%.]+)") or "")
      local who = "unknown"
      if ip then
        for _, net in ipairs(nets) do
          if within(ip, net[2]) then who = net[1] break end
        end
      end
      headers:replace("x-phoenix-consumer", who)
      headers:replace("x-gateway-inference-fairness-id", who)
    end
    LUA
  ]) : ""

  access_values = {
    hostname     = local.hostname
    gateway      = { name = try(local.gateway.name, ""), namespace = try(local.gateway.namespace, "") }
    allowedCidrs = local.allowed_cidrs
    consumerLua  = local.consumer_lua
    oidc = local.oidc_on ? {
      issuer        = local.oidc.issuer
      jwksUri       = local.oidc.jwks_uri
      audiences     = local.oidc.audiences
      consumerClaim = local.oidc.consumer_claim
    } : null
  }
}
