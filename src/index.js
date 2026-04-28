// _worker.js
// Cloudflare Pages "Advanced Mode" worker: serves the static site and
// adds a /hf/* route that proxies to huggingface.co. Transformers.js
// fetches model files via /hf/<repo>/resolve/<rev>/<file>, which lands
// here, gets forwarded to https://huggingface.co/... with redirects
// followed server-side, and comes back with permissive CORS headers.
//
// Why proxy: model fetches are same-origin from the browser's view,
// so any CORS variance (cached failures, networks that strip ACAO,
// extensions interfering) becomes irrelevant. The browser only sees
// responses from this origin.

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith('/hf/')) {
      return proxyHuggingFace(request, url);
    }

    // Otherwise serve the static site.
    return env.ASSETS.fetch(request);
  },
};

async function proxyHuggingFace(request, url) {
  // CORS preflight: respond directly. Browsers should rarely send one
  // for a same-origin request, but harmless to handle.
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: corsHeaders({
        'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
        'Access-Control-Allow-Headers': 'range, accept, if-modified-since, if-none-match',
        'Access-Control-Max-Age': '86400',
      }),
    });
  }

  const path = url.pathname.slice('/hf/'.length);
  const target = `https://huggingface.co/${path}${url.search}`;

  // Forward only headers HF cares about for content negotiation and
  // partial fetches. Cookies / Authorization stay out — this is a
  // public unauthenticated proxy.
  const fwd = new Headers();
  for (const name of ['range', 'accept', 'if-modified-since', 'if-none-match']) {
    const v = request.headers.get(name);
    if (v) fwd.set(name, v);
  }

  const upstream = await fetch(target, {
    method: request.method,
    headers: fwd,
    redirect: 'follow',
  });

  const headers = new Headers(upstream.headers);
  // Override anything HF set that might confuse the browser:
  for (const [k, v] of Object.entries(corsHeaders())) headers.set(k, v);
  // Remove headers that don't make sense after a server-side redirect
  // (Location is gone; CORP from upstream is replaced by ours).
  headers.delete('content-security-policy');

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers,
  });
}

function corsHeaders(extra) {
  return {
    'Access-Control-Allow-Origin': '*',
    'Cross-Origin-Resource-Policy': 'cross-origin',
    'Vary': 'Origin',
    ...(extra || {}),
  };
}
